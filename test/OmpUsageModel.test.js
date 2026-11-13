// OmpUsageModel.test.js — node harness for OmpUsageModel.js.
// Run: node test/OmpUsageModel.test.js
var M = require("../OmpUsageModel.js");

var passed = 0, failed = 0;
function eq(actual, expected, name) {
    if (actual === expected) { passed++; }
    else { failed++; console.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", want " + JSON.stringify(expected)); }
}
function ok(cond, name) {
    if (cond) { passed++; }
    else { failed++; console.log("FAIL " + name); }
}

// Fixture: a cut-down `omp usage --json` shaped like the real one.
var FIXTURE = JSON.stringify({
    generatedAt: 1794542502143,
    reports: [
        { provider: "anthropic", fetchedAt: 1794542501262, limits: [
            { id: "anthropic:5h", label: "Claude 5 Hour",
              window: { id: "5h", label: "5 Hour", durationMs: 18000000, resetsAt: 1794546000193 },
              amount: { used: 100, limit: 100, remaining: 0, usedFraction: 1, remainingFraction: 0, unit: "percent" },
              status: "exhausted" },
            { id: "anthropic:7d", label: "Claude 7 Day",
              window: { id: "7d", label: "7 Day", durationMs: 604800000, resetsAt: 1794995999193 },
              amount: { used: 34, limit: 100, remaining: 66, usedFraction: 0.34, remainingFraction: 0.66, unit: "percent" },
              status: "ok" }
        ]},
        { provider: "openai-codex", fetchedAt: 1794542501262, limits: [
            { id: "openai-codex:primary", label: "Primary",
              window: { id: "primary", label: "Primary", durationMs: 0, resetsAt: null },
              amount: { used: 86, limit: 100, remaining: 14, usedFraction: 0.86, remainingFraction: 0.14, unit: "percent" },
              status: "ok" }
        ]},
        { provider: "devin", fetchedAt: 1794542501262, limits: [
            { id: "devin:quota:weekly", label: "Weekly",
              window: { id: "weekly", label: "Weekly", durationMs: 604800000, resetsAt: 1794995999193 },
              amount: { used: 100, limit: 100, remaining: 0, usedFraction: 1, remainingFraction: 0, unit: "percent" },
              status: "exhausted" }
        ]}
    ]
});

var report = M.parseUsageReport(FIXTURE);
ok(report !== null, "parse: fixture parses");
eq(report.providers.length, 3, "parse: 3 providers");
eq(report.providers[0].label, "Anthropic", "parse: provider label");
eq(report.providers[0].limits.length, 2, "parse: anthropic has 2 limits");
eq(report.providers[0].limits[0].usedPct, 100, "parse: 5h usedPct 100");
eq(report.providers[0].limits[1].usedPct, 34, "parse: 7d usedPct 34");
eq(report.providers[0].limits[0].status, "exhausted", "parse: status kept");
eq(report.providers[0].limits[0].resetsAt, 1794546000193, "parse: resetsAt kept");
eq(report.providers[1].label, "OpenAI Codex", "parse: codex label");
eq(report.providers[2].label, "Devin", "parse: devin label");

eq(M.parseUsageReport("not json"), null, "parse: bad JSON -> null");
eq(M.parseUsageReport("{}"), null, "parse: no reports -> null");
eq(M.parseUsageReport(JSON.stringify({ reports: [] })).providers.length, 0, "parse: empty reports -> 0 providers");
eq(M.parseUsageReport(JSON.stringify({ reports: [{ provider: "anthropic", limits: [{ id: "x", amount: {} }] }] })).providers.length, 0, "parse: limit without amount is skipped");

// pickBarLimit
var anth = report.providers[0];
eq(M.pickBarLimit(anth, "auto").id, "anthropic:5h", "pick: auto takes highest (5h 100%)");
eq(M.pickBarLimit(anth, "7d").id, "anthropic:7d", "pick: pinned 7d");
eq(M.pickBarLimit(anth, "5h").id, "anthropic:5h", "pick: pinned 5h");
eq(M.pickBarLimit(anth, "monthly").id, "anthropic:5h", "pick: unknown window falls back to highest");
eq(M.pickBarLimit(null, "auto"), null, "pick: null provider -> null");

// pickPrimaryProvider
eq(M.pickPrimaryProvider(report, "anthropic").id, "anthropic", "primary: configured anthropic");
eq(M.pickPrimaryProvider(report, "openai-codex").id, "openai-codex", "primary: configured codex");
eq(M.pickPrimaryProvider(report, "missing").id, "anthropic", "primary: unknown id falls back to highest (anthropic 100%)");
eq(M.pickPrimaryProvider(report, "").id, "anthropic", "primary: blank id falls back to highest");
eq(M.pickPrimaryProvider({ providers: [] }, "anthropic"), null, "primary: no providers -> null");

// formatBarValue
eq(M.formatBarValue(anth.limits[0], "used"), "100%", "bar: used 100%");
eq(M.formatBarValue(anth.limits[1], "used"), "34%", "bar: used 34%");
eq(M.formatBarValue(anth.limits[1], "left"), "66% left", "bar: left 66%");
eq(M.formatBarValue(null, "used"), "", "bar: null limit -> empty");

// formatResetIn
var now = 1794542502143;
eq(M.formatResetIn(1794546000193, now), "58m", "reset: 58m");
eq(M.formatResetIn(1794542502143 + 2 * 3600000 + 14 * 60000, now), "2h 14m", "reset: 2h 14m");
eq(M.formatResetIn(now - 1000, now), "resetting", "reset: past -> resetting");
eq(M.formatResetIn(null, now), "", "reset: null -> empty");
eq(M.formatResetIn(1794546000193, null), "", "reset: null now -> empty");

// limitTone
eq(M.limitTone(anth.limits[0]), "critical", "tone: exhausted 100% -> critical");
eq(M.limitTone(anth.limits[1]), "ok", "tone: 34% -> ok");
eq(M.limitTone({ usedPct: 95, status: "ok" }), "high", "tone: 95% -> high");
eq(M.limitTone({ usedPct: 100, status: "ok" }), "critical", "tone: 100% -> critical");
eq(M.limitTone(null), "ok", "tone: null -> ok");

// pollIntervalMs — base 300s (5 min), panel open, no failures.
// Closed panel halves the cadence; failures double it, capped at 30 min.
eq(M.pollIntervalMs(300, true, 0, 1800000), 300000, "poll: open, 5 min base");
eq(M.pollIntervalMs(300, false, 0, 1800000), 600000, "poll: closed panel -> 10 min");
eq(M.pollIntervalMs(300, true, 1, 1800000), 600000, "poll: 1 failure doubles to 10 min");
eq(M.pollIntervalMs(300, true, 2, 1800000), 1200000, "poll: 2 failures -> 20 min");
eq(M.pollIntervalMs(300, true, 3, 1800000), 1800000, "poll: 3 failures caps at 30 min");
eq(M.pollIntervalMs(300, true, 10, 1800000), 1800000, "poll: many failures stay capped at 30 min");
eq(M.pollIntervalMs(300, false, 1, 1800000), 1200000, "poll: closed + 1 failure -> 20 min");
eq(M.pollIntervalMs(120, true, 0, 1800000), 120000, "poll: custom base 120s respected");
eq(M.pollIntervalMs(10, true, 0, 1800000), 30000, "poll: base floors at 30s");
eq(M.pollIntervalMs(0, true, 0, 1800000), 30000, "poll: zero base floors at 30s");

// providerLabel / providerShort
eq(M.providerLabel("anthropic"), "Anthropic", "label: anthropic");
eq(M.providerLabel("google-antigravity"), "Antigravity", "label: antigravity");
eq(M.providerLabel("some-new-thing"), "Some New Thing", "label: unknown falls back to title-case");
eq(M.providerShort("anthropic"), "cld", "short: anthropic -> cld");
eq(M.providerShort("openai-codex"), "codex", "short: codex");
eq(M.providerShort("unknown-provider"), "unkn", "short: unknown falls back to 4 chars");

console.log("OmpUsageModel tests: " + passed + " passed, " + failed + " failed");
process.exit(failed === 0 ? 0 : 1);
