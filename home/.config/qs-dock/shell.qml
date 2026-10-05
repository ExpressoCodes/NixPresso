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
            // Fully disabled: no Dock is instantiated, so there is no window and no reserved
            // space on any screen. The settings window (IPC) and DockIpc stay available so the
            // dock can be re-enabled. This is distinct from the autohide visibility modes.
            if (!Settings.enabled)
                return [];
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
