pragma ComponentBehavior: Bound
import QtQuick
import qs

// Exclusion list editor (UX.md §7.3, D-14). Rows show the stored strings: an exact appId, a
// /regex/, or entry:<desktop id> (shown by app name). Validation goes through Settings.isValidPattern.
// The list box has a fixed height (5 rows, the default count) and scrolls, and the error line
// always takes its space, so adding or removing a pattern never moves the field, Add, or the
// running-apps picker below it under the pointer.
Column {
    id: root

    readonly property int visibleRows: 5
    readonly property int count: Settings.exclusions.length
    property int lastCount: count
    property string error: ""

    width: parent ? parent.width : 492
    spacing: 8

    // A new pattern is appended, so scroll it into view; after a removal just stay in bounds.
    onCountChanged: {
        flick.settle(count > lastCount);
        lastCount = count;
    }

    function add(): void {
        const t = field.text.trim();
        if (t === "")
            error = "Enter an appId, /regex/ or entry:<desktop id>";
        else if (!Settings.isValidPattern(t))
            error = t.startsWith("entry:") ? "entry: needs a desktop entry id" : "Invalid regular expression";
        else if (Settings.exclusions.includes(t))
            error = "Already in the list";
        else if (Settings.addExclusion(t)) {
            field.text = "";
            error = "";
        }
        UiState.moveFocus(field);
    }

    // The Repeater rebuilds its rows when the list changes, so focus is restored afterwards: on
    // the next row's remove button, or on the field when the list is empty. The mode is taken
    // now, because the rebuild itself moves focus.
    function removeAt(i: int): void {
        const keyboard = UiState.keyboardNav;
        Settings.removeExclusion(Settings.exclusions[i]);
        Qt.callLater(() => {
            const n = Settings.exclusions.length;
            const next = n > 0 ? rows.itemAt(Math.min(i, n - 1)) : null;
            UiState.moveFocusAs(next ? next.removeButton : field, keyboard);
        });
    }

    Rectangle {
        width: root.width
        height: root.visibleRows * 32 + 2
        radius: 6
        color: Theme.popupBg
        border.width: 1
        border.color: Theme.surface1

        Text {
            visible: root.count === 0
            x: 12
            height: 34
            verticalAlignment: Text.AlignVCenter
            text: "No excluded apps"
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 12
        }

        Flickable {
            id: flick
            x: 1
            y: 1
            width: parent.width - 2
            height: parent.height - 2
            clip: true
            contentWidth: width
            // From the count, not list.height: the Column passes through intermediate heights
            // while the Repeater rebuilds, which would reset the scroll position.
            contentHeight: root.count * 32
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            function settle(end: bool): void {
                const max = Math.max(0, root.count * 32 - height);
                contentY = end ? max : Math.min(contentY, max);
            }

            // Keyboard only; y from the index, since a freshly rebuilt row isn't positioned yet.
            function reveal(index: int): void {
                const y = index * 32;
                if (!UiState.keyboardNav)
                    return;
                if (y < contentY)
                    contentY = y;
                else if (y + 32 > contentY + height)
                    contentY = y + 32 - height;
            }

            Column {
                id: list
                width: flick.width

                Repeater {
                    id: rows
                    model: Settings.exclusions

                    ExclusionRow {
                        id: row
                        width: list.width
                        divider: row.index < root.count - 1
                        onRemoveRequested: root.removeAt(row.index)
                        onFocused: flick.reveal(row.index)
                    }
                }
            }
        }

        // 4 px scrollbar, only when the list overflows.
        Rectangle {
            visible: flick.interactive
            x: parent.width - 7
            y: 1 + flick.visibleArea.yPosition * flick.height
            width: 4
            height: flick.visibleArea.heightRatio * flick.height
            radius: 2
            color: Theme.surface2
        }
    }

    Row {
        spacing: 8

        Rectangle {
            width: root.width - addButton.width - 8
            height: 30
            radius: 6
            color: Theme.popupBg
            border.width: 1
            border.color: root.error !== "" ? Theme.red : field.activeFocus ? Theme.surface2 : Theme.surface1

            FocusRing {
                baseRadius: 6
                shown: field.activeFocus
            }

            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                activeFocusOnTab: true
                selectByMouse: true
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.crust
                font.family: "monospace"
                font.pixelSize: 12

                onTextEdited: root.error = ""
                onAccepted: root.add()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: field.text === ""
                    text: "appId, /regex/ or entry:<desktop id>"
                    color: Theme.subtext0
                    font: field.font
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                acceptedButtons: Qt.NoButton
            }
        }

        Button {
            id: addButton
            text: "Add"
            onClicked: root.add()
        }
    }

    // Fixed height: the text overflows into the next label's top padding, so an error doesn't
    // push the picker down.
    Item {
        width: root.width
        height: 10

        Text {
            text: root.error
            color: Theme.red
            font.family: Theme.font
            font.pixelSize: 12
        }
    }
}
