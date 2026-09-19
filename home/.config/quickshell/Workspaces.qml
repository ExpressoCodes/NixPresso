import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
    id: root
    required property var screen
    readonly property var monitor: Hyprland.monitorFor(screen)
    spacing: 2

    Repeater {
        model: Hyprland.workspaces.values.filter(ws => ws.id > 0 && ws.monitor === root.monitor)

        BarButton {
            required property var modelData
            readonly property bool active: modelData.id === root.monitor?.activeWorkspace?.id
            text: modelData.name
            implicitWidth: Math.max(26, implicitHeight)
            color: active ? Theme.accent : (hovered ? Theme.hover : "transparent")
            textColor: active ? Theme.bg : Theme.fg
            radius: 8
            onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${modelData.id} })`)
        }
    }

    WheelHandler {
        onWheel: event => Hyprland.dispatch(`hl.dsp.focus({ workspace = "${event.angleDelta.y > 0 ? "m-1" : "m+1"}" })`)
    }
}
