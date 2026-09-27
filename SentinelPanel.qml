import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// The watch panel. Law 17: no page scroller. Three columns; only the
// failed-unit list scrolls, inside its own fixed box.
Panel {
  id: panel
  moduleName: "nixfred.sentinel"
  manageIpc: false

  required property var widget
  readonly property var svc: widget.svc
  readonly property var d: svc ? svc.data : ({})
  readonly property var j: d.journal || ({})
  readonly property var c: d.counts || ({ system: {}, user: {} })

  readonly property color foreground: widget.bar ? widget.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Util.alpha(foreground, 0.10)
  readonly property color accent: Color.accent
  readonly property color red: "#ff4d5e"
  readonly property color amber: "#f5a623"
  readonly property string fontFamily: widget.bar ? widget.bar.fontFamily : Style.font.family
  readonly property int panelWidth: Style.space(1240)
  readonly property int boxHeight: Style.space(300)

  function dur(s) {
    if (s < 0) return "--"
    if (s < 60) return s + "s"
    if (s < 3600) return Math.floor(s / 60) + "m" + (s % 60 < 10 ? "0" : "") + (s % 60) + "s"
    if (s < 86400) return Math.floor(s / 3600) + "h" + (Math.floor(s / 60) % 60 < 10 ? "0" : "") + (Math.floor(s / 60) % 60) + "m"
    return Math.floor(s / 86400) + "d" + Math.floor(s / 3600) % 24 + "h"
  }
  function stateColor(s) { return s === "running" ? accent : (s === "degraded" ? red : amber) }

  // Local 1 s tick so the timer countdowns move between polls.
  property int tick: 0
  property real polledAt: Date.now()
  Connections { target: panel.svc; function onDataChanged() { panel.polledAt = Date.now(); panel.tick = 0 } }
  Timer { interval: 1000; repeat: true; running: panel.opened; onTriggered: panel.tick = Math.floor((Date.now() - panel.polledAt) / 1000) }

  component Stat: Rectangle {
    property string label: ""
    property string value: ""
    property string tip: ""
    property color valueColor: panel.foreground
    Layout.fillWidth: true
    implicitHeight: Style.space(58)
    radius: Style.space(6)
    color: panel.faint
    border.width: 1
    border.color: Util.alpha(valueColor, 0.45)
    Column {
      anchors.centerIn: parent
      spacing: Style.space(2)
      Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.value
             color: parent.parent.valueColor; font.family: panel.fontFamily
             font.pixelSize: Style.font.subtitle * 1.2; font.bold: true }
      Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.label
             color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall * 0.9
             font.letterSpacing: 1.5 }
    }
    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true }
    ToolTip.visible: sm.containsMouse && tip !== ""
    ToolTip.text: tip
  }

  component Caption: Text {
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.letterSpacing: 2
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property string tip: ""
    property color tint: panel.accent
    signal clicked()
    implicitWidth: ct.implicitWidth + Style.space(12)
    implicitHeight: Style.space(20)
    radius: 3
    color: cm.containsMouse ? Util.alpha(tint, 0.35) : Util.alpha(tint, 0.12)
    border.width: 1
    border.color: Util.alpha(tint, 0.6)
    Text { id: ct; anchors.centerIn: parent; text: chip.label; color: chip.tint
           font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall * 0.85; font.bold: true }
    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: chip.clicked() }
    ToolTip.visible: cm.containsMouse && tip !== ""
    ToolTip.text: tip
  }

  component Mono: Text {
    color: panel.foreground
    font.family: panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  KeyboardPanel {
    id: kpanel
    anchorItem: panel.widget.anchorItem
    owner: panel.widget
    bar: panel.widget.bar
    open: panel.opened
    focusTarget: keyCatcher
    contentWidth: kpanel.fittedContentWidth(panel.panelWidth)
    contentHeight: kpanel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: panel.widget.close()

      ColumnLayout {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          Text { text: panel.widget.label.substring(0, 2); color: panel.widget.levelColor
                 font.family: panel.fontFamily; font.pixelSize: Style.font.subtitle }
          Text { text: "SENTINEL"; color: panel.foreground; font.family: panel.fontFamily
                 font.pixelSize: Style.font.subtitle; font.bold: true; font.letterSpacing: 3 }
          Text {
            text: svc && !svc.ok ? ("error: " + svc.error)
                  : (d.host || "--") + "  //  " + (d.kernel || "") + "  //  polled " + (d.generated || "--")
                    + (svc && svc.lastAction ? "  //  " + svc.lastAction : "")
            color: svc && !svc.ok ? panel.red : panel.dim
            font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          Item { Layout.fillWidth: true }
          Chip { label: "ERR LOG"; tip: "Open this boot's err/crit/alert/emerg journal in a terminal"
                 onClicked: if (svc) svc.journalErrors() }
          Chip { label: "REFRESH"; tip: "Poll systemctl and the journal now"
                 onClicked: if (svc) svc.refresh() }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: panel.faint; border.width: 0 }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Stat { label: "FAILED"; value: String((d.failed || []).length)
                 valueColor: (d.failed || []).length ? panel.red : panel.accent
                 tip: "Failed units, system + user (systemctl --failed)" }
          Stat { label: "SYSTEM"; value: c.system.state || "--"; valueColor: panel.stateColor(c.system.state)
                 tip: "systemctl is-system-running" }
          Stat { label: "USER"; value: c.user.state || "--"; valueColor: panel.stateColor(c.user.state)
                 tip: "systemctl --user is-system-running" }
          Stat { label: "SYS SVC"; value: (c.system.running || 0) + "/" + (c.system.total || 0)
                 tip: "System services running / loaded" }
          Stat { label: "USER SVC"; value: (c.user.running || 0) + "/" + (c.user.total || 0)
                 tip: "User services running / loaded" }
          Stat { label: "ERR+ 5M"; value: String(j.recent || 0)
                 valueColor: j.burst ? panel.amber : panel.foreground
                 tip: "err+ journal lines in the last " + (j.burstWindow || 300) / 60 + " min. " + (j.burstLimit || 20) + " or more is a burst (amber shield)." }
          Stat { label: "ERR+ 1H"; value: String(j.hour || 0); tip: "err+ journal lines in the last hour" }
          Stat { label: "CRIT BOOT"; value: String(j.crit || 0); valueColor: j.crit ? panel.amber : panel.foreground
                 tip: "crit/alert/emerg lines since boot (priority 0..2)" }
          Stat { label: "UPTIME"; value: panel.dur(d.uptime || 0); tip: "Time since boot" }
          Stat { label: "JOURNAL"; value: d.diskUsage || "--"; tip: "journalctl --disk-usage (archived + active)" }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(16)

          // ---------------- col 1: failed units + auto-restarted
          ColumnLayout {
            Layout.preferredWidth: panel.panelWidth * 0.36
            Layout.maximumWidth: panel.panelWidth * 0.36
            Layout.alignment: Qt.AlignTop
            spacing: Style.space(8)

            Caption { text: "FAILED UNITS  //  system + user" }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(176)
              radius: Style.space(6); border.width: 1
              border.color: (d.failed || []).length ? Util.alpha(panel.red, 0.6) : "transparent"
              color: panel.faint
              clip: true
              ListView {
                id: failedList
                anchors.fill: parent; anchors.margins: Style.space(6)
                model: d.failed || []
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                Column {
                  anchors.centerIn: parent; visible: failedList.count === 0; spacing: Style.space(4)
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCodePoint(0xF0565)
                         color: panel.accent; font.family: panel.fontFamily; font.pixelSize: Style.font.subtitle * 1.6 }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ALL CLEAR  //  0 failed units"
                         color: panel.accent; font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 2 }
                }
                delegate: Rectangle {
                  required property var modelData
                  width: failedList.width - Style.space(8)
                  height: Style.space(44)
                  radius: 3; border.width: 0
                  color: Util.alpha(panel.red, fm.containsMouse ? 0.16 : 0.08)
                  MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true }
                  ToolTip.visible: fm.containsMouse
                  ToolTip.text: modelData.unit + " (" + modelData.scope + ")\n" + modelData.desc
                    + "\nresult=" + modelData.result + "  exit=" + (modelData.exit || "?")
                    + "  restarts=" + modelData.restarts + "\nsince " + modelData.since
                  ColumnLayout {
                    anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                    spacing: 0
                    RowLayout {
                      Layout.fillWidth: true; spacing: Style.space(6)
                      Rectangle { width: 7; height: 7; radius: 4; color: panel.red; border.width: 0 }
                      Mono { Layout.fillWidth: true; text: modelData.unit; elide: Text.ElideMiddle; font.bold: true }
                      Chip { label: "RESTART"; tint: panel.amber
                             tip: modelData.scope === "user" ? "systemctl --user restart " + modelData.unit
                                  : "pkexec systemctl restart " + modelData.unit + " (polkit may ask)"
                             onClicked: if (svc) svc.restart(modelData.scope, modelData.unit) }
                      Chip { label: "LOGS"; tip: "journalctl -b for this unit in a terminal"
                             onClicked: if (svc) svc.logs(modelData.scope, modelData.unit) }
                    }
                    Mono { Layout.fillWidth: true; color: panel.dim; font.pixelSize: Style.font.bodySmall * 0.85
                           elide: Text.ElideRight
                           text: modelData.scope.toUpperCase() + "  " + modelData.result + "  exit " + (modelData.exit || "?")
                                 + "  " + modelData.since }
                  }
                }
              }
            }

            Caption { text: "AUTO-RESTARTED THIS BOOT" }
            Repeater {
              model: d.flapping || []
              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(8)
                Mono { Layout.fillWidth: true; text: modelData.unit; elide: Text.ElideMiddle }
                Mono { text: modelData.scope; color: panel.dim; font.pixelSize: Style.font.bodySmall * 0.85 }
                Mono { text: "x" + modelData.n; color: modelData.n >= 3 ? panel.amber : panel.foreground; font.bold: true }
              }
            }
            Mono { visible: (d.flapping || []).length === 0; text: "none. Nothing has needed a restart."; color: panel.dim }
            Item { Layout.fillHeight: true }
          }

          // ---------------- col 2: next timers
          ColumnLayout {
            Layout.preferredWidth: panel.panelWidth * 0.30
            Layout.maximumWidth: panel.panelWidth * 0.30
            Layout.alignment: Qt.AlignTop
            spacing: Style.space(4)

            Caption { text: "NEXT 10 TIMERS" }
            Repeater {
              model: d.timers || []
              delegate: Rectangle {
                required property var modelData
                readonly property int remain: Math.max(0, modelData.in - panel.tick)
                Layout.fillWidth: true
                implicitHeight: Style.space(26)
                radius: 3; border.width: 0
                color: tm.containsMouse ? Util.alpha(panel.accent, 0.15) : panel.faint
                // proximity bar: full when due within a minute, empty at 6 h
                Rectangle {
                  anchors.left: parent.left; anchors.bottom: parent.bottom
                  height: 2; border.width: 0; color: panel.accent
                  width: parent.width * Math.max(0.02, 1 - Math.log(1 + remain) / Math.log(1 + 21600))
                }
                RowLayout {
                  anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                  spacing: Style.space(8)
                  Mono { Layout.preferredWidth: Style.space(62); text: panel.dur(remain)
                         color: remain < 60 ? panel.amber : panel.accent; font.bold: true }
                  Mono { Layout.fillWidth: true; text: modelData.unit.replace(/\.timer$/, ""); elide: Text.ElideMiddle }
                  Mono { text: modelData.scope === "user" ? "U" : "S"; color: panel.dim }
                }
                MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true }
                ToolTip.visible: tm.containsMouse
                ToolTip.text: modelData.unit + " -> " + modelData.activates + " (" + modelData.scope + ")"
                  + "\nlast run: " + (modelData.last ? new Date(modelData.last * 1000).toLocaleString() : "never")
              }
            }
          }

          // ---------------- col 3: journal
          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Style.space(6)

            Caption { text: "ERR+ RATE SINCE BOOT  //  " + panel.dur(j.bucketSec || 0) + " per bar" }
            Row {
              id: spark
              Layout.fillWidth: true
              height: Style.space(84)
              spacing: 1
              readonly property var vals: j.spark || []
              readonly property int peak: Math.max(1, Math.max.apply(null, vals.length ? vals : [1]))
              readonly property real bw: vals.length ? (width - (vals.length - 1) * spacing) / vals.length : 0
              Repeater {
                model: spark.vals
                delegate: Item {
                  required property int modelData
                  required property int index
                  width: spark.bw; height: spark.height
                  Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width; border.width: 0; radius: 1
                    // sqrt scale so one noisy hour does not flatten the rest
                    height: modelData ? Math.max(2, parent.height * Math.sqrt(modelData / spark.peak)) : 1
                    color: modelData ? (index === spark.vals.length - 1 && j.burst ? panel.amber : panel.accent) : panel.faint
                    opacity: 0.35 + 0.65 * (index + 1) / spark.vals.length
                  }
                  MouseArea { id: km; anchors.fill: parent; hoverEnabled: true }
                  ToolTip.visible: km.containsMouse
                  ToolTip.text: {
                    var start = (Date.now() / 1000) - (d.uptime || 0) + index * (j.bucketSec || 0)
                    return Qt.formatTime(new Date(start * 1000), "ddd HH:mm") + "  " + modelData + " err+ lines"
                  }
                }
              }
            }
            RowLayout {
              Layout.fillWidth: true
              Mono { text: "boot"; color: panel.dim; font.pixelSize: Style.font.bodySmall * 0.8 }
              Item { Layout.fillWidth: true }
              Mono { text: "peak " + spark.peak + "  //  " + ((j.err || 0) + (j.crit || 0)) + " total  //  last "
                           + (j.lastAgo >= 0 ? panel.dur(j.lastAgo) + " ago" : "never")
                     color: panel.dim; font.pixelSize: Style.font.bodySmall * 0.8 }
              Item { Layout.fillWidth: true }
              Mono { text: "now"; color: panel.dim; font.pixelSize: Style.font.bodySmall * 0.8 }
            }

            Caption { text: "TOP 5 NOISY SOURCES" ; Layout.topMargin: Style.space(4) }
            Repeater {
              model: j.noisy || []
              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(8)
                Mono { Layout.preferredWidth: Style.space(170); Layout.maximumWidth: Style.space(170)
                       text: modelData.unit; elide: Text.ElideMiddle }
                Rectangle {
                  Layout.fillWidth: true; height: Style.space(8); radius: 2; color: panel.faint; border.width: 0
                  Rectangle { height: parent.height; radius: 2; border.width: 0; color: panel.accent
                              width: parent.width * modelData.n / Math.max(1, (j.noisy[0] || {}).n || 1) }
                }
                Mono { Layout.preferredWidth: Style.space(44); horizontalAlignment: Text.AlignRight
                       text: String(modelData.n); color: panel.dim }
                Chip { label: "LOGS"; tip: "err+ lines from " + modelData.unit + " this boot"
                       visible: /\.(service|scope)$/.test(modelData.unit)
                       onClicked: if (svc) svc.logs(modelData.scope, modelData.unit) }
              }
            }
            Mono { visible: (j.noisy || []).length === 0; text: "Journal is clean this boot."; color: panel.accent }
          }
        }
      }
    }
  }
}
