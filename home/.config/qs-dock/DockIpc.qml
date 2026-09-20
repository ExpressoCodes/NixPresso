import QtQuick
import Quickshell.Io

// FR-8: `qs ipc -p ~/Projects/qs-dock/src call dock <fn> [args]`.
// Every parameter and return is typed (§C7). Only string params: a missing typed int silently becomes 0.
IpcHandler {
    target: "dock"

    function settings(): void {
        UiState.toggleSettings();
    }

    // show(), hide(), toggle() → Visibility.show/hide/toggle (M4, WP-4.x). Called as `call dock -- show` (D-6).
    // state(): string → read-only debug dump of items and per-screen revealed/obstructed (D-24, M4).

    function pin(id: string): string {
        return AppModel.pin(id) ? "ok" : "error: unknown or already pinned: " + id;
    }

    function unpin(id: string): string {
        return AppModel.unpin(id) ? "ok" : "error: not pinned: " + id;
    }

    function setMode(mode: string): string {
        return Settings.setMode(mode) ? "ok" : "error: mode must be " + Settings.enums.visibilityMode.join("|");
    }
}
