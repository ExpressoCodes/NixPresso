import QtQuick
import qs

// Push button (UX.md §7.3). `danger` uses control.dangerButton.
Rectangle {
    id: root

    property string text: ""
    property bool danger: false
    signal clicked

    implicitWidth: Math.max(64, label.implicitWidth + 28)
    implicitHeight: 30
    radius: 6
    color: danger ? (area.containsMouse ? Qt.lighter(Theme.red, 1.08) : Theme.red)
                  : (area.containsMouse ? Theme.surface1 : Theme.hover)
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.4

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.clicked();
            event.accepted = true;
        }
    }

    FocusRing {
        baseRadius: 6
        shown: root.activeFocus
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger ? Theme.crust : Theme.fg
        font.family: Theme.font
        font.pixelSize: 13
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: {
            root.clicked();
        }
    }
}
