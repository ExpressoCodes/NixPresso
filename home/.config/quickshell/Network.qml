import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: root
    property string status: "…"

    text: status
    onClicked: Quickshell.execDetached(["kitty", "-e", "nmtui"])

    Process {
        id: proc
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = "Offline";
                for (const line of text.trim().split("\n")) {
                    const [type, state, ...rest] = line.split(":");
                    if (state !== "connected") continue;
                    if (type === "ethernet") { s = "<span style='font-family: \"Font Awesome 7 Free Solid\";'>&#xF796;</span>"; break; }
                    if (type === "wifi") { s = "<span style='font-family: \"Font Awesome 7 Free Solid\";'>&#xF1EB;</span>"; break; }
                }
                root.status = s;
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }
}
