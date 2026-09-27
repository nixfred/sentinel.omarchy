# Surprise 4: SENTINEL (nixfred.sentinel)
Systemd + journal watchdog. Bar: shield glyph, green when 0 failed units, red count otherwise, amber on journal error burst.
Panel: failed units (system+user) with restart/logs buttons, next 10 timers countdown, journal err/crit rate sparkline since boot, top 5 noisy units.
Why: gus runs a dozen+ custom user services (npu-embed, k3-dictate-hold, backup, clipsync) and they die silently; nothing on the bar says so.
Runner-ups: Pacwatch (pending updates age; Omarchy already nags updates), Bootlog (boot time history; OMW-038 notification covers it).
Coordination: surprise1 SHIPYARD, surprise2 HOURGLASS; surprise4-8 are this session.
