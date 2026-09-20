//@ pragma IconTheme Adwaita
import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    // Singletons are lazy and nothing else touches HyprEvents yet; without this, new windows
    // keep an empty lastIpcObject and focusing the most recent window breaks.
    Component.onCompleted: HyprEvents.requestRefresh()

    // One dock per selected monitor (D-3, FR-6 "Monitors"). If nothing matches (the named monitor
    // is unplugged, or no monitor is focused yet) every screen gets one, so the dock never vanishes.
    Variants {
        model: {
            const screens = Quickshell.screens;
            const want = Settings.monitors === "all" ? ""
                       : Settings.monitors === "focused" ? (Hyprland.focusedMonitor?.name ?? "")
                       : Settings.monitors;
            const picked = want === "" ? [] : screens.filter(s => s.name === want);
            return picked.length > 0 ? picked : screens;
        }
        Dock {}
    }

    LazyLoader {
        active: UiState.settingsOpen
        SettingsWindow {}
    }

    DockIpc {}
}
