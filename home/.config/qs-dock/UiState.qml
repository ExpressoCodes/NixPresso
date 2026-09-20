pragma Singleton
import QtQuick
import Quickshell

// Transient UI state (ARCHITECTURE §4.7). Survives hot reload through PersistentProperties
// (primitives only, ADR-0001); it is not written to settings.json.
Singleton {
    readonly property bool settingsOpen: persist.settingsOpen
    // Selected settings group (0 Appearance, 1 Position, 2 Behaviour, 3 Filtering).
    readonly property int settingsGroup: persist.settingsGroup
    // True while the user drives the settings window with the keyboard; focus rings show only then.
    property bool keyboardNav: false

    function openSettings(): void {
        persist.settingsOpen = true;
    }

    function closeSettings(): void {
        persist.settingsOpen = false;
    }

    function toggleSettings(): void {
        persist.settingsOpen = !persist.settingsOpen;
    }

    // True during a programmatic focus move; the settings window then leaves keyboardNav alone.
    property bool focusMoving: false

    // Programmatic focus move that keeps the current keyboard/pointer mode (no ring flash after a click).
    function moveFocus(item: Item): void {
        moveFocusAs(item, keyboardNav);
    }

    // Programmatic focus move in an explicit mode, for moves decided before an async step.
    function moveFocusAs(item: Item, keyboard: bool): void {
        keyboardNav = keyboard;
        focusMoving = true;
        item?.forceActiveFocus();
        focusMoving = false;
    }

    function selectGroup(index: int): void {
        persist.settingsGroup = Math.max(0, Math.min(3, index));
    }

    PersistentProperties {
        id: persist
        reloadableId: "qsdock-ui"

        property bool settingsOpen: false
        property int settingsGroup: 0
    }
}
