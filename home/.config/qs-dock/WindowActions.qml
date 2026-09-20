pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Window actions for dock items (ARCHITECTURE §4.5). Focus goes through a Hyprland dispatch,
// because Toplevel.activate() is a no-op on this system (D-10). Close uses Toplevel.close(),
// which is bound to the surface, so a reused address can't hit the wrong window.
Singleton {
    id: root

    signal launched(string key)

    readonly property string _home: Quickshell.env("HOME") || ""

    // FR-2 left click.
    function activate(item: var): void {
        if (!item)
            return;
        if (!item.windows || item.windows.length === 0)
            launch(item);
        else if (!item.active)
            focus(mruWindow(item));
        else if (Settings.clickFocused === "cycle")
            cycle(item, 1);
    }

    // Starts a new instance in $HOME rather than the dock's cwd (D-19).
    function launch(item: var): bool {
        const entry = item?.entry;
        if (!entry)
            return false;
        _exec(entry, entry.command);
        launched(item.key);
        return true;
    }

    function runAction(item: var, action: var): void {
        if (!item || !action)
            return;
        if (item.entry && action.command && action.command.length > 0)
            _exec(item.entry, action.command);
        else
            action.execute();
        launched(item.key);
    }

    function focus(toplevel: var): bool {
        const address = hyprFor(toplevel)?.address;
        if (!address)
            return false;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + address + '" })');
        return true;
    }

    function cycle(item: var, step: int): void {
        const wins = item?.windows ?? [];
        const n = wins.length;
        if (n === 0)
            return;
        const i = wins.indexOf(ToplevelManager.activeToplevel);
        if (i < 0)
            focus(mruWindow(item));
        else
            focus(wins[((i + step) % n + n) % n]);
    }

    // Read at call time only, never in a binding (ADR-0009).
    function mruWindow(item: var): var {
        const sorted = windowsByRecency(item);
        return sorted.length > 0 ? sorted[0] : null;
    }

    // Most recent first. Windows without a focusHistoryID yet (just opened, refresh pending)
    // count as newest; among those the later-created one wins.
    function windowsByRecency(item: var): var {
        const wins = item?.windows ?? [];
        const ranked = wins.map((t, index) => {
            const id = hyprFor(t)?.lastIpcObject?.focusHistoryID;
            return { t: t, index: index, id: typeof id === "number" && id >= 0 ? id : -1 };
        });
        ranked.sort((a, b) => {
            if (a.id < 0 || b.id < 0) {
                if (a.id < 0 && b.id < 0)
                    return b.index - a.index;
                return a.id < 0 ? -1 : 1;
            }
            return a.id - b.id;
        });
        return ranked.map(r => r.t);
    }

    // The attached `toplevel.HyprlandToplevel` is a separate object that only has `address` and
    // `wayland`: title, workspace, monitor, urgent and lastIpcObject stay empty. The live object is
    // the one in Hyprland.toplevels. Click-time only (O(n)).
    function hyprFor(toplevel: var): var {
        if (!toplevel)
            return null;
        const values = Hyprland.toplevels.values;
        for (let i = 0; i < values.length; i++) {
            if (values[i].wayland === toplevel)
                return values[i];
        }
        return toplevel.HyprlandToplevel ?? null;
    }

    function close(toplevel: var): void {
        toplevel?.close();
    }

    // FR-3 "Quit". Copy first: closing mutates the window list.
    function closeAll(item: var): void {
        (item?.windows ?? []).slice().forEach(t => t.close());
    }

    // Terminal entries need the terminal wrapping only execute() knows about.
    function _exec(entry: var, command: var): void {
        if (entry.runInTerminal || !command || command.length === 0) {
            entry.execute();
            return;
        }
        Quickshell.execDetached({
            command: command,
            workingDirectory: entry.workingDirectory || root._home
        });
    }
}
