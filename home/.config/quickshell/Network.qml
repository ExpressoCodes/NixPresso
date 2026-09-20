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
                    if (type === "ethernet") { s = "Wired"; break; }
                    if (type === "wifi") {
                        const ssid = rest.join(":").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                        s = "<span style='font-family: \"Font Awesome 7 Free Solid\";'>&#xF1EB;</span> " + ssid;
                        break;
                    }
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
