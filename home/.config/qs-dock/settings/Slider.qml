import QtQuick
import qs

// Horizontal slider with a right-aligned read-out (UX.md §7.3). It never writes `value` itself:
// it emits `moved` and the caller writes Settings, so the binding on `value` stays intact.
Item {
    id: root

    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property string suffix: ""
    property int decimals: 0
    // Optional read-out formatter: (value) => string.
    property var formatter: null

    signal moved(real value)

    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    implicitWidth: 292
    implicitHeight: 28
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.4

    function setValue(v: real): void {
        let q = Math.round((v - from) / stepSize) * stepSize + from;
        q = Math.max(from, Math.min(to, q));
        q = Number(q.toFixed(4));
        if (q !== value)
            moved(q);
    }

    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Left || k === Qt.Key_Down)
            setValue(value - stepSize);
        else if (k === Qt.Key_Right || k === Qt.Key_Up)
            setValue(value + stepSize);
        else if (k === Qt.Key_PageDown)
            setValue(value - 10 * stepSize);
        else if (k === Qt.Key_PageUp)
            setValue(value + 10 * stepSize);
        else if (k === Qt.Key_Home)
            setValue(from);
        else if (k === Qt.Key_End)
            setValue(to);
        else
            return;
        event.accepted = true;
    }

    Item {
        id: track
        x: 8
        width: root.width - readout.width - 12 - 16
        height: root.height

        FocusRing {
            baseRadius: 6
            shown: root.activeFocus
        }

        Rectangle {
            y: (parent.height - height) / 2
            width: parent.width
            height: 4
            radius: 2
            color: Theme.surface2
        }

        Rectangle {
            y: (parent.height - height) / 2
            width: root.frac * parent.width
            height: 4
            radius: 2
            color: Theme.accent
        }

        Rectangle {
            x: root.frac * parent.width - width / 2
            y: (parent.height - height) / 2
            width: 16
            height: 16
            radius: 8
            color: Theme.fg
        }

        MouseArea {
            anchors.fill: parent
            anchors.leftMargin: -8
            anchors.rightMargin: -8
            preventStealing: true
            cursorShape: Qt.PointingHandCursor

            function apply(mx: real): void {
                root.setValue(root.from + Math.max(0, Math.min(1, (mx - 8) / track.width)) * (root.to - root.from));
            }

            onPressed: mouse => {
                root.forceActiveFocus();
                apply(mouse.x);
            }
            onPositionChanged: mouse => {
                if (pressed)
                    apply(mouse.x);
            }
        }
    }

    Text {
        id: readout
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 56
        horizontalAlignment: Text.AlignRight
        text: root.formatter ? root.formatter(root.value) : root.value.toFixed(root.decimals) + root.suffix
        color: Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 13
        font.features: { "tnum": 1 }
    }
}
