.pragma library

// Pure helpers for Settings.qml: schema layout, validation and exclusion pattern parsing
// (exact appId, `/regex/`, `entry:<desktop id>`).

// Where each flat Settings key lives in settings.json ("" = top level). Mirrors ARCHITECTURE §5.
var groups = {
    "": ["pins"],
    appearance: ["iconSize", "magnification", "maxMagnifiedSize", "magnificationSpread", "spacing",
        "backgroundOpacity", "cornerRadius", "showSeparator", "indicatorStyle"],
    position: ["edge", "margin", "monitors", "onlyCurrentMonitorApps"],
    behaviour: ["visibilityMode", "lastVisibleMode", "lastHiddenMode", "hideOnFullscreen", "showDelay",
        "hideDelay", "animationSpeed", "clickFocused", "showRunning", "bounceOnLaunch"],
    filtering: ["hideNoDisplay", "exclusions"]
};

// Plain JS copy of a value; QML list<string> isn't a JS Array.
function plain(v) {
    return (v !== null && typeof v === "object") ? Array.from(v) : v;
}

function same(a, b) {
    return JSON.stringify(plain(a)) === JSON.stringify(plain(b));
}

function dedupe(ids) {
    const out = [];
    for (const id of ids ?? []) if (id && !out.includes(id)) out.push(id);
    return out;
}

// undefined: not a /regex/ pattern. null: a /regex/ pattern that doesn't compile.
function parseRegex(p) {
    const m = /^\/(.+)\/([a-z]*)$/.exec(p);
    if (!m) return undefined;
    try {
        return new RegExp(m[1], m[2].replace(/[gy]/g, ""));
    } catch (e) {
        return null;
    }
}

// Prefix of an entry pattern: `entry:<desktop entry id>` hides every appId that resolves to that entry.
var entryPrefix = "entry:";

// undefined: not an entry pattern. "": `entry:` with no id (invalid). Otherwise the lower-cased id.
function parseEntry(p) {
    if (typeof p !== "string" || !p.startsWith(entryPrefix)) return undefined;
    return p.slice(entryPrefix.length).trim().toLowerCase();
}

// Flat key → corrected value, for every value that breaks a range, an enum or a list rule.
// `get(key)` reads the current value. Empty object when everything is valid.
function fixups(get, spec) {
    const out = {};
    for (const k in spec.ranges) {
        const [lo, hi] = spec.ranges[k];
        let v = Math.min(hi, Math.max(lo, Number(get(k))));
        if (isNaN(v)) v = spec.defaults[k];
        if (spec.ints.includes(k)) v = Math.round(v);
        if (v !== get(k)) out[k] = v;
    }
    for (const k in spec.enums) {
        if (!spec.enums[k].includes(get(k))) out[k] = spec.defaults[k];
    }
    if (!get("monitors")) out.monitors = spec.defaults.monitors;
    for (const k of ["pins", "exclusions"]) {
        const d = dedupe(get(k));
        if (d.length !== get(k).length) out[k] = d;
    }
    return out;
}

// True when the parsed file doesn't hold exactly the in-memory value for some known key
// (missing key, wrong type that JsonAdapter skipped or coerced, or a value we corrected).
function needsRepair(raw, get) {
    for (const g in groups) {
        const obj = g === "" ? raw : raw[g];
        for (const k of groups[g]) {
            if (obj === null || typeof obj !== "object" || !(k in obj) || !same(obj[k], get(k))) return true;
        }
    }
    return false;
}

// Flat key → value for every persisted key, as a JSON string (the hot-reload hand-off).
function snapshot(get) {
    const out = {};
    for (const g in groups) for (const k of groups[g]) out[k] = plain(get(k));
    return JSON.stringify(out);
}
