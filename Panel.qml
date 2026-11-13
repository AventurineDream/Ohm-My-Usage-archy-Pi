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

  function refresh() {
    if (root.usageService)
      root.usageService.refresh();
  }

  function toneColor(tone) {
    if (tone === "critical")
      return Color.alert;
    if (tone === "high")
      return Color.warning;
    return root.foreground;
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
              color: Color.warning
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

          // One section per provider.
          Repeater {
            model: root.usageService && root.usageService.report ? root.usageService.report.providers : []

            Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

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
