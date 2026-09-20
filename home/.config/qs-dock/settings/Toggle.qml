import QtQuick
import qs

// On/off switch (UX.md §7.3): 36 × 20 track inside a 44 × 28 hit area.
Item {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 44
    implicitHeight: 28
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.4

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.toggled(!root.checked);
            event.accepted = true;
        }
    }

    Rectangle {
        id: trackRect
        anchors.centerIn: parent
        width: 36
        height: 20
        radius: 10
        color: root.checked ? Theme.accent : Theme.surface1
        border.width: root.checked ? 0 : 1
        border.color: Theme.dim

        Behavior on color {
            ColorAnimation { duration: Theme.dur(120) }
        }

        FocusRing {
            baseRadius: 10
            shown: root.activeFocus
        }

        Rectangle {
            x: root.checked ? parent.width - width - 3 : 3
            y: 3
            width: 14
            height: 14
            radius: 7
            color: root.checked ? Theme.crust : Theme.overlay2

            Behavior on x {
                NumberAnimation { duration: Theme.dur(120); easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: {
            root.toggled(!root.checked);
        }
    }
}
