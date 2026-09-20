import QtQuick
import qs

// One row of the exclusion list (UX.md §7.2): the pattern (an `entry:` one by app name), a
// "default" or "app" tag, and [×].
Item {
    id: row

    required property string modelData
    required property int index
    property bool divider: true
    readonly property Item removeButton: remove

    signal removeRequested
    // The [×] got focus (Tab), so the list can scroll it into view.
    signal focused

    // An `entry:` pattern reads as the app's name, with its id muted after it. An id that no
    // longer resolves shows the stored string verbatim.
    readonly property string label: AppModel.patternLabel(modelData)
    readonly property bool named: modelData.startsWith("entry:") && label !== modelData
    readonly property real textWidth: width - 11 - defaultTag.width - remove.width - 24

    height: 32

    Text {
        id: labelText
        x: 11
        width: row.named ? Math.min(implicitWidth, row.textWidth * 0.6) : row.textWidth
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: row.label
        color: Theme.fg
        font.family: row.named ? Theme.font : "monospace"
        font.pixelSize: row.named ? 13 : 12
    }

    Text {
        visible: row.named
        x: labelText.x + labelText.width + 8
        width: Math.max(0, row.textWidth - labelText.width - 8)
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
        text: row.named ? row.modelData.slice(6).trim() : ""
        color: Theme.subtext0
        font.family: "monospace"
        font.pixelSize: 12
    }

    Text {
        id: defaultTag
        anchors.right: remove.left
        anchors.rightMargin: 12
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: Settings.defaultExclusions.includes(row.modelData) ? "default" : row.named ? "app" : ""
        color: Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 12
    }

    Rectangle {
        id: remove
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 6
        color: removeArea.containsMouse ? Theme.hover : "transparent"
        activeFocusOnTab: true

        onActiveFocusChanged: {
            if (activeFocus)
                row.focused();
        }

        Keys.onPressed: event => {
            const k = event.key;
            if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Delete) {
                row.removeRequested();
                event.accepted = true;
            }
        }

        FocusRing {
            baseRadius: 6
            shown: remove.activeFocus
        }

        Text {
            anchors.centerIn: parent
            text: "×"
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 16
        }

        MouseArea {
            id: removeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.removeRequested()
        }
    }

    Rectangle {
        visible: row.divider
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.hover
    }
}
