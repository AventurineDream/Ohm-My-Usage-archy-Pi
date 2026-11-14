import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "OmpUsageModel.js" as Model

Panel {
  id: root
  moduleName: "omp-usage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var usageService: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.popups.text
  readonly property color activeColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real maxContentHeight: Math.max(200, Screen.height - 100)

  // Settings section expanded state (panel-local, not persisted).
  property bool settingsExpanded: false

  // Pending settings write: the last settings object handed to
  // updateEntryInline that the shell has not echoed back yet. A second
  // toggle before the echo lands merges into this object instead of
  // re-reading the stale root.settings, so the first change is not
  // lost. Cleared in onSettingsChanged once root.settings catches up.
  property var pendingSettings: null

  // When the shell echoes the settings back, clear the pending write
  // once it matches; if it does not match yet (a newer write is still
  // in flight), re-send the pending object so nothing is dropped.
  onSettingsChanged: {
    if (root.pendingSettings === null || !root.settings)
      return;
    var match = true;
    for (var k in root.pendingSettings) {
      if (root.settings[k] !== root.pendingSettings[k]) {
        match = false;
        break;
      }
    }
    if (match) {
      root.pendingSettings = null;
    } else if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline("aven.omp-usage", root.pendingSettings);
    }
  }

  function refresh() {
    if (root.usageService)
      root.usageService.refresh();
  }

  function toneColor(tone) {
    if (tone === "critical")
      return Color.urgent;
    if (tone === "high")
      return Color.accent;
    return root.foreground;
  }

  // Write one settings key. updateEntryInline REPLACES the whole bar
  // entry, so the full settings object is passed every time — copied
  // from the existing settings (pending write first, else the live
  // ones), with defaults filled in only for keys that are missing.
  // Copying instead of rebuilding from a hardcoded key list means a
  // key added later (or set by hand) is never wiped by a panel change.
  function updateSetting(key, value) {
    var s = {};
    var base = root.pendingSettings !== null ? root.pendingSettings : root.settings;
    if (base) {
      for (var k in base)
        s[k] = base[k];
    }
    if (s.provider === undefined)
      s.provider = "anthropic";
    if (s.barWindow === undefined)
      s.barWindow = "auto";
    if (s.showAs === undefined)
      s.showAs = "used";
    if (s.refreshIntervalSec === undefined)
      s.refreshIntervalSec = 300;
    if (s.showBarValue === undefined)
      s.showBarValue = true;
    if (s.showPanelBars === undefined)
      s.showPanelBars = true;
    if (s.showProvider === undefined)
      s.showProvider = false;
    s[key] = value;
    root.pendingSettings = s;
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline("aven.omp-usage", s);
  }

  function settingValue(key, fallback) {
    if (root.pendingSettings !== null && root.pendingSettings[key] !== undefined)
      return root.pendingSettings[key];
    if (root.settings && root.settings[key] !== undefined)
      return root.settings[key];
    return fallback;
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(Math.min(contentColumn.implicitHeight, maxContentHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight

        // Wheel events were not reaching the Flickable's built-in handler
        // on this surface (drag scrolled, the wheel did not). Root cause
        // is UNKNOWN — nothing in Panel blocks the built-in wheel (the
        // PanelKeyCatcher is keyboard-only). This explicit handler is a
        // workaround, ported from OmoPomodorachy PR #11 (1.9.1): if the
        // built-in wheel handling ever starts working, REMOVE this
        // WheelHandler, or the page will scroll twice per wheel step
        // (double scroll).
        // Touchpads report smooth pixel deltas; a mouse wheel reports
        // angle deltas in 120ths of a degree per notch. 48px per notch
        // is a comfortable step (120px/notch is a lot). The event is
        // only accepted when the content actually moves, so a wheel
        // step at the top or bottom still propagates.
        WheelHandler {
          onWheel: function (event) {
            var step = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 48;
            var maxY = scroller.originY + Math.max(0, scroller.contentHeight - scroller.height);
            var next = Math.max(scroller.originY, Math.min(scroller.contentY - step, maxY));
            if (next !== scroller.contentY) {
              scroller.contentY = next;
              event.accepted = true;
            }
          }
        }

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(16)

          // Header.
          RowLayout {
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "OMP Usage"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Item { width: 1; height: 1; Layout.fillWidth: true }

            Text {
              visible: root.usageService && root.usageService.stale
              text: "stale"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Button {
              text: root.usageService && root.usageService.loading ? "Refreshing…" : "Refresh"
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              foreground: root.foreground
              accent: root.activeColor
              enabled: !(root.usageService && root.usageService.loading)
              onClicked: root.refresh()
            }
          }

          // Error / empty state.
          Column {
            visible: !root.usageService || !root.usageService.report
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: root.usageService && root.usageService.error !== "" ? root.usageService.error : "Waiting for the first OMP usage fetch…"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          // Settings section (collapsible). Edits the bar-entry
          // settings inline, so the bar updates immediately.
          Column {
            visible: root.usageService && root.usageService.report && root.usageService.report.providers.length > 0
            width: parent.width
            spacing: Style.space(8)

            MouseArea {
              width: parent.width
              height: settingsHeader.implicitHeight
              onClicked: root.settingsExpanded = !root.settingsExpanded
              RowLayout {
                id: settingsHeader
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: root.settingsExpanded ? "v" : ">"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: "Settings"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }

            Column {
              visible: root.settingsExpanded
              width: parent.width
              spacing: Style.space(10)

              // Primary provider (bar).
              Column {
                width: parent.width
                spacing: Style.space(4)
                Text {
                  text: "Bar provider"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: root.usageService && root.usageService.report ? root.usageService.report.providers : []
                    Button {
                      required property var modelData
                      text: (root.settingValue("provider", "anthropic") === modelData.id ? "✓ " : "") + Model.providerShort(modelData.id)
                      fontFamily: root.fontFamily
                      fontSize: Style.font.body
                      foreground: root.foreground
                      accent: root.activeColor
                      onClicked: root.updateSetting("provider", modelData.id)
                    }
                  }
                  Button {
                    text: (root.settingValue("provider", "anthropic") === "" ? "✓ " : "") + "Auto"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    foreground: root.foreground
                    accent: root.activeColor
                    onClicked: root.updateSetting("provider", "")
                  }
                }
              }

              // Bar window.
              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "Bar window"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Row {
                  spacing: Style.space(6)
                  Button {
                    text: (root.settingValue("barWindow", "auto") === "auto" ? "✓ " : "") + "Auto"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    foreground: root.foreground
                    accent: root.activeColor
                    onClicked: root.updateSetting("barWindow", "auto")
                  }
                  Button {
                    text: (root.settingValue("barWindow", "auto") === "5h" ? "✓ " : "") + "5h"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    foreground: root.foreground
                    accent: root.activeColor
                    onClicked: root.updateSetting("barWindow", "5h")
                  }
                  Button {
                    text: (root.settingValue("barWindow", "auto") === "7d" ? "✓ " : "") + "7d"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    foreground: root.foreground
                    accent: root.activeColor
                    onClicked: root.updateSetting("barWindow", "7d")
                  }
                }
              }

              // Show as used / left.
              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "Show as"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Row {
                  spacing: Style.space(6)
                  Button {
                    text: (root.settingValue("showAs", "used") === "used" ? "✓ " : "") + "Used"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    foreground: root.foreground
                    accent: root.activeColor
                    onClicked: root.updateSetting("showAs", "used")
                  }
                  Button {
                    text: (root.settingValue("showAs", "used") === "left" ? "✓ " : "") + "Left"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    foreground: root.foreground
                    accent: root.activeColor
                    onClicked: root.updateSetting("showAs", "left")
                  }
                }
              }

              // Toggles: bar value + panel bars.
              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "Show value in bar"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Button {
                  text: root.settingValue("showBarValue", true) ? "On" : "Off"
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  foreground: root.foreground
                  accent: root.activeColor
                  onClicked: root.updateSetting("showBarValue", !root.settingValue("showBarValue", true))
                }
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "Show bars in panel"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Item { width: 1; height: 1; Layout.fillWidth: true }
                Button {
                  text: root.settingValue("showPanelBars", true) ? "On" : "Off"
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  foreground: root.foreground
                  accent: root.activeColor
                  onClicked: root.updateSetting("showPanelBars", !root.settingValue("showPanelBars", true))
                }
              }
            }
          }

          // One section per provider. The first two start expanded, the
          // rest collapsed; the state persists in the state file, so it
          // survives closing and reopening the panel.
          Repeater {
            model: root.usageService && root.usageService.report ? root.usageService.report.providers : []

            Column {
              id: providerSection
              required property var modelData
              readonly property bool collapsed: root.usageService ? root.usageService.isProviderCollapsed(modelData.id) : false
              // Summary: highest used% across this provider's limits.
              readonly property int peakPct: {
                var best = 0;
                for (var i = 0; i < modelData.limits.length; i++) {
                  if (modelData.limits[i].usedPct > best)
                    best = modelData.limits[i].usedPct;
                }
                return best;
              }
              width: parent.width
              spacing: Style.space(8)

              MouseArea {
                width: parent.width
                height: providerHeader.implicitHeight
                onClicked: {
                  if (root.usageService)
                    root.usageService.toggleProviderCollapsed(modelData.id);
                }
                RowLayout {
                  id: providerHeader
                  width: parent.width
                  spacing: Style.space(6)
                  Text {
                    text: providerSection.collapsed ? ">" : "v"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                  }
                  Text {
                    text: providerSection.peakPct + "%"
                    color: root.toneColor(Model.limitTone({ usedPct: providerSection.peakPct, status: providerSection.peakPct >= 100 ? "exhausted" : "ok" }))
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: providerSection.peakPct >= 90
                  }
                }
              }

              Column {
                visible: !providerSection.collapsed
                width: parent.width
                spacing: Style.space(8)

                Repeater {
                  model: modelData.limits

                  Column {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(4)

                    RowLayout {
                      width: parent.width
                      spacing: Style.space(8)

                      Text {
                        text: modelData.label
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                      }

                      Text {
                        text: modelData.usedPct + "% used"
                        color: root.toneColor(Model.limitTone(modelData))
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.usedPct >= 90
                      }

                      Text {
                        visible: modelData.resetsAt !== null
                        text: "resets in " + Model.formatResetIn(modelData.resetsAt, new Date().getTime())
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                    }

                    Rectangle {
                      visible: root.settingValue("showPanelBars", true)
                      width: parent.width
                      height: Style.space(6)
                      radius: height / 2
                      color: Qt.darker(root.foreground, 2.2)

                      Rectangle {
                        width: parent.width * Math.min(1, modelData.usedPct / 100)
                        height: parent.height
                        radius: height / 2
                        color: root.toneColor(Model.limitTone(modelData))
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.usageService && root.usageService.report && root.usageService.report.providers.length > 0
            width: parent.width
            text: "From `omp usage`. Right-click the bar icon to refresh."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
