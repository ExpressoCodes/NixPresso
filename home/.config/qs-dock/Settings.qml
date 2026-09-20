pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/settings.js" as Lib

// Persistent settings (ARCHITECTURE §4.2, §5; ADR-0001/0002). The file is the single source of truth.
Singleton {
    id: root

    readonly property int schemaVersion: 1
    readonly property string path: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.config") + "/qs-dock/settings.json";
    }

    readonly property bool ready: _ready
    property bool _ready: false
    property bool _arming: false
    property bool _dirty: false
    // Text of our last write. A stale load of exactly this text is our own output, so it is never
    // repaired again (no write loop). Any other stale content gets one repair write.
    property string _written: ""
    property string _corruptText: ""
    property string _handoff: ""

    // Appearance
    property alias iconSize: appearance.iconSize
    property alias magnification: appearance.magnification
    property alias maxMagnifiedSize: appearance.maxMagnifiedSize
    property alias magnificationSpread: appearance.magnificationSpread
    property alias spacing: appearance.spacing
    property alias backgroundOpacity: appearance.backgroundOpacity
    property alias cornerRadius: appearance.cornerRadius
    property alias showSeparator: appearance.showSeparator
    property alias indicatorStyle: appearance.indicatorStyle
    // Position
    property alias edge: position.edge
    property alias margin: position.margin
    property alias monitors: position.monitors
    property alias onlyCurrentMonitorApps: position.onlyCurrentMonitorApps
    // Behaviour
    property alias visibilityMode: behaviour.visibilityMode
    readonly property alias lastVisibleMode: behaviour.lastVisibleMode
    readonly property alias lastHiddenMode: behaviour.lastHiddenMode
    property alias hideOnFullscreen: behaviour.hideOnFullscreen
    property alias showDelay: behaviour.showDelay
    property alias hideDelay: behaviour.hideDelay
    property alias animationSpeed: behaviour.animationSpeed
    property alias clickFocused: behaviour.clickFocused
    property alias showRunning: behaviour.showRunning
    property alias bounceOnLaunch: behaviour.bounceOnLaunch
    // Filtering
    property alias hideNoDisplay: filtering.hideNoDisplay
    readonly property alias exclusions: filtering.exclusions
    readonly property alias pins: adapter.pins

    readonly property bool hiddenMode: visibilityMode === "autohide" || visibilityMode === "intelligent"

    readonly property list<string> defaultExclusions: ["org.quickshell", "quickshell", "/^xdg-desktop-portal-.*$/", "hyprpolkitagent", "/^polkit-.*$/"]
    readonly property var defaults: ({
        iconSize: 48, magnification: true, maxMagnifiedSize: 80, magnificationSpread: 2.5, spacing: 6,
        backgroundOpacity: 85, cornerRadius: 18, showSeparator: true, indicatorStyle: "dot",
        edge: "bottom", margin: 6, monitors: "all", onlyCurrentMonitorApps: false,
        visibilityMode: "reserve", lastVisibleMode: "reserve", lastHiddenMode: "intelligent",
        hideOnFullscreen: true, showDelay: 150, hideDelay: 500, animationSpeed: 1.0, clickFocused: "cycle",
        showRunning: true, bounceOnLaunch: true, hideNoDisplay: true,
        pins: ["kitty", "brave-origin", "org.gnome.Nautilus"],
        exclusions: ["org.quickshell", "quickshell", "/^xdg-desktop-portal-.*$/", "hyprpolkitagent", "/^polkit-.*$/"]
    })
    readonly property var ranges: ({
        iconSize: [24, 128], maxMagnifiedSize: [24, 192], magnificationSpread: [1, 5], spacing: [0, 24],
        backgroundOpacity: [0, 100], cornerRadius: [0, 32], margin: [0, 40], showDelay: [0, 1000],
        hideDelay: [0, 2000], animationSpeed: [0.5, 2]
    })
    readonly property var enums: ({
        indicatorStyle: ["none", "dot", "dot-per-window"],
        edge: ["bottom", "left", "right"],
        visibilityMode: ["reserve", "overlap", "autohide", "intelligent"],
        lastVisibleMode: ["reserve", "overlap"],
        lastHiddenMode: ["autohide", "intelligent"],
        clickFocused: ["cycle", "none"]
    })
    // Numeric properties stored as int (the rest of `ranges` are real).
    readonly property var _ints: ["iconSize", "maxMagnifiedSize", "spacing", "backgroundOpacity", "cornerRadius", "margin", "showDelay", "hideDelay"]
    // Scalars restored by reset(): everything except pins/exclusions (D-12).
    readonly property var _resettable: Object.keys(defaults).filter(k => k !== "pins" && k !== "exclusions")

    // Reads the enums, not `hiddenMode`: that binding may not have re-evaluated yet inside this handler.
    onVisibilityModeChanged: {
        if (enums.lastHiddenMode.includes(visibilityMode)) behaviour.lastHiddenMode = visibilityMode;
        else if (enums.lastVisibleMode.includes(visibilityMode)) behaviour.lastVisibleMode = visibilityMode;
    }

    // Invalid patterns already warned about. A constant holder, so the binding below doesn't depend on it.
    readonly property var _warned: ({ patterns: [] })

    // Compiled exclusion matchers, rebuilt only when the list changes.
    readonly property var _matchers: {
        const out = [];
        const bad = [];
        for (const p of exclusions) {
            const entry = Lib.parseEntry(p);
            const re = entry === undefined ? Lib.parseRegex(p) : undefined;
            if (entry === "") {
                bad.push(p);
                if (!_warned.patterns.includes(p)) console.warn(`qs-dock: skipping exclusion pattern ${p} without an entry id`);
            } else if (entry !== undefined) {
                out.push({ pattern: p, entry: entry });
            } else if (re === undefined) {
                out.push({ pattern: p, exact: p });
            } else if (re === null) {
                bad.push(p);
                if (!_warned.patterns.includes(p)) console.warn(`qs-dock: skipping invalid exclusion pattern ${p}`);
            } else {
                out.push({ pattern: p, re: re });
            }
        }
        _warned.patterns = bad;
        return out;
    }

    // The first pattern that matches, or "". Exact and /regex/ patterns test the appId (D-14). An
    // `entry:<id>` pattern tests the desktop entry the appId resolves to, case-insensitively, so it catches
    // every appId variant of an app (WP-3.4). `entryId` is that resolved id ("" = none); when it's omitted
    // it's looked up through AppModel.resolve, and only if an entry pattern is reached.
    function matchExclusion(appId: string, entryId = null): string {
        let eid = entryId;
        for (const m of _matchers) {
            if (m.entry !== undefined) {
                if (eid === null) eid = (AppModel.resolve(appId)?.id ?? "").toLowerCase();
                if (eid.toLowerCase() === m.entry) return m.pattern;
            } else if (m.re ? m.re.test(appId) : m.exact === appId) {
                return m.pattern;
            }
        }
        return "";
    }

    // The pattern that hides everything resolving to desktop entry `id`.
    function entryPattern(id: string): string {
        return Lib.entryPrefix + id;
    }

    // The stored `entry:` patterns naming desktop entry `id` (case-insensitive; normally at most one).
    function entryPatternsFor(id: string): var {
        const lc = (id ?? "").toLowerCase();
        return lc === "" ? [] : exclusions.filter(p => Lib.parseEntry(p) === lc);
    }

    // Not empty after trimming; a /regex/ must compile and an `entry:` pattern needs an id.
    function isValidPattern(p: string): bool {
        const t = (p ?? "").trim();
        const entry = Lib.parseEntry(t);
        if (entry !== undefined) return entry !== "";
        return t.length > 0 && Lib.parseRegex(t) !== null;
    }

    function addExclusion(p: string): bool {
        const t = (p ?? "").trim();
        if (!isValidPattern(t) || exclusions.includes(t)) return false;
        filtering.exclusions = exclusions.concat([t]);
        return true;
    }

    function removeExclusion(p: string): bool {
        const i = exclusions.indexOf(p);
        if (i < 0) return false;
        const next = exclusions.slice();
        next.splice(i, 1);
        filtering.exclusions = next;
        return true;
    }

    function setPins(ids: list<string>): void {
        const next = Lib.dedupe(ids);
        if (!Lib.same(next, pins)) adapter.pins = next;
    }

    function setMode(mode: string): bool {
        if (!enums.visibilityMode.includes(mode)) return false;
        visibilityMode = mode;
        return true;
    }

    function toggleAutohide(): void {
        visibilityMode = hiddenMode ? lastVisibleMode : lastHiddenMode;
    }

    function reset(): void {
        for (const k of _resettable) {
            if (!Lib.same(root[k], defaults[k])) _set(k, defaults[k]);
        }
    }

    // Used by AppModel.
    function _dedupe(ids: var): var {
        return Lib.dedupe(ids);
    }

    // Writes go to the owning JsonObject; lastVisibleMode/lastHiddenMode are read-only aliases.
    function _set(k: string, v: var): void {
        if (k === "lastVisibleMode" || k === "lastHiddenMode") behaviour[k] = v;
        else if (k === "pins") adapter.pins = v;
        else if (k === "exclusions") filtering.exclusions = v;
        else root[k] = v;
    }

    // Marks the adapter changed so the debounced save writes it. writeAdapter() alone is a silent
    // no-op when nothing changed since the last write (api-findings §A5).
    function _touch(): void {
        if (adapter.version === schemaVersion) adapter.version = 0;
        adapter.version = schemaVersion;
    }

    // Runs migrations, clamps ranges and fixes enums. The file is rewritten (once) only if it doesn't
    // already hold exactly the resulting values, so a valid file is never rewritten on load.
    function _validate(raw: var, text: string): void {
        const fileVersion = typeof raw.version === "number" ? raw.version : 0;
        if (fileVersion > schemaVersion)
            console.warn(`qs-dock: settings.json has version ${fileVersion}, newer than ${schemaVersion}; unknown keys will be dropped on save`);
        else if (fileVersion < schemaVersion)
            _migrate(raw, fileVersion);

        const fix = Lib.fixups(k => root[k], { ranges: ranges, enums: enums, defaults: defaults, ints: _ints });
        for (const k in fix) _set(k, fix[k]);
        // Compared after the fixups, so clamped values count as stale too. Never rewrites a newer file.
        const stale = fileVersion < schemaVersion
            || (fileVersion === schemaVersion && Lib.needsRepair(raw, k => root[k]));
        // Keyed by content, not by "last load was stale": the echo of our own save is usually dropped
        // (it arrives while the write is in flight), so a flag would never be cleared.
        if (stale && text !== _written) _touch();
    }

    // Migration hook: one step per version bump, applied in order (step N upgrades N-1 → N).
    // A step receives the parsed file and adjusts the in-memory values through _set().
    readonly property var _migrations: ({
        // v0 → v1: files without a version key. v1 is the first schema, so nothing to convert.
        1: raw => {}
    })
    function _migrate(raw: var, from: int): void {
        for (let v = from + 1; v <= schemaVersion; v++) {
            if (_migrations[v]) _migrations[v](raw);
        }
    }

    // Keeps the in-memory values and never writes over the user's broken file on its own. A copy goes to
    // `<path>.corrupt` because the next settings change replaces the file. JsonAdapter already logged the
    // one warning (NFR-4), so this is info only.
    function _quarantine(t: string): void {
        if (t === _corruptText) return;
        _corruptText = t;
        backup.setText(t);
        console.info(`qs-dock: ${path} isn't valid settings JSON; keeping the current values. A copy is in ${backup.path}. The file is replaced on the next settings change.`);
    }

    function _snapshot(): string {
        return Lib.snapshot(k => root[k]);
    }

    // Hot reload (ADR-0001): the old generation's singleton gets no onDestruction and its Timer never
    // fires, so an unsaved change is handed over as a snapshot in PersistentProperties and applied here,
    // after the new generation's first load. Applying it marks the adapter dirty, so it gets saved.
    function _applyHandoff(): void {
        if (_handoff === "") return;
        let snap = {};
        try {
            snap = JSON.parse(_handoff);
        } catch (e) {}
        _handoff = "";
        for (const k in snap) {
            if (k in defaults && !Lib.same(root[k], snap[k])) _set(k, snap[k]);
        }
    }

    function _save(): void {
        if (!_dirty) return;
        _dirty = false;
        file.writeAdapter();
    }

    // Reading text() with blockLoading loads the file synchronously, so consumers never see defaults
    // first (no startup/reload flash) and `ready` is true before the first frame.
    Component.onCompleted: file.text()

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: root._save()
    }

    PersistentProperties {
        id: pending
        reloadableId: "qsDockSettingsPending"
        // Snapshot of the in-memory values while a save is pending, "" otherwise.
        property string json: ""

        onLoaded: {
            const old = json;
            json = root._dirty ? root._snapshot() : "";
            if (old !== "") {
                root._handoff = old;
                if (root._ready) root._applyHandoff();
            }
        }
    }

    FileView {
        id: backup
        path: root.path + ".corrupt"
        preload: false
        printErrors: false
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        blockLoading: true
        printErrors: false

        onFileChanged: reload()
        onAdapterUpdated: {
            root._dirty = true;
            pending.json = root._snapshot();
            saveTimer.restart();
        }
        onLoaded: {
            const t = text();
            let raw = null;
            try {
                raw = t.trim() === "" ? null : JSON.parse(t);
            } catch (e) {
                raw = undefined;
            }
            if (raw === null) {
                // Empty file (or an editor mid-save): nothing loaded, keep the current values.
            } else if (typeof raw !== "object" || Array.isArray(raw)) {
                root._quarantine(t);
            } else {
                root._corruptText = "";
                root._validate(raw, t);
            }
            root._ready = true;
            root._applyHandoff();
        }
        onLoadFailed: e => {
            if (e === FileViewError.FileNotFound) {
                console.warn(`qs-dock: ${root.path} not found, creating it with the current settings`);
                root._arming = true;
                root._touch();
            } else {
                console.warn(`qs-dock: can't read ${root.path} (${FileViewError.toString(e)}), using the current settings`);
            }
            root._ready = true;
            root._applyHandoff();
        }
        onSaved: {
            root._written = text();
            if (!root._dirty) pending.json = "";
            // The watch isn't armed when the file was missing, so reload once after creating it.
            // Deferred: reloading from inside the save's completion drops the operation (warning).
            if (root._arming) {
                root._arming = false;
                Qt.callLater(() => file.reload());
            }
        }
        onSaveFailed: e => {
            root._dirty = true;
            console.warn(`qs-dock: can't write ${root.path} (${FileViewError.toString(e)})`);
        }

        JsonAdapter {
            id: adapter

            property int version: 1
            property list<string> pins: ["kitty", "brave-origin", "org.gnome.Nautilus"]

            property JsonObject appearance: JsonObject {
                id: appearance
                property int iconSize: 48
                property bool magnification: true
                property int maxMagnifiedSize: 80
                property real magnificationSpread: 2.5
                property int spacing: 6
                property int backgroundOpacity: 85
                property int cornerRadius: 18
                property bool showSeparator: true
                property string indicatorStyle: "dot"
            }
            property JsonObject position: JsonObject {
                id: position
                property string edge: "bottom"
                property int margin: 6
                property string monitors: "all"
                property bool onlyCurrentMonitorApps: false
            }
            property JsonObject behaviour: JsonObject {
                id: behaviour
                property string visibilityMode: "reserve"
                property string lastVisibleMode: "reserve"
                property string lastHiddenMode: "intelligent"
                property bool hideOnFullscreen: true
                property int showDelay: 150
                property int hideDelay: 500
                property real animationSpeed: 1.0
                property string clickFocused: "cycle"
                property bool showRunning: true
                property bool bounceOnLaunch: true
            }
            property JsonObject filtering: JsonObject {
                id: filtering
                property bool hideNoDisplay: true
                property list<string> exclusions: ["org.quickshell", "quickshell", "/^xdg-desktop-portal-.*$/", "hyprpolkitagent", "/^polkit-.*$/"]
            }
        }
    }
}
