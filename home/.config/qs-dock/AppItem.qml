import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// One app in the dock. Created only by AppModel's Variants (ADR-0008); everything here is read-only.
QtObject {
    id: item

    required property string modelData

    readonly property string key: modelData
    readonly property var entry: key.startsWith("appid:") ? null : AppModel.entryById(key)
    readonly property string entryId: entry?.id ?? ""

    // Creation order (§C6), so cycling is stable.
    readonly property var windows: AppModel._grouping.groups[key] ?? []
    readonly property int windowCount: windows.length
    readonly property bool running: windowCount > 0
    readonly property var appIds: {
        const ids = [];
        for (const t of windows) if (!ids.includes(t.appId)) ids.push(t.appId);
        return ids;
    }
    readonly property string appId: windows.length > 0 ? windows[0].appId
        : (entry?.startupClass || key.replace(/^appid:/, ""))

    readonly property string name: entry?.name || appId
    // Adwaita's application-x-executable uses clipPath, which Qt draws as black blocks (D-21).
    readonly property string icon: Quickshell.iconPath(entry?.icon || appId, "application-x-generic")
    readonly property bool noDisplay: entry?.noDisplay ?? false

    readonly property int pinIndex: Settings.pins.indexOf(key)
    readonly property bool pinned: pinIndex >= 0

    // ToplevelManager's active toplevel is correct from the start; Hyprland's is null until an event (§B3).
    readonly property bool active: windows.includes(ToplevelManager.activeToplevel)
    // The attached `t.HyprlandToplevel` isn't the live object in 0.3.1 (urgent stays false, D-20),
    // so join through Hyprland.toplevels by `wayland`.
    readonly property bool urgent: windows.length > 0
        && Hyprland.toplevels.values.some(h => h.urgent && windows.includes(h.wayland))
}
