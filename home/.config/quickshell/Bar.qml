import QtQuick
import Quickshell

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    color: "transparent"
    margins { top: 6; left: 7; right: 7 }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Left: workspaces
    Island {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        padding: 4

        Workspaces {
            screen: bar.modelData
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Center: date/time
    Island {
        anchors.centerIn: parent
        padding: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }

    // Right: tray, bluetooth, network, session
    Island {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Tray { bar: bar; anchors.verticalCenter: parent.verticalCenter }
        BluetoothButton { anchors.verticalCenter: parent.verticalCenter }
        Network { anchors.verticalCenter: parent.verticalCenter }
        SessionButton { anchors.verticalCenter: parent.verticalCenter }
    }
}
