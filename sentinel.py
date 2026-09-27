#!/usr/bin/env python3
"""Sentinel collector: systemd + journal watchdog for the Omarchy bar.

Read-only. Prints one JSON object. Every number comes straight from
systemctl / journalctl; nothing is estimated.

  sentinel.py            -> status JSON
  sentinel.py restart <scope> <unit>   (scope = user|system)
"""
import json
import os
import subprocess
import sys
import time

BUCKETS = 48          # sparkline buckets from boot to now
BURST_WINDOW = 300    # seconds
BURST_LIMIT = 20      # err+ lines in the window that count as a burst


def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def sysctl(scope, *args):
    base = ["systemctl", "--no-pager"]
    if scope == "user":
        base.append("--user")
    return run(base + list(args))


def jload(text, default):
    try:
        return json.loads(text)
    except ValueError:
        return default


def failed_units():
    out = []
    for scope in ("system", "user"):
        _, t = sysctl(scope, "--failed", "-o", "json")
        for u in jload(t, []):
            name = u.get("unit", "")
            info = {"unit": name, "scope": scope, "desc": u.get("description", ""),
                    "sub": u.get("sub", ""), "since": "", "result": "", "restarts": 0}
            _, s = sysctl(scope, "show", name, "-p",
                          "Result,NRestarts,StateChangeTimestamp,ExecMainStatus")
            for line in s.splitlines():
                k, _, v = line.partition("=")
                if k == "Result":
                    info["result"] = v
                elif k == "NRestarts":
                    info["restarts"] = int(v or 0)
                elif k == "StateChangeTimestamp":
                    info["since"] = v
                elif k == "ExecMainStatus":
                    info["exit"] = v
            out.append(info)
    return out


def timers(now_us):
    rows = []
    for scope in ("system", "user"):
        _, t = sysctl(scope, "list-timers", "--all", "-o", "json")
        for r in jload(t, []):
            nxt = r.get("next") or 0
            if not nxt:
                continue
            rows.append({"unit": r.get("unit", ""), "scope": scope,
                         "activates": r.get("activates", ""),
                         "in": max(0, int((nxt - now_us) / 1e6)),
                         "last": int(r["last"] / 1e6) if r.get("last") else 0})
    rows.sort(key=lambda r: r["in"])
    return rows


def unit_counts():
    c = {}
    for scope in ("system", "user"):
        _, t = sysctl(scope, "list-units", "--type=service", "--all", "-o", "json")
        units = jload(t, [])
        c[scope] = {"total": len(units),
                    "running": sum(1 for u in units if u.get("sub") == "running"),
                    "failed": sum(1 for u in units if u.get("active") == "failed")}
        _, st = sysctl(scope, "is-system-running")
        c[scope]["state"] = st.strip() or "unknown"
    return c


def flapping():
    """User + system services that have been auto-restarted this boot."""
    rows = []
    for scope in ("system", "user"):
        _, t = sysctl(scope, "list-units", "--type=service", "--all", "-o", "json")
        names = [u["unit"] for u in jload(t, []) if u.get("load") == "loaded"]
        if not names:
            continue
        _, s = sysctl(scope, "show", *names, "-p", "Id,NRestarts")
        cur = {}
        for line in s.splitlines() + [""]:
            if not line:
                if cur.get("NRestarts", "0") not in ("0", ""):
                    rows.append({"unit": cur.get("Id", ""), "scope": scope,
                                 "n": int(cur["NRestarts"])})
                cur = {}
                continue
            k, _, v = line.partition("=")
            cur[k] = v
    rows.sort(key=lambda r: -r["n"])
    return rows[:6]


def journal(boot_ts, now):
    _, t = run(["journalctl", "-b", "-p", "0..3", "-o", "json", "--no-pager",
                "--output-fields=_SYSTEMD_UNIT,_SYSTEMD_USER_UNIT,SYSLOG_IDENTIFIER,PRIORITY"],
               timeout=20)
    span = max(1.0, now - boot_ts)
    spark = [0] * BUCKETS
    noisy = {}
    crit = err = recent = hour = 0
    last = 0
    for line in t.splitlines():
        e = jload(line, None)
        if not e:
            continue
        ts = int(e.get("__REALTIME_TIMESTAMP", 0)) / 1e6
        if ts < boot_ts:
            ts = boot_ts
        i = min(BUCKETS - 1, int((ts - boot_ts) / span * BUCKETS))
        spark[i] += 1
        pr = int(e.get("PRIORITY", 3) or 3)
        if pr <= 2:
            crit += 1
        else:
            err += 1
        if now - ts <= BURST_WINDOW:
            recent += 1
        if now - ts <= 3600:
            hour += 1
        last = max(last, ts)
        if e.get("_SYSTEMD_USER_UNIT"):
            src = ("user", e["_SYSTEMD_USER_UNIT"])
        else:
            src = ("system", e.get("_SYSTEMD_UNIT") or e.get("SYSLOG_IDENTIFIER") or "?")
        if isinstance(src[1], list):
            src = (src[0], src[1][0])
        noisy[src] = noisy.get(src, 0) + 1
    top = sorted(noisy.items(), key=lambda kv: -kv[1])[:5]
    return {"spark": spark, "bucketSec": int(span / BUCKETS), "crit": crit, "err": err,
            "recent": recent, "hour": hour, "burst": recent >= BURST_LIMIT,
            "burstLimit": BURST_LIMIT, "burstWindow": BURST_WINDOW,
            "lastAgo": int(now - last) if last else -1,
            "noisy": [{"unit": k[1], "scope": k[0], "n": v} for k, v in top]}


def disk_usage():
    _, t = run(["journalctl", "--disk-usage"])
    # "Archived and active journals take up 1.2G in the file system."
    for w in t.split():
        if w[:1].isdigit():
            return w
    return "?"


def status():
    now = time.time()
    with open("/proc/uptime") as f:
        up = float(f.read().split()[0])
    boot_ts = now - up
    failed = failed_units()
    j = journal(boot_ts, now)
    return {
        "ok": True,
        "generated": time.strftime("%H:%M:%S"),
        "host": os.uname().nodename,
        "kernel": os.uname().release,
        "uptime": int(up),
        "failed": failed,
        "timers": timers(int(now * 1e6))[:10],
        "counts": unit_counts(),
        "flapping": flapping(),
        "journal": j,
        "diskUsage": disk_usage(),
    }


def restart(scope, unit):
    if not unit or "/" in unit:
        return {"ok": False, "error": "bad unit"}
    if scope == "user":
        cmd = ["systemctl", "--user", "restart", unit]
    else:
        cmd = ["pkexec", "systemctl", "restart", unit]
    rc, _ = run(cmd, timeout=60)
    return {"ok": rc == 0, "error": "" if rc == 0 else "restart exited %d" % rc}


def main():
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == "restart":
            print(json.dumps(restart(sys.argv[2], sys.argv[3])))
        else:
            print(json.dumps(status()))
    except Exception as e:  # fail loudly, in-band
        print(json.dumps({"ok": False, "error": "%s: %s" % (type(e).__name__, e)}))


if __name__ == "__main__":
    main()
