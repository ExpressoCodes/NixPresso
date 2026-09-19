import QtQuick
import Quickshell
import Quickshell.Hyprland

// Dropdown anchored under an item on the bar; closes on outside click.
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

    HyprlandFocusGrab {
        id: grab
        windows: [popup]
        active: false
        onCleared: popup.visible = false
    }

    onVisibleChanged: {
        if (visible) Qt.callLater(() => { grab.active = true })
        else grab.active = false
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
