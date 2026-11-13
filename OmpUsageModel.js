// OmpUsageModel.js — pure functions over `omp usage --json` output.
// No QML, no I/O: every function is testable in node. The Service polls
// `omp usage --json` and hands the raw text here; the BarWidget and Panel
// render what these functions return.
//
// The JSON shape (from `omp usage --json`):
//   { generatedAt, reports: [ { provider, fetchedAt, limits: [
//       { id, label, window: { id, label, durationMs, resetsAt },
//         amount: { used, limit, remaining, usedFraction,
//                   remainingFraction, unit }, status } ], ... } ] }

function providerLabel(providerId) {
    var labels = {
        "anthropic": "Anthropic",
        "devin": "Devin",
        "google-antigravity": "Antigravity",
        "openai-codex": "OpenAI Codex",
        "xai-oauth": "xAI"
    };
    if (Object.prototype.hasOwnProperty.call(labels, providerId))
        return labels[providerId];
    // Fallback: split on -/_ and title-case each part.
    return String(providerId).split(/[-_]/).map(function (p) {
        return p ? p.charAt(0).toUpperCase() + p.slice(1) : p;
    }).join(" ");
}

function providerShort(providerId) {
    var shorts = {
        "anthropic": "cld",
        "devin": "devin",
        "google-antigravity": "agy",
        "openai-codex": "codex",
        "xai-oauth": "grok"
    };
    if (Object.prototype.hasOwnProperty.call(shorts, providerId))
        return shorts[providerId];
    return String(providerId).slice(0, 4);
}

// Normalize one limit entry into the shape the UI consumes. Returns null
// when the entry is unusable (missing amount/window), so callers skip it.
function normalizeLimit(raw) {
    if (!raw || !raw.amount || typeof raw.amount.usedFraction !== "number")
        return null;
    var win = raw.window || {};
    return {
        id: String(raw.id || ""),
        label: String(raw.label || raw.id || ""),
        windowId: String(win.id || ""),
        windowLabel: String(win.label || win.id || ""),
        usedPct: Math.round(raw.amount.usedFraction * 100),
        remainingPct: Math.round(raw.amount.remainingFraction * 100),
        status: String(raw.status || "ok"),
        resetsAt: typeof win.resetsAt === "number" ? win.resetsAt : null
    };
}

// Parse the raw `omp usage --json` text. Returns
//   { providers: [ { id, label, limits: [normalized] } ] }
// or null when the text is not usable JSON / has no reports.
function parseUsageReport(jsonText) {
    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        return null;
    }
    if (!data || !Array.isArray(data.reports))
        return null;
    var providers = [];
    data.reports.forEach(function (rep) {
        if (!rep || typeof rep.provider !== "string")
            return;
        var limits = [];
        (Array.isArray(rep.limits) ? rep.limits : []).forEach(function (raw) {
            var lim = normalizeLimit(raw);
            if (lim)
                limits.push(lim);
        });
        if (limits.length > 0)
            providers.push({ id: rep.provider, label: providerLabel(rep.provider), limits: limits });
    });
    return { providers: providers };
}

// Pick the limit to show in the bar for one provider.
//   barWindow "auto" -> the limit with the highest used%.
//   barWindow "5h"/"7d" -> the limit whose windowId matches; falls back to
//   the highest when the provider has no such window.
// Returns null when the provider has no limits.
function pickBarLimit(provider, barWindow) {
    if (!provider || !provider.limits || provider.limits.length === 0)
        return null;
    if (barWindow && barWindow !== "auto") {
        for (var i = 0; i < provider.limits.length; i++) {
            if (provider.limits[i].windowId === barWindow)
                return provider.limits[i];
        }
    }
    var best = provider.limits[0];
    for (var j = 1; j < provider.limits.length; j++) {
        if (provider.limits[j].usedPct > best.usedPct)
            best = provider.limits[j];
    }
    return best;
}

// Pick the primary provider: the configured id when present in the report,
// otherwise the provider whose highest limit is the most used.
function pickPrimaryProvider(report, providerId) {
    if (!report || !report.providers || report.providers.length === 0)
        return null;
    if (providerId) {
        for (var i = 0; i < report.providers.length; i++) {
            if (report.providers[i].id === providerId)
                return report.providers[i];
        }
    }
    var best = null, bestPct = -1;
    report.providers.forEach(function (p) {
        var lim = pickBarLimit(p, "auto");
        if (lim && lim.usedPct > bestPct) {
            bestPct = lim.usedPct;
            best = p;
        }
    });
    return best;
}

// The bar text for one limit. showAs "used" -> "100%"; "left" -> "0% left".
function formatBarValue(limit, showAs) {
    if (!limit)
        return "";
    if (showAs === "left")
        return limit.remainingPct + "% left";
    return limit.usedPct + "%";
}

// Human reset countdown for a limit's resetsAt (epoch ms) against nowMs.
// "2h 14m", "38m", "resetting" when past, "" when unknown.
function formatResetIn(resetsAt, nowMs) {
    if (typeof resetsAt !== "number" || typeof nowMs !== "number")
        return "";
    var ms = resetsAt - nowMs;
    if (ms <= 0)
        return "resetting";
    var mins = Math.floor(ms / 60000);
    var h = Math.floor(mins / 60);
    var m = mins % 60;
    if (h > 0)
        return h + "h " + m + "m";
    return m + "m";
}

// Status tint for a limit: exhausted -> "critical", >= 90% -> "high",
// otherwise "ok". The UI maps these to theme colors.
function limitTone(limit) {
    if (!limit)
        return "ok";
    if (limit.status === "exhausted" || limit.usedPct >= 100)
        return "critical";
    if (limit.usedPct >= 90)
        return "high";
    return "ok";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        providerLabel: providerLabel,
        providerShort: providerShort,
        normalizeLimit: normalizeLimit,
        parseUsageReport: parseUsageReport,
        pickBarLimit: pickBarLimit,
        pickPrimaryProvider: pickPrimaryProvider,
        formatBarValue: formatBarValue,
        formatResetIn: formatResetIn,
        limitTone: limitTone
    };
}
