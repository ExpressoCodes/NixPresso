import QtQuick
import qs

// 2 px keyboard focus outline drawn 2 px outside its parent (UX.md §7.5, focus.ring).
// Only shown while the user is navigating with the keyboard, never after a mouse click.
Rectangle {
    property real baseRadius: 6
    property bool shown: false

    anchors.fill: parent
    anchors.margins: -4
    radius: baseRadius + 4
    color: "transparent"
    border.width: 2
    border.color: Theme.accent
    visible: shown && UiState.keyboardNav
}
