import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Shield glyph: green when nothing failed, red with a count, amber on a
// journal error burst.
BarWidget {
  id: root
  moduleName: "nixfred.sentinel"
  property var anchorItem: button

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property int failed: svc ? svc.failedCount : 0
  readonly property int level: svc ? svc.level : 0

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined ? fallback : v
  }
  readonly property bool showRate: String(setting("showRate", false)) === "true"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  // Fixed semantic red/amber: some themes map urgent to green. Healthy follows the theme accent.
  readonly property color red: "#ff4d5e"
  readonly property color amber: "#f5a623"
  readonly property color levelColor: !svc || !svc.ok ? red
    : (level === 2 ? red : (level === 1 ? amber : Color.accent))

  // md-shield_check (F0565) / md-shield_alert (F0ECC) / md-shield_half_full (F0780), verified by glyph name
  readonly property string label: String.fromCodePoint(level === 2 ? 0xF0ECC : (level === 1 ? 0xF0780 : 0xF0565))
    + (failed > 0 ? " " + failed : "")
    + (showRate && svc ? "  " + svc.hourErr + "/h" : "")

  implicitWidth: vertical ? barSize : Math.max(Style.space(32), txt.implicitWidth + Style.space(16))
  implicitHeight: vertical ? Style.space(40) : barSize

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    active: false
    useActiveColor: false
    tooltipText: !svc ? "Sentinel: starting"
      : !svc.ok ? "Sentinel: " + svc.error
      : root.failed > 0 ? "Sentinel: " + root.failed + " failed unit" + (root.failed > 1 ? "s" : "")
      : root.level === 1 ? "Sentinel: journal error burst (" + svc.data.journal.recent + " err+ in 5 min)"
      : "Sentinel: all units healthy, " + svc.hourErr + " err+ lines in the last hour"

    Text {
      id: txt
      anchors.centerIn: parent
      text: root.label
      color: root.levelColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: root.level > 0
    }

    onPressed: function(code) {
      if (root.bar) root.bar.hideTooltip(root)
      root.toggle()
    }
  }

  readonly property bool opened: panel.opened
  function open() { panel.controller.show(); if (svc) svc.refresh() }
  function close() { panel.controller.hide() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  readonly property bool popoutSwitchClosing: false

  SentinelPanel {
    id: panel
    widget: root
  }
}
