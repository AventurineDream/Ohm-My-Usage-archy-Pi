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
  property int refreshIntervalSec: 300
  // Whether the bar shows the usage number (false = provider short code
  // only) and whether the panel shows the usage progress bars (false =
  // one text row per limit, a much more compact list).
  property bool showBarValue: true
  property bool showPanelBars: true

  // Collapse state for the panel's provider sections. A plain object
  // mapping provider id -> true for collapsed providers; expanded ones
  // are absent. Persisted in ~/.config/omarchy/omp-usage-state.json so
  // it survives closing and reopening the panel (and restarts). When
  // no state file exists yet, providers after the first two start
  // collapsed (Model.defaultCollapsedProviders).
  property var collapsedProviders: ({})
  property bool collapseStateLoaded: false
  // The raw set read from the state file (before merging with the
  // defaults). Kept separate so the merge can run whenever the report
  // arrives, regardless of whether the state file or the first fetch
  // finished first.
  property var persistedCollapsed: ({})
  readonly property string collapseStatePath: Quickshell.env("HOME") + "/.config/omarchy/omp-usage-state.json"
  readonly property int maxStateBytes: 65536
  readonly property string readStateScriptPath: Qt.resolvedUrl("read-state").toString().replace(/^file:\/\//, "")
  readonly property string writeStateScriptPath: Qt.resolvedUrl("write-state").toString().replace(/^file:\/\//, "")

  // Whether the panel is open, pushed in by the BarWidget. Polling
  // slows while the panel is closed so providers are not hammered
  // around the clock for a number nobody is looking at.
  property bool panelOpen: false
  // Consecutive failed fetches. Each one doubles the poll interval
  // (exponential back-off); a success resets it to 0.
  property int consecutiveFailures: 0
  // Epoch ms of the last successful fetch (0 = never). Changing the
  // poll interval restarts the poll Timer's countdown, so toggling the
  // panel could otherwise keep pushing the next fetch back and leave
  // the panel showing ~10 min old data. On panel open we fetch
  // immediately when the data is older than the base interval.
  property var lastFetchMs: 0
  // Back-off never exceeds 30 minutes.
  readonly property int maxBackoffMs: 1800000
  // The live poll interval, recomputed whenever the base, the panel
  // state, or the failure count changes.
  readonly property int pollIntervalMs: Model.pollIntervalMs(root.refreshIntervalSec, root.panelOpen, root.consecutiveFailures, root.maxBackoffMs)

  onPanelOpenChanged: {
    if (root.panelOpen)
      root.maybeFetchOnPanelOpen();
  }

  // When the panel opens, fetch immediately if the data is older than
  // the base interval (or never fetched). The poll Timer's countdown
  // restarts whenever its interval changes, so without this the panel
  // could open on data up to ~10 min old.
  function maybeFetchOnPanelOpen() {
    var now = new Date().getTime();
    var baseMs = Math.max(30, root.refreshIntervalSec) * 1000;
    if (!root.lastFetchMs || now - root.lastFetchMs > baseMs)
      root.refresh();
  }

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
    if (typeof settings.showBarValue === "boolean")
      root.showBarValue = settings.showBarValue;
    if (typeof settings.showPanelBars === "boolean")
      root.showPanelBars = settings.showPanelBars;
    root.deriveBar();
  }

  // --- Collapse state (Phase 1) ---
  // The state file holds { providerId: true } for collapsed providers.
  // A missing file is not an error: the first two providers start
  // expanded and the rest collapsed (Model.defaultCollapsedProviders).
  function loadCollapseState() {
    if (collapseStateProc.running)
      return;
    collapseStateProc.collected = "";
    collapseStateProc.command = ["bash", root.readStateScriptPath, root.collapseStatePath, String(root.maxStateBytes)];
    collapseStateProc.running = true;
  }

  function applyCollapseState(ok, output) {
    root.collapseStateLoaded = true;
    root.persistedCollapsed = Model.parseCollapseState(ok ? output : "");
    root.reconcileCollapseState();
  }

  // Merge the persisted set with the defaults for the current report:
  // a provider the user never touched follows the default (first two
  // expanded, rest collapsed); a provider in the file keeps its stored
  // state. Runs whenever either the state file or the report lands,
  // so the order they finish in does not matter.
  function reconcileCollapseState() {
    if (!root.report || !root.report.providers)
      return;
    var dflt = Model.defaultCollapsedProviders(root.report.providers);
    var merged = {};
    root.report.providers.forEach(function (p) {
      if (!p || typeof p.id !== "string")
        return;
      if (Object.prototype.hasOwnProperty.call(root.persistedCollapsed, p.id))
        merged[p.id] = true;
      else if (dflt[p.id])
        merged[p.id] = true;
    });
    root.collapsedProviders = merged;
  }

  function saveCollapseState() {
    if (collapseStateWriteProc.running)
      return;
    collapseStateWriteProc.command = ["bash", root.writeStateScriptPath, "--create", root.collapseStatePath, Model.collapseStateText(root.collapsedProviders)];
    collapseStateWriteProc.running = true;
  }

  function isProviderCollapsed(providerId) {
    return Model.isCollapsed(root.collapsedProviders, providerId);
  }

  function toggleProviderCollapsed(providerId) {
    root.collapsedProviders = Model.toggleCollapsed(root.collapsedProviders, providerId);
    // Keep the persisted set in sync so a later reconcile (e.g. a new
    // provider arriving) does not resurrect the old state.
    root.persistedCollapsed = Model.toggleCollapsed(root.persistedCollapsed, providerId);
    root.saveCollapseState();
  }

  // Apply the collapse defaults for the current report (used when the
  // first fetch lands). Delegates to the reconcile, which merges the
  // persisted set with the defaults.
  function applyCollapseDefaults() {
    root.reconcileCollapseState();
  }

  // Re-derive the bar display from the current report + settings. Called
  // after a fetch lands and after a settings change, so the bar updates
  // immediately when the user switches provider or window.
  function deriveBar() {
    root.primaryProvider = Model.pickPrimaryProvider(root.report, root.provider);
    root.barLimit = root.primaryProvider ? Model.pickBarLimit(root.primaryProvider, root.barWindow) : null;
    // showBarValue off: no number in the bar; the BarWidget shows just
    // the provider short code instead.
    root.barText = (root.showBarValue && root.barLimit) ? Model.formatBarValue(root.barLimit, root.showAs) : "";
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
      // Back off: the next poll waits longer, and the wait grows with
      // each consecutive failure until a fetch succeeds.
      root.consecutiveFailures += 1;
      root.stale = root.report !== null;
      if (!root.report)
        root.error = "Couldn't read OMP usage just now.";
      return;
    }
    var parsed = Model.parseUsageReport(output);
    if (!parsed) {
      root.consecutiveFailures += 1;
      root.stale = root.report !== null;
      if (!root.report)
        root.error = "OMP usage came back in a shape I don't recognise.";
      return;
    }
    root.consecutiveFailures = 0;
    root.lastFetchMs = new Date().getTime();
    root.report = parsed;
    root.stale = false;
    root.error = "";
    root.installed = true;
    root.lastGoodAt = new Date();
    root.applyCollapseDefaults();
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
    interval: root.pollIntervalMs
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

  // Collapse-state file I/O. The read/write helpers are invoked via
  // bash (they are mode 100644 in git, so a direct exec would fail —
  // the same lesson as OmoPomodorachy's read-config/write-config).
  Process {
    id: collapseStateProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function (data) {
        collapseStateProc.collected += String(data + "\n");
      }
    }
    onExited: function (exitCode) {
      var out = String(collapseStateProc.collected);
      collapseStateProc.collected = "";
      root.applyCollapseState(exitCode === 0, out);
    }
  }

  Process {
    id: collapseStateWriteProc
    stderr: SplitParser {
      onRead: function (data) {
        console.warn("omp-usage: collapse state write failed: " + String(data));
      }
    }
  }

  Component.onCompleted: {
    OmpShared.ServiceBridge.service = root;
    root.loadCollapseState();
    root.refresh();
  }
  Component.onDestruction: {
    if (OmpShared.ServiceBridge.service === root)
      OmpShared.ServiceBridge.service = null;
  }
}
