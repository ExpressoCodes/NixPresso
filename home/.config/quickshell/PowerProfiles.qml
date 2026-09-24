import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: root
    property string profile: "balanced"

    readonly property var icons: ({
        "performance": "<span style='font-family: \"Font Awesome 7 Free Solid\"; font-size: 14px;'>&#xF0E7;</span>",
        "balanced":    "<span style='font-family: \"Font Awesome 7 Free Solid\"; font-size: 14px;'>&#xF192;</span>",
        "power-saver": "<span style='font-family: \"Font Awesome 7 Free Solid\"; font-size: 14px;'>&#xF06C;</span>",
    })

    text: icons[profile] ?? profile
    onClicked: popup.toggle()

    Process {
        id: getProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: root.profile = text.trim()
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: getProc.running = true
    }

    Process {
        id: setProc
        property string target: ""
        command: ["powerprofilesctl", "set", target]
        onRunningChanged: if (!running && target !== "") getProc.running = true
    }

    Popup {
        id: popup
        anchorItem: root

        Repeater {
            model: ["power-saver", "balanced", "performance"]

            BarButton {
                required property var modelData
                width: parent.width
                text: (modelData === root.profile ? "&#x25CF; " : "&#x25CB; ") + modelData
                textColor: modelData === root.profile ? Theme.accent : Theme.fg
                onClicked: {
                    popup.visible = false
                    setProc.target = modelData
                    setProc.running = true
                }
            }
        }
    }
}
