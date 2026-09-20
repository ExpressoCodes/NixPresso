pragma ComponentBehavior: Bound
import QtQuick
import qs

// Sidebar group list (UX.md §7.1/§7.5). One tab stop; Up/Down change the group at once.
Column {
    id: root

    property var groups: []
    readonly property int current: UiState.settingsGroup

    activeFocusOnTab: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Up)
            UiState.selectGroup(current - 1);
        else if (event.key === Qt.Key_Down)
            UiState.selectGroup(current + 1);
        else
            return;
        event.accepted = true;
    }

    Repeater {
        model: root.groups

        Item {
            id: entry
            required property string modelData
            required property int index
            readonly property bool isSelected: entry.index === root.current

            width: root.width
            height: 36

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                radius: 6
                color: entry.isSelected ? Theme.hover : area.containsMouse ? Qt.alpha(Theme.hover, 0.5) : "transparent"

                FocusRing {
                    baseRadius: 6
                    shown: root.activeFocus && entry.isSelected
                }

                Rectangle {
                    visible: entry.isSelected
                    x: 0
                    y: 8
                    width: 3
                    height: parent.height - 16
                    radius: 1.5
                    color: Theme.accent
                }

                Text {
                    x: 14
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: entry.modelData
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.bold: entry.isSelected
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: root.forceActiveFocus()
                onClicked: {
                    UiState.selectGroup(entry.index);
                }
            }
        }
    }
}
