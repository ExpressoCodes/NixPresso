import QtQuick

// Simple text button used across the bar and popups.
Rectangle {
    id: root
    property alias text: label.text
    property color textColor: Theme.fg
    readonly property bool hovered: area.containsMouse
    signal clicked(var mouse)

    implicitWidth: label.implicitWidth + 16
    implicitHeight: Theme.barHeight - 6
    radius: 4
    color: area.containsMouse ? Theme.hover : "transparent"

    Text {
        id: label
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        color: root.textColor
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => root.clicked(mouse)
    }
}
