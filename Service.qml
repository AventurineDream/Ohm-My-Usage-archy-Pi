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

  // Provider state for the panel: which sections are collapsed, and
  // the display order (drag-to-sort). Persisted in
  // ~/.config/omarchy/omp-usage-state.json as a versioned object
  // { version: 2, collapsed: {...}, order: [...] } so both survive
  // closing and reopening the panel (and restarts). A v1 file (a flat
  // id -> boolean collapse map) migrates on read. When no state file
  // exists yet, providers after the first two start collapsed
  // (Model.defaultCollapsedProviders) and the order is the fetch order.
  property var collapsedProviders: ({})
  property bool providerStateLoaded: false
  // The raw sets read from the state file (before merging with the
  // defaults). Kept separate so the merge can run whenever the report
  // arrives, regardless of whether the state file or the first fetch
  // finished first.
  property var persistedCollapsed: ({})
  property var persistedOrder: []
  readonly property string providerStatePath: Quickshell.env("HOME") + "/.config/omarchy/omp-usage-state.json"
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

  // --- Provider state (collapse + order) ---
  // The state file holds { version: 2, collapsed: {...}, order: [...] }.
  // A missing file is not an error: the first two providers start
  // expanded and the rest collapsed (Model.defaultCollapsedProviders),
  // and the order is the fetch order.
  function loadProviderState() {
    if (providerStateProc.running)
      return;
    providerStateProc.collected = "";
    providerStateProc.command = ["bash", root.readStateScriptPath, root.providerStatePath, String(root.maxStateBytes)];
    providerStateProc.running = true;
  }

  function applyProviderState(ok, output) {
    root.providerStateLoaded = true;
    var state = Model.parseProviderState(ok ? output : "");
    root.persistedCollapsed = state.collapsed;
    root.persistedOrder = state.order;
    root.reconcileCollapseState();
    root.applyProviderOrder();
  }

  // Re-sort the current report to the persisted display order. Runs
  // whenever the report or the state file lands, so the order they
  // finish in does not matter. Providers not in the stored order (new
  // providers) are appended in fetch order. The report is reassigned
  // to a new object so QML bindings on it re-evaluate (mutating the
  // providers array in place would not notify).
  function applyProviderOrder() {
    if (!root.report || !root.report.providers)
      return;
    root.report = { providers: Model.applyProviderOrder(root.report.providers, root.persistedOrder) };
  }

  // Move a provider in the display order (drag-to-sort). `from` and
  // `to` are indices in the current display order. The new order is
  // persisted, so it survives the next refetch. A no-op move (dropped
  // on itself) writes nothing.
  function moveProvider(from, to) {
    if (!root.report || !root.report.providers)
      return;
    var ids = [];
    root.report.providers.forEach(function (p) { ids.push(p.id); });
    var next = Model.moveProviderOrder(ids, from, to);
    var changed = next.length !== ids.length;
    if (!changed) {
      for (var i = 0; i < next.length; i++) {
        if (next[i] !== ids[i]) { changed = true; break; }
      }
    }
    if (!changed)
      return;
    root.persistedOrder = next;
    root.report = { providers: Model.applyProviderOrder(root.report.providers, next) };
    root.saveProviderState();
  }

  // Merge the persisted set with the defaults for the current report:
  // a provider with a stored boolean keeps it (true or false); only
  // ids never touched fall back to the default (first two expanded,
  // rest collapsed). Runs whenever either the state file or the report
  // lands, so the order they finish in does not matter.
  function reconcileCollapseState() {
    if (!root.report || !root.report.providers)
      return;
    root.collapsedProviders = Model.mergeCollapseState(root.persistedCollapsed, Model.defaultCollapsedProviders(root.report.providers));
  }

  // Pending flag (OmoPomodorachy #14 pattern): a change that lands
  // while a write is running sets the flag instead of being dropped;
  // the write's onExited re-runs the save with the latest state.
  property bool providerStateWritePending: false

  function saveProviderState() {
    if (providerStateWriteProc.running) {
      root.providerStateWritePending = true;
      return;
    }
    providerStateWriteProc.command = ["bash", root.writeStateScriptPath, "--create", root.providerStatePath, Model.providerStateText(root.collapsedProviders, root.persistedOrder)];
    providerStateWriteProc.running = true;
  }

  function isProviderCollapsed(providerId) {
    return Model.isCollapsed(root.collapsedProviders, providerId);
  }

  function toggleProviderCollapsed(providerId) {
    var next = Model.toggleCollapsed(root.collapsedProviders, providerId);
    root.collapsedProviders = next;
    // Record the NEW state explicitly in the persisted set, so it wins
    // over the default on the next reconcile. (Toggling the persisted
    // set itself would be wrong: a default-collapsed provider absent
    // from the file would flip to "collapsed: true" when the user just
    // expanded it, and the next fetch would snap it shut again.)
    var p = {};
    if (root.persistedCollapsed && typeof root.persistedCollapsed === "object") {
      for (var k in root.persistedCollapsed) {
        if (Object.prototype.hasOwnProperty.call(root.persistedCollapsed, k))
          p[k] = root.persistedCollapsed[k];
      }
    }
    p[providerId] = Model.isCollapsed(next, providerId);
    root.persistedCollapsed = p;
    root.saveProviderState();
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
    root.applyProviderOrder();
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

  // Provider-state file I/O. The read/write helpers are invoked via
  // bash (they are mode 100755 in git since PR #5, but invoking via
  // bash is the established pattern here, as with OmoPomodorachy's
  // read-config/write-config).
  Process {
    id: providerStateProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function (data) {
        providerStateProc.collected += String(data + "\n");
      }
    }
    onExited: function (exitCode) {
      var out = String(providerStateProc.collected);
      providerStateProc.collected = "";
      root.applyProviderState(exitCode === 0, out);
    }
  }

  Process {
    id: providerStateWriteProc
    stderr: SplitParser {
      onRead: function (data) {
        console.warn("omp-usage: provider state write failed: " + String(data));
      }
    }
    onExited: function (exitCode) {
      // A change that landed mid-write set the pending flag; write the
      // latest state now so it is not lost.
      if (root.providerStateWritePending) {
        root.providerStateWritePending = false;
        root.saveProviderState();
      }
    }
  }

  Component.onCompleted: {
    OmpShared.ServiceBridge.service = root;
    root.loadProviderState();
    root.refresh();
  }
  Component.onDestruction: {
    if (OmpShared.ServiceBridge.service === root)
      OmpShared.ServiceBridge.service = null;
  }
}
