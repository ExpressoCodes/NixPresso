import QtQuick
import qs

// Sidebar footer (UX.md §7.4): the Reset button turns into an in-place confirmation.
// D-12: reset keeps pins and the exclusion list, and the text says so.
Item {
    id: root

    property bool confirming: false
    // Emitted after a confirmed reset, so the window can move focus to the sidebar.
    signal resetDone

    width: 148
    height: confirming ? panel.implicitHeight : resetButton.height

    function ask(): void {
        confirming = true;
        timeout.restart();
        UiState.moveFocus(cancelButton);
    }

    function cancel(): void {
        confirming = false;
        timeout.stop();
        UiState.moveFocus(resetButton);
    }

    function confirm(): void {
        Settings.reset();
        confirming = false;
        timeout.stop();
        resetDone();
    }

    // Esc and the 10 s timeout both go back to the button (the window routes Esc here first).
    Timer {
        id: timeout
        interval: 10000
        onTriggered: root.cancel()
    }

    Keys.onPressed: event => {
        if (root.confirming)
            timeout.restart();
        event.accepted = false;
    }

    HoverHandler {
        enabled: root.confirming
        onHoveredChanged: timeout.restart()
    }

    Button {
        id: resetButton
        visible: !root.confirming
        width: 148
        text: "Reset to defaults…"
        onClicked: root.ask()
    }

    Column {
        id: panel
        visible: root.confirming
        width: parent.width
        spacing: 8

        Text {
            width: parent.width
            text: "Reset all settings?"
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
        }

        Text {
            width: parent.width
            text: "Pins and excluded apps are kept."
            wrapMode: Text.WordWrap
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 12
        }

        Button {
            id: cancelButton
            width: parent.width
            text: "Cancel"
            onClicked: root.cancel()
        }

        Button {
            width: parent.width
            text: "Reset"
            danger: true
            onClicked: root.confirm()
        }
    }
}
