pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "settings"

// "Dock Settings" (FR-6, UX.md §7). Fixed size so Hyprland floats it (D-7). Every control writes
// Settings directly; Settings owns the debounced save. Closing it clears UiState.settingsOpen.
FloatingWindow {
    id: win

    readonly property var groups: ["Appearance", "Position", "Behaviour", "Filtering"]

    title: "Dock Settings"
    implicitWidth: 720
    implicitHeight: 540
    minimumSize: Qt.size(720, 540)
    maximumSize: Qt.size(720, 540)
    color: Theme.bg

    onClosed: UiState.closeSettings()

    // Only called from keyboard shortcuts.
    function selectGroup(i: int): void {
        UiState.selectGroup((i + groups.length) % groups.length);
        UiState.moveFocusAs(groupList, true);
    }

    // A FocusScope, so focus stays inside when the focused control is destroyed (an exclusion row)
    // and the key handler below always sees the keys.
    FocusScope {
        id: root
        anchors.fill: parent
        focus: true

        // Keyboard vs. pointer focus (UX.md §7.5). A focus change right after a press came from the
        // pointer. Programmatic moves (UiState.moveFocusAs) set the mode themselves. A change onto
        // a non-tab item is a fallback (the focused row was destroyed), not navigation. Anything
        // else landing on a tab stop (Tab, Backtab) is keyboard navigation and shows the rings.
        property bool pointerFocus: false
        property Item lastFocus: null
        readonly property Item focusItem: Window.activeFocusItem

        onFocusItemChanged: {
            if (focusItem && lastFocus && !pointerFocus && !UiState.focusMoving && focusItem.activeFocusOnTab)
                UiState.keyboardNav = true;
            lastFocus = focusItem;
            // Never scroll on a pointer press: the control would move away before the release and
            // the click would be lost (QA-FR5-09).
            if (focusItem && UiState.keyboardNav && !pointerFocus)
                content.ensureVisible(focusItem);
        }

        Component.onCompleted: UiState.keyboardNav = false

        Rectangle {
            width: 180
            height: parent.height
            color: Theme.popupBg
        }

        // Tab order: sidebar list → page controls → Reset (item order, see ResetPanel below).
        GroupList {
            id: groupList
            y: 16
            width: 180
            groups: win.groups
            focus: true
        }

        Flickable {
            id: content
            x: 180
            width: 540
            height: parent.height
            clip: true
            contentWidth: width
            contentHeight: pages.height + 48
            boundsBehavior: Flickable.StopAtBounds

            // Scrolls so the focused control is fully visible, with a 16 px margin.
            function ensureVisible(item: Item): void {
                let p = item;
                while (p && p !== pages)
                    p = p.parent;
                if (!p)
                    return;
                const r = item.mapToItem(pages, 0, 0, item.width, item.height);
                const top = r.y + 24 - 16;
                const bottom = r.y + 24 + r.height + 16;
                if (top < contentY)
                    contentY = Math.max(0, top);
                else if (bottom > contentY + height)
                    contentY = Math.min(contentHeight - height, bottom - height);
            }

            Item {
                id: pages
                x: 24
                y: 24
                width: 492
                height: [appearance, position, behaviour, filtering][UiState.settingsGroup].height

                AppearancePage {
                    id: appearance
                    visible: UiState.settingsGroup === 0
                }
                PositionPage {
                    id: position
                    visible: UiState.settingsGroup === 1
                }
                BehaviourPage {
                    id: behaviour
                    visible: UiState.settingsGroup === 2
                }
                FilteringPage {
                    id: filtering
                    visible: UiState.settingsGroup === 3
                }
            }

            Connections {
                target: UiState
                function onSettingsGroupChanged(): void {
                    content.contentY = 0;
                }
            }
        }

        // 6 px scrollbar, only when the page overflows.
        Rectangle {
            visible: content.contentHeight > content.height
            x: content.x + content.width - 8
            y: content.visibleArea.yPosition * content.height
            width: 6
            height: content.visibleArea.heightRatio * content.height
            radius: 3
            color: Theme.surface2
        }

        ResetPanel {
            id: resetPanel
            x: 16
            y: parent.height - height - 16
            onResetDone: UiState.moveFocus(groupList)
        }

        // Pointer-press observer on top of everything; it never accepts the press.
        MouseArea {
            anchors.fill: parent
            z: 100
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => {
                UiState.keyboardNav = false;
                root.pointerFocus = true;
                Qt.callLater(() => root.pointerFocus = false);
                mouse.accepted = false;
            }
        }

        // Window shortcuts (UX.md §7.5). Keys, not Shortcut: a Shortcut inside a FloatingWindow
        // crashes Quickshell on shutdown (QShortcutMap::removeShortcut after the window is gone).
        // Unaccepted keys bubble up here from the focused control; Ctrl+Tab is never taken by
        // the Tab focus chain.
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            const shift = event.modifiers & Qt.ShiftModifier;
            const k = event.key;
            if (k === Qt.Key_Escape && !ctrl) {
                if (resetPanel.confirming)
                    resetPanel.cancel();
                else
                    UiState.closeSettings();
            } else if (!ctrl) {
                return;
            } else if (k === Qt.Key_W) {
                UiState.closeSettings();
            } else if (k >= Qt.Key_1 && k <= Qt.Key_4 && !shift) {
                win.selectGroup(k - Qt.Key_1);
            } else if (k === Qt.Key_Backtab || (k === Qt.Key_Tab && shift)) {
                win.selectGroup(UiState.settingsGroup - 1);
            } else if (k === Qt.Key_Tab) {
                win.selectGroup(UiState.settingsGroup + 1);
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
