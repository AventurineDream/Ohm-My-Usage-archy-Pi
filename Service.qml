import QtQuick
import Quickshell
import Quickshell.Io
import "OmpUsageModel.js" as Model
import "shared" as OmpShared

Item {
  id: root

  property var shell: null
  property var manifest: null

  // Settings, pushed in by the BarWidget from the plugin settings.
  property string provider: "anthropic"
  property string barWindow: "auto"
  property string showAs: "used"
  property int refreshIntervalSec: 120

  // Live state.
  property var report: null
  property var primaryProvider: null
  property var barLimit: null
  property string barText: ""
  property string barTone: "ok"
  property string barShort: ""
  property bool installed: false
  property bool loading: false
  property bool stale: false
  property string error: ""
  property var lastGoodAt: null

  // The usage JSON is small (tens of KB for a handful of providers), but
  // cap it anyway: a runaway `omp` must never fill memory. 256 KiB is
  // generous for this payload.
  readonly property int maxUsageBytes: 262144
  readonly property int usageTimeoutMs: 30000

  function configure(settings) {
    if (!settings)
      return;
    if (typeof settings.provider === "string")
      root.provider = settings.provider;
    if (typeof settings.barWindow === "string")
      root.barWindow = settings.barWindow;
    if (typeof settings.showAs === "string")
      root.showAs = settings.showAs;
    if (typeof settings.refreshIntervalSec === "number" && settings.refreshIntervalSec > 0)
      root.refreshIntervalSec = settings.refreshIntervalSec;
    root.deriveBar();
  }

  // Re-derive the bar display from the current report + settings. Called
  // after a fetch lands and after a settings change, so the bar updates
  // immediately when the user switches provider or window.
  function deriveBar() {
    root.primaryProvider = Model.pickPrimaryProvider(root.report, root.provider);
    root.barLimit = root.primaryProvider ? Model.pickBarLimit(root.primaryProvider, root.barWindow) : null;
    root.barText = root.barLimit ? Model.formatBarValue(root.barLimit, root.showAs) : "";
    root.barTone = root.barLimit ? Model.limitTone(root.barLimit) : "ok";
    root.barShort = root.primaryProvider ? Model.providerShort(root.primaryProvider.id) : "";
  }

  function refresh() {
    if (usageProc.running)
      return;
    root.loading = true;
    usageProc.collected = "";
    usageProc.collectedBytes = 0;
    usageProc.overflowed = false;
    usageProc.timedOut = false;
    usageWatchdog.restart();
    usageProc.command = ["omp", "usage", "--json"];
    usageProc.running = true;
  }

  function applyUsage(ok, output) {
    root.loading = false;
    if (!ok) {
      // Keep the last good report on screen, marked stale, instead of
      // blanking the bar. A failed fetch is a fetch problem, not a data
      // problem: the previous numbers are still the best thing to show.
      root.stale = root.report !== null;
      if (!root.report)
        root.error = "Couldn't read OMP usage just now.";
      return;
    }
    var parsed = Model.parseUsageReport(output);
    if (!parsed) {
      root.stale = root.report !== null;
      if (!root.report)
        root.error = "OMP usage came back in a shape I don't recognise.";
      return;
    }
    root.report = parsed;
    root.stale = false;
    root.error = "";
    root.installed = true;
    root.lastGoodAt = new Date();
    root.deriveBar();
  }

  function killProc(proc) {
    try {
      proc.running = false;
    } catch (e) {
    }
  }

  Timer {
    id: pollTimer
    interval: Math.max(30, root.refreshIntervalSec) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: usageWatchdog
    interval: root.usageTimeoutMs
    repeat: false
    onTriggered: {
      if (usageProc.running) {
        usageProc.timedOut = true;
        usageProc.collected = "";
        usageProc.collectedBytes = 0;
        root.killProc(usageProc);
      }
    }
  }

  Process {
    id: usageProc
    property string collected: ""
    property int collectedBytes: 0
    property bool overflowed: false
    property bool timedOut: false
    stdout: SplitParser {
      onRead: function (data) {
        if (usageProc.overflowed || usageProc.timedOut)
          return;
        var chunk = String(data + "\n");
        if (usageProc.collectedBytes + chunk.length > root.maxUsageBytes) {
          usageProc.overflowed = true;
          usageProc.collected = "";
          usageProc.collectedBytes = 0;
          root.killProc(usageProc);
          return;
        }
        usageProc.collected += chunk;
        usageProc.collectedBytes += chunk.length;
      }
    }
    stderr: SplitParser {
      onRead: function (data) {
        if (usageProc.overflowed || usageProc.timedOut)
          return;
        usageProc.collectedBytes += String(data + "\n").length;
        if (usageProc.collectedBytes > root.maxUsageBytes) {
          usageProc.overflowed = true;
          usageProc.collected = "";
          usageProc.collectedBytes = 0;
          root.killProc(usageProc);
        }
      }
    }
    onExited: function (exitCode) {
      usageWatchdog.stop();
      var ok = !usageProc.overflowed && !usageProc.timedOut && exitCode === 0;
      var output = String(usageProc.collected);
      usageProc.collected = "";
      usageProc.collectedBytes = 0;
      usageProc.overflowed = false;
      usageProc.timedOut = false;
      root.applyUsage(ok, output);
    }
  }

  Component.onCompleted: {
    OmpShared.ServiceBridge.service = root;
    root.refresh();
  }
  Component.onDestruction: {
    if (OmpShared.ServiceBridge.service === root)
      OmpShared.ServiceBridge.service = null;
  }
}
