import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "shared" as OmpShared

BarWidget {
  id: root

  readonly property var usageService: (bar && bar.shell ? bar.shell.serviceFor(moduleName) : null) || OmpShared.ServiceBridge.service
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Bar text: provider short code + usage, e.g. "cld 100%". When the
  // provider name is shown, the short code is the name; otherwise just
  // the number. A missing/failed fetch shows a quiet "—" instead of
  // blanking the bar.
  readonly property string barDisplayText: {
    if (!root.usageService || !root.usageService.installed)
      return "—";
    var value = String(root.usageService.barText || "");
    if (value === "")
      return "—";
    if (root.settings && root.settings.showProvider) {
      var short = String(root.usageService.barShort || "");
      return short !== "" ? short + " " + value : value;
    }
    return value;
  }

  // Tone color: exhausted/high usage tints the bar text so a blown
  // window is visible at a glance. Falls back to the bar foreground.
  // (Color has urgent/accent; there is no alert/warning role.)
  readonly property color barToneColor: {
    if (!root.usageService)
      return button.foreground;
    if (root.usageService.barTone === "critical")
      return Color.urgent;
    if (root.usageService.barTone === "high")
      return Color.accent;
    return button.foreground;
  }

  function syncService() {
    if (root.usageService && typeof root.usageService.configure === "function")
      root.usageService.configure(root.settings);
    injectPanel();
  }

  function injectPanel() {
    var target = panelLoader.item;
    if (!target)
      return;
    if ("bar" in target)
      target.bar = root.bar;
    if ("settings" in target)
      target.settings = root.settings;
    if ("anchorItem" in target)
      target.anchorItem = button;
    if ("hostWidget" in target)
      target.hostWidget = root;
    if ("usageService" in target)
      target.usageService = root.usageService;
  }

  function open() {
    if (panelLoader.item)
      panelLoader.item.open();
  }

  function close() {
    if (panelLoader.item)
      panelLoader.item.close();
  }

  function toggle() {
    if (panelLoader.item)
      panelLoader.item.toggle();
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item)
      panelLoader.item.closeForPopoutSwitch();
  }

  moduleName: "omp-usage"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: Qt.callLater(syncService)
  onSettingsChanged: Qt.callLater(syncService)
  onUsageServiceChanged: Qt.callLater(syncService)
  Component.onCompleted: Qt.callLater(syncService)

  Loader {
    id: panelLoader

    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel();
      Qt.callLater(root.syncService);
    }
  }

  WidgetButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: root.barDisplayText
    foreground: root.barToneColor
    labelVisible: true
    hasVisualContent: text !== ""
    tooltipText: root.usageService && root.usageService.installed ? (root.usageService.stale ? "OMP usage (stale — last fetch failed)" : "OMP usage") : "OMP usage — waiting for the first fetch"
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton)
        root.toggle();
      else if (buttonCode === Qt.RightButton && root.usageService)
        root.usageService.refresh();
    }
  }
}
