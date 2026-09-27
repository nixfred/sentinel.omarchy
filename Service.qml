import QtQuick
import Quickshell
import Quickshell.Io

// One poll of sentinel.py, relayed to the bar and the panel, plus the
// Restart and Logs actions.
Item {
  id: root

  property var settings: ({})
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\/(localhost)?/, ""))

  property bool ready: false
  property bool ok: true
  property string error: ""
  property string lastAction: ""
  property var data: ({})
  readonly property int failedCount: (data.failed || []).length
  readonly property bool burst: !!(data.journal && data.journal.burst)
  readonly property int hourErr: data.journal ? data.journal.hour : 0
  // 0 ok, 1 burst, 2 failed
  readonly property int level: !ready ? 0 : (failedCount > 0 ? 2 : (burst ? 1 : 0))

  readonly property int refreshSec: {
    var n = parseInt(String(settings && settings.refreshSec !== undefined ? settings.refreshSec : 30), 10)
    return isFinite(n) ? Math.max(10, Math.min(600, n)) : 30
  }

  function apply(text) {
    var d
    try { d = JSON.parse(text) } catch (e) { ok = false; error = "bad JSON from sentinel.py"; ready = true; return }
    ok = !!d.ok
    error = d.error || ""
    if (d.ok) data = d
    ready = true
  }

  Process {
    id: poll
    command: ["python3", root.pluginDir + "sentinel.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Process {
    id: act
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { var r = JSON.parse(text); root.lastAction = r.ok ? "restarted" : ("restart failed: " + r.error) }
        catch (e) { root.lastAction = "restart: no reply" }
        root.refresh()
      }
    }
  }
  Process { id: term }

  function refresh() { if (!poll.running) poll.running = true }
  function restart(scope, unit) {
    if (act.running) return
    lastAction = "restarting " + unit + "..."
    act.command = ["python3", root.pluginDir + "sentinel.py", "restart", scope, unit]
    act.running = true
  }
  function logs(scope, unit) {
    var flag = scope === "user" ? "--user-unit" : "--unit"
    term.command = ["omarchy-launch-floating-terminal-with-presentation",
                    "journalctl -b " + flag + " " + unit + " -n 300 -e --no-hostname"]
    term.running = true
  }
  function journalErrors() {
    term.command = ["omarchy-launch-floating-terminal-with-presentation",
                    "journalctl -b -p 0..3 -e --no-hostname"]
    term.running = true
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
