import QtQuick
import Quickshell
import Quickshell.Bluetooth

BarButton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var paired: Bluetooth.devices.values.filter(d => d.paired)
    readonly property int connectedCount: paired.filter(d => d.connected).length

    visible: adapter !== null
    text: !adapter?.enabled ? "BT: off" : connectedCount > 0 ? "BT: " + connectedCount : "BT"
    textColor: adapter?.enabled ? Theme.fg : Theme.dim
    onClicked: popup.toggle()

    Popup {
        id: popup
        anchorItem: root

        BarButton {
            width: parent.width
            text: root.adapter?.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
            onClicked: root.adapter.enabled = !root.adapter.enabled
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hover; visible: root.paired.length > 0 }

        Repeater {
            model: root.adapter?.enabled ? root.paired : []

            BarButton {
                required property var modelData
                width: parent.width
                text: (modelData.connected ? "● " : "○ ") + modelData.name
                    + (modelData.batteryAvailable ? `  ${Math.round(modelData.battery * 100)}%` : "")
                textColor: modelData.connected ? Theme.accent : Theme.fg
                onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
            }
        }
    }
}
