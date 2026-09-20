pragma ComponentBehavior: Bound
import QtQuick
import qs

// Selectable chips (UX.md §7.3). `options` is [{ value, label }]. One tab stop; Left/Right move
// the keyboard cursor, Space selects it.
Item {
    id: root

    property var options: []
    property var current
    signal selected(var value)

    readonly property int index: options.findIndex(o => o.value === current)
    property int cursor: 0

    implicitWidth: flow.implicitWidth
    implicitHeight: flow.implicitHeight
    activeFocusOnTab: enabled && options.length > 0
    opacity: enabled ? 1 : 0.4

    onActiveFocusChanged: if (activeFocus)
        cursor = Math.max(0, index)

    Keys.onPressed: event => {
        const n = options.length;
        if (n === 0)
            return;
        if (event.key === Qt.Key_Left)
            cursor = Math.max(0, cursor - 1);
        else if (event.key === Qt.Key_Right)
            cursor = Math.min(n - 1, cursor + 1);
        else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            selected(options[Math.min(cursor, n - 1)].value);
        else
            return;
        event.accepted = true;
    }

    Row {
        id: flow
        spacing: 8

        Repeater {
            model: root.options

            Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool isSelected: chip.index === root.index

                width: label.implicitWidth + 24
                height: 26
                radius: 13
                color: isSelected ? Theme.accent : chipArea.containsMouse ? Theme.hover : Theme.popupBg
                border.width: isSelected ? 0 : 1
                border.color: Theme.surface1

                FocusRing {
                    baseRadius: 13
                    shown: root.activeFocus && root.cursor === chip.index
                }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: chip.modelData.label
                    color: chip.isSelected ? Theme.crust : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                }

                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.forceActiveFocus()
                    onClicked: {
                        root.cursor = chip.index;
                        root.selected(chip.modelData.value);
                    }
                }
            }
        }
    }
}
