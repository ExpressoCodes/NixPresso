pragma ComponentBehavior: Bound
import QtQuick
import qs

// Vertical radio list (UX.md §7.3). `options` is [{ value, label, description }]. One tab stop;
// Up/Down move the selection and apply at once.
Item {
    id: root

    property var options: []
    property var current
    signal selected(var value)

    readonly property int index: options.findIndex(o => o.value === current)

    implicitWidth: 292
    implicitHeight: column.implicitHeight
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.4

    function step(d: int): void {
        const n = options.length;
        if (n === 0)
            return;
        const i = index < 0 ? 0 : Math.max(0, Math.min(n - 1, index + d));
        if (options[i].value !== current)
            selected(options[i].value);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Up)
            step(-1);
        else if (event.key === Qt.Key_Down)
            step(1);
        else
            return;
        event.accepted = true;
    }

    FocusRing {
        baseRadius: 6
        shown: root.activeFocus
    }

    Column {
        id: column
        width: parent.width

        Repeater {
            model: root.options

            Item {
                id: opt
                required property var modelData
                required property int index
                readonly property bool isSelected: opt.index === root.index

                width: column.width
                height: 44

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: optArea.containsMouse ? Qt.alpha(Theme.hover, 0.5) : "transparent"
                }

                Rectangle {
                    x: 6
                    y: 6
                    width: 16
                    height: 16
                    radius: 8
                    color: "transparent"
                    border.width: 1.5
                    border.color: opt.isSelected ? Theme.accent : Theme.dim

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.accent
                        visible: opt.isSelected
                    }
                }

                Column {
                    x: 32
                    y: 5
                    width: parent.width - x

                    Text {
                        text: opt.modelData.label
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 13
                    }

                    Text {
                        text: opt.modelData.description ?? ""
                        visible: text !== ""
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.forceActiveFocus()
                    onClicked: {
                        if (!opt.isSelected)
                            root.selected(opt.modelData.value);
                    }
                }
            }
        }
    }
}
