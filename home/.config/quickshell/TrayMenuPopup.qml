import QtQuick
import Quickshell
import Quickshell.Hyprland

// Like Popup.qml but without HyprlandFocusGrab, which prevents clicks from
// reaching items when the popup is anchored inside a MouseArea (tray icons).
// Closes on outside activity via Hyprland window-focus events instead.
PopupWindow {
    id: popup
    required property Item anchorItem
    default property alias content: column.data

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.top: 4
    implicitWidth: Math.max(180, column.implicitWidth + 12)
    implicitHeight: column.implicitHeight + 12
    color: "transparent"
    visible: false

    function toggle() { visible = !visible }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!popup.visible) return;
            if (event.name === "activewindow" || event.name === "activewindowv2"
                    || event.name === "workspace" || event.name === "focusedmon") {
                popup.visible = false;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.popupBg
        border.color: Theme.hover
        radius: 6

        Column {
            id: column
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2
        }
    }
}
