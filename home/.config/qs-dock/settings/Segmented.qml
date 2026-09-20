pragma ComponentBehavior: Bound
import QtQuick
import qs

// Segmented control (UX.md §7.3). `options` is [{ value, label }]. One tab stop; Left/Right
// move the selection and apply at once.
Item {
    id: root

    property var options: []
    property var current
    signal selected(var value)

    readonly property int index: options.findIndex(o => o.value === current)
    readonly property int segmentWidth: {
        let w = 64;
        for (const o of options)
            w = Math.max(w, Math.ceil(metrics.advanceWidth(o.label)) + 24);
        return w;
    }

    implicitWidth: segmentWidth * options.length
    implicitHeight: 28
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
        if (event.key === Qt.Key_Left)
            step(-1);
        else if (event.key === Qt.Key_Right)
            step(1);
        else
            return;
        event.accepted = true;
    }

    FontMetrics {
        id: metrics
        font.family: Theme.font
        font.pixelSize: 13
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Theme.popupBg
        border.width: 1
        border.color: Theme.surface1

        FocusRing {
            baseRadius: 6
            shown: root.activeFocus
        }
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: root.options

            Item {
                id: seg
                required property var modelData
                required property int index
                readonly property bool isSelected: seg.index === root.index

                width: root.segmentWidth
                height: root.height

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 5
                    color: seg.isSelected ? Theme.accent : segArea.containsMouse ? Qt.alpha(Theme.hover, 0.8) : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: seg.modelData.label
                    color: seg.isSelected ? Theme.crust : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                }

                MouseArea {
                    id: segArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.forceActiveFocus()
                    onClicked: {
                        if (!seg.isSelected)
                            root.selected(seg.modelData.value);
                    }
                }
            }
        }
    }
}
