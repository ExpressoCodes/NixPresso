import QtQuick
import qs

// One settings row (UX.md §7.1): 180 px label column, 292 px control column right-aligned,
// 40 px minimum height, 1 px divider below.
Item {
    id: root

    property string label: ""
    property string help: ""
    property bool divider: true
    default property alias control: slot.data

    width: parent ? parent.width : 492
    implicitHeight: Math.max(40, labels.implicitHeight + 12, slot.implicitHeight + 12)

    Column {
        id: labels
        width: 180
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: root.label
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
        }

        Text {
            width: parent.width
            text: root.help
            visible: text !== ""
            wrapMode: Text.WordWrap
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 12
        }
    }

    Row {
        id: slot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        layoutDirection: Qt.RightToLeft
    }

    Rectangle {
        visible: root.divider
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.hover
    }
}
