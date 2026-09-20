pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// Joins pins + toplevels + desktop entries + exclusions into stable AppItems (ARCHITECTURE §4.3, ADR-0004/0008).
Singleton {
    id: root

    // After a hot reload applicationsChanged never fires again, hence the length check (§C8).
    // Reading `applications` here also starts the lazy desktop-entry scan (§C3).
    readonly property bool _entriesLoaded: _entriesSeen || DesktopEntries.applications.values.length > 0
    readonly property bool ready: Settings.ready && _entriesLoaded

    property bool _entriesSeen: false
    property int _entriesRev: 0
    property var _cache: Object.create(null)

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root._cache = Object.create(null);
            root._entriesSeen = true;
            root._entriesRev++;
        }
    }

    readonly property var _pinKeys: ready ? Settings._dedupe(Settings.pins) : []

    // Pure pass over the toplevels (creation order, §C6): key → windows, plus first-seen key order.
    readonly property var _grouping: {
        const groups = Object.create(null);
        const order = [];
        if (!ready) return { groups, order };
        const pins = _pinKeys;
        for (const t of ToplevelManager.toplevels.values) {
            const appId = t.appId;
            if (!appId) continue;
            const e = resolve(appId);
            if (Settings.matchExclusion(appId, e?.id ?? "") !== "") continue;
            const key = e ? e.id : "appid:" + appId;
            if (!pins.includes(key) && (!Settings.showRunning || (Settings.hideNoDisplay && e?.noDisplay)))
                continue;
            if (!groups[key]) {
                groups[key] = [];
                order.push(key);
            }
            groups[key].push(t);
        }
        return { groups, order };
    }

    // Every list below reads _pinKeys and _grouping directly, never a derived sibling: bindings update
    // eagerly, so a "running keys" binding could still hold its old value when _pinKeys changes. Pinning a
    // running app then gave `pins + old running`, a duplicate key (Variants WARN), and unpinning one briefly
    // dropped its key (AppItem destroyed and re-created, against ADR-0008). Pins first, de-duplicated.
    readonly property list<string> _keys: {
        const keys = _pinKeys.slice();
        for (const k of _grouping.order) if (!keys.includes(k)) keys.push(k);
        return keys;
    }

    // One AppItem per key, kept across reorders and running/pinned changes (§C2).
    Variants {
        id: registry
        model: root._keys
        AppItem {}
    }

    // `instances` is in creation order, so always look items up by key.
    readonly property var _byKey: {
        const m = Object.create(null);
        for (const o of registry.instances) m[o.key] = o;
        return m;
    }

    readonly property var pinnedItems: _pinKeys.map(k => _byKey[k]).filter(o => !!o)
    readonly property var runningItems: _grouping.order.filter(k => !_pinKeys.includes(k)).map(k => _byKey[k]).filter(o => !!o)
    readonly property var items: pinnedItems.concat(runningItems)
    readonly property int pinnedCount: pinnedItems.length
    readonly property int runningCount: runningItems.length

    // Every non-empty appId, excluded and NoDisplay ones included (settings picker, UX §7.3).
    readonly property var runningAppIds: {
        const ids = [];
        for (const t of ToplevelManager.toplevels.values)
            if (t.appId && !ids.includes(t.appId)) ids.push(t.appId);
        return ids.sort();
    }

    function itemFor(key: string): var {
        return _byKey[key] ?? null;
    }

    // Entry for a pin or key. Null until DesktopEntries has loaded.
    // `_entriesRev < 0` is never true: reading it makes calling bindings re-run when entries change.
    function entryById(id: string): var {
        if (_entriesRev < 0 || !id || !_entriesLoaded) return null;
        return DesktopEntries.byId(id) ?? null;
    }

    // Lower-cased startupClass → entry and id → entry over the displayed entries. It's rebuilt only when
    // _entriesRev changes. Entries are sorted by id and the first one wins, so ties are deterministic.
    readonly property var _index: {
        const wm = Object.create(null);
        const ids = Object.create(null);
        if (_entriesRev < 0 || !_entriesLoaded) return { wm, ids };
        const all = DesktopEntries.applications.values.slice().sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
        for (const a of all) {
            const c = (a.startupClass ?? "").toLowerCase();
            if (c !== "" && !(c in wm)) wm[c] = a;
            const i = a.id.toLowerCase();
            if (!(i in ids)) ids[i] = a;
        }
        return { wm, ids };
    }

    // ADR-0004: heuristic lookup, then byId, then the index fallbacks, then a displayed twin for NoDisplay hits.
    // Cached per appId.
    function resolve(appId: string): var {
        if (_entriesRev < 0 || !appId || !_entriesLoaded) return null;
        if (appId in _cache) return _cache[appId];
        let e = DesktopEntries.heuristicLookup(appId) ?? DesktopEntries.byId(appId) ?? _fallback(appId);
        if (e?.noDisplay) e = _displayedTwin(appId, e) ?? e;
        _cache[appId] = e;
        return e;
    }

    // Reverse-DNS appIds whose entry only knows the short name, e.g. org.localsend.localsend_app →
    // LocalSend.desktop (StartupWMClass=localsend_app). Step order: full appId as startupClass, then the last
    // segment as startupClass, then as entry id (NoDisplay entries only through byId), then the two trailing
    // segments joined with a dash (e.g. dev.hyprland.settings → hyprland-settings).
    function _fallback(appId: string): var {
        const lc = appId.toLowerCase();
        if (lc in _index.wm) return _index.wm[lc];
        const dot = lc.lastIndexOf(".");
        const seg = dot >= 0 ? lc.slice(dot + 1) : "";
        if (seg === "") return null;
        const byLast = _index.wm[seg] ?? _index.ids[seg] ?? DesktopEntries.byId(appId.slice(dot + 1)) ?? null;
        if (byLast) return byLast;
        const prevDot = lc.lastIndexOf(".", dot - 1);
        if (prevDot < 0) return null;
        const twoSeg = lc.slice(prevDot + 1, dot) + "-" + seg;
        return _index.wm[twoSeg] ?? _index.ids[twoSeg] ?? DesktopEntries.byId(twoSeg) ?? null;
    }

    function _displayedTwin(appId: string, e: var): var {
        const lc = s => (s ?? "").toLowerCase();
        const ids = [lc(appId), lc(e.startupClass)].filter(s => s !== "");
        const cmd = (e.command ?? []).join("");
        return DesktopEntries.applications.values.find(a => !a.noDisplay
            && (ids.includes(lc(a.startupClass)) || (cmd !== "" && (a.command ?? []).join("") === cmd))) ?? null;
    }

    // Mutations (FR-4, ARCHITECTURE §4.3). They change Settings synchronously, so one debounced save writes
    // them within ~300 ms. Keys only move between sections, so AppItems survive (ADR-0008).

    // Index of a pin (an entry id, i.e. a pinned item's key), or -1.
    function pinIndexOf(key: string): int {
        return Settings.pins.indexOf(key);
    }

    // The entry a pin request means. Accepts an item key, a running appId or an entry id (D-31):
    // `org.localsend.localsend_app` → LocalSend. Running appIds go through resolve() so the pin gets the
    // same key as the running item, which then just moves into the pinned section.
    function _entryFor(id: string): var {
        if (!id || !ready) return null;
        const item = itemFor(id);
        if (item) return item.entry;
        if (id.startsWith("appid:") || runningAppIds.includes(id)) return resolve(id.replace(/^appid:/, ""));
        const e = entryById(id);
        if (e?.noDisplay) return _displayedTwin(id, e) ?? e;
        return e ?? resolve(id);
    }

    // False before `ready`, for apps without a desktop entry (D-18) and for duplicates. Reordering an
    // existing pin is movePin's job. An out-of-range index appends. Pinning drops the entry's own
    // `entry:` exclusion (left by "Hide from Dock"), so a re-pinned app shows its windows again.
    function pin(id: string, index = -1): bool {
        const e = _entryFor(id);
        if (!e || Settings.pins.includes(e.id)) return false;
        const next = Settings.pins.slice();
        if (index < 0 || index >= next.length) next.push(e.id);
        else next.splice(index, 0, e.id);
        for (const p of Settings.entryPatternsFor(e.id)) Settings.removeExclusion(p);
        Settings.setPins(next);
        return true;
    }

    // The exact stored pin id (D-29), or anything pin() would accept for it (an appId, a NoDisplay twin).
    function unpin(id: string): bool {
        let i = Settings.pins.indexOf(id);
        if (i < 0) {
            const e = _entryFor(id);
            i = e ? Settings.pins.indexOf(e.id) : -1;
        }
        if (i < 0) return false;
        const next = Settings.pins.slice();
        next.splice(i, 1);
        Settings.setPins(next);
        return true;
    }

    // Moves pin `from` so it ends up at index `to`. `to` is clamped, so a drop past the end means "last".
    // False (nothing written) for a bad `from` or when nothing moves.
    function movePin(from: int, to: int): bool {
        const next = Settings.pins.slice();
        if (from < 0 || from >= next.length) return false;
        const dest = Math.max(0, Math.min(next.length - 1, to));
        if (from === dest) return false;
        next.splice(dest, 0, next.splice(from, 1)[0]);
        Settings.setPins(next);
        return true;
    }

    // FR-3 "Hide from Dock". Anything that resolves to a desktop entry (an item key, an entry id, a running or
    // stopped appId) is hidden by `entry:<id>`, so every appId the app may report later is covered, even
    // when it has never run this session (WP-3.4: LocalSend's `org.localsend.localsend_app` vs its
    // StartupWMClass `localsend_app`). Apps without an entry fall back to their exact appIds. A pinned app
    // is unpinned as well (D-33): pins ignore exclusions (D-18), so it would otherwise stay in the dock with
    // no running state. That holds for a pin whose entry is gone too, so the exact stored pin id wins.
    function hide(id: string): bool {
        if (!id || !ready) return false;
        const item = itemFor(id);
        const e = item ? item.entry : _entryFor(id);
        let patterns;
        if (e) patterns = [Settings.entryPattern(e.id)];
        else if (item) patterns = item.appIds.length > 0 ? item.appIds : [item.appId];
        else patterns = [id.replace(/^appid:/, "")];
        let changed = false;
        for (const p of patterns) if (Settings.addExclusion(p)) changed = true;
        const pinId = Settings.pins.includes(id) ? id
            : item && Settings.pins.includes(item.key) ? item.key
            : e ? e.id : "";
        if (pinId !== "" && unpin(pinId)) changed = true;
        return changed;
    }

    // The exclusion editor's label for a pattern: an `entry:` pattern shows the entry's name, anything else
    // (or an entry that isn't installed) the stored string.
    function patternLabel(p: string): string {
        if (!p.startsWith("entry:")) return p;
        return entryById(p.slice(6).trim())?.name || p;
    }
}
