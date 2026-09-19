import QtQuick
import Quickshell

BarButton {
    id: root
    text: Quickshell.env("USER") + " ▾"
    onClicked: popup.toggle()

    Popup {
        id: popup
        anchorItem: root

        Repeater {
            model: [
                { label: "Lock",      cmd: ["hyprlock"] },
                { label: "Log out",   cmd: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
                { label: "Restart",   cmd: ["systemctl", "reboot"] },
                { label: "Shut down", cmd: ["systemctl", "poweroff"] },
            ]

            BarButton {
                required property var modelData
                width: parent.width
                text: modelData.label
                onClicked: {
                    popup.visible = false;
                    Quickshell.execDetached(modelData.cmd);
                }
            }
        }
    }
}
