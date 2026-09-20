import QtQuick
import Quickshell
import Quickshell.Bluetooth

BarButton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var paired: Bluetooth.devices.values.filter(d => d.paired)
    readonly property int connectedCount: paired.filter(d => d.connected).length

    visible: adapter !== null
    text: "<span style='font-family: \"Font Awesome 7 Brands\"; font-size: 14px; font-weight: bold;'>&#xF294;</span>"
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
                text: (modelData.connected ? "&#x25CF; " : "&#x25CB; ") + modelData.name
                    + (modelData.batteryAvailable ? `  ${Math.round(modelData.battery * 100)}%` : "")
                textColor: modelData.connected ? Theme.accent : Theme.fg
                onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hover }

        BarButton {
            width: parent.width
            text: "Bluetooth Settings"
            onClicked: {
                Quickshell.execDetached(["kitty", "-e", "bluetui"])
                popup.visible = false
            }
        }
    }
}
