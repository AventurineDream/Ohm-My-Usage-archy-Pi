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
          // survives closing and reopening the panel. Drag a provider
          // by its grip to reorder the list; the order persists too.
          // A ListView (not a Repeater) so the sections can be dragged:
          // it is non-interactive with its height bound to its content,
          // so the outer Flickable stays the scroller and keeps the
          // WheelHandler workaround.
          ListView {
            id: providerList
            width: parent.width
            height: contentHeight
            interactive: false
            spacing: Style.space(16)
            model: root.usageService && root.usageService.report ? root.usageService.report.providers : []

            // Drag state, shared by the delegates. dragItem is the
            // delegate being dragged; dragLayoutY is its layout
            // position before the drag (its y is the dragged position
            // while dragging).
            property Item dragItem: null
            property real dragLayoutY: 0

            // Return the delegate index whose layout span contains the
            // given y (in content coordinates). Used on drop to find
            // where the dragged provider lands. The dragged delegate's
            // own y is its dragged position, so its stored layoutY is
            // used instead; the other delegates have not moved.
            function dropIndex(centerY) {
              var spans = [];
              var kids = providerList.contentItem.children;
              for (var i = 0; i < kids.length; i++) {
                var c = kids[i];
                if (c && typeof c.index === "number" && typeof c.height === "number") {
                  var y = (c === providerList.dragItem) ? providerList.dragLayoutY : c.y;
                  spans.push({ index: c.index, y: y, h: c.height });
                }
              }
              spans.sort(function (a, b) { return a.index - b.index; });
              for (var j = 0; j < spans.length; j++) {
                if (centerY < spans[j].y + spans[j].h)
                  return spans[j].index;
              }
              return spans.length > 0 ? spans[spans.length - 1].index : 0;
            }

            delegate: Item {
              id: delegateRoot
              required property var modelData
              required property int index
              width: providerList.width
              height: providerSection.implicitHeight
              property bool dragging: false
              property real layoutY: 0
              z: dragging ? 10 : 0

              Column {
                id: providerSection
                // NOTE: no `required property var modelData` here. This
                // Column is a child of the ListView delegate, not a
                // delegate itself — it reads the delegate's modelData
                // from scope. Declaring it required breaks delegate
                // creation (nothing assigns it), which renders the
                // whole list empty.
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
                opacity: delegateRoot.dragging ? 0.85 : 1

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
                    // Drag grip. The grip — not the whole header — is the
                    // drag target, so click-to-collapse keeps working and
                    // the gesture is discoverable. The grip MouseArea
                    // accepts the press, so a press on it never reaches
                    // the header MouseArea above.
                    Text {
                      text: "⠿"
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      MouseArea {
                        id: gripArea
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        cursorShape: Qt.OpenHandCursor
                        drag.target: delegateRoot
                        drag.axis: Drag.YAxis
                        drag.minimumY: 0
                        drag.maximumY: Math.max(0, providerList.contentHeight - delegateRoot.height)
                        onPressed: function (mouse) {
                          delegateRoot.layoutY = delegateRoot.y;
                          delegateRoot.dragging = true;
                          providerList.dragItem = delegateRoot;
                          providerList.dragLayoutY = delegateRoot.y;
                          // A drag is not a scroll: stop the Flickable
                          // from treating it as one.
                          scroller.interactive = false;
                          gripArea.cursorShape = Qt.ClosedHandCursor;
                        }
                        onReleased: function (mouse) {
                          var from = delegateRoot.index;
                          var centerY = delegateRoot.y + delegateRoot.height / 2;
                          var target = providerList.dropIndex(centerY);
                          delegateRoot.dragging = false;
                          providerList.dragItem = null;
                          scroller.interactive = true;
                          gripArea.cursorShape = Qt.OpenHandCursor;
                          if (target !== from && root.usageService) {
                            root.usageService.moveProvider(from, target);
                            // The model change recreates the delegates;
                            // no y reset needed.
                          } else {
                            // Dropped on itself: snap back to the layout
                            // position.
                            delegateRoot.y = delegateRoot.layoutY;
                          }
                        }
                      }
                    }
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
          }

          Text {
            visible: root.usageService && root.usageService.report && root.usageService.report.providers.length > 0
            width: parent.width
            text: "From `omp usage`. Drag a provider by its ⠿ grip to reorder it. Right-click the bar icon to refresh."
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
