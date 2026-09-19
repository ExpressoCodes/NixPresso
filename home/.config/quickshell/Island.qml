import QtQuick

// A rounded pill that holds a horizontal row of bar items.
Rectangle {
    default property alias content: row.data
    property alias spacing: row.spacing
    property int padding: 8

    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: Theme.barHeight
    color: Qt.alpha(Theme.bg, Theme.barOpacity)
    radius: 10
    border.color: Theme.hover

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
    }
}
