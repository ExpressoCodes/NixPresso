pragma ComponentBehavior: Bound
import QtQuick

// One app slot: icon, indicator and click handling. Dock positions it absolutely along the
// main axis; its box is the base slot (s along the edge, T away from it), so the dot sits in
// the screen-side padding (UX.md §2.3).
Item {
    id: root

    required property var modelData   // AppItem
    required property int index

    required property int main        // slot start along the edge, relative to the body
    required property string edge     // "bottom" | "left" | "right"
    required property int iconSize    // s
    required property int pad         // p
    required property int magSize     // M: the icon is rendered once at M and scaled down (UX.md §3.2)
    required property int edgeGap     // m: the hit area reaches the screen edge
    property real hitBefore: 0        // half the gap to the previous slot, so there are no dead zones
    property real hitAfter: 0
    property bool pinnedSection: false
    required property var dragger     // DragController
    property bool suspended: false    // a menu is open or a drag runs: no hover feedback
    property bool animate: false      // slot moves animate (drag preview and settle)

    signal menuRequested()

    readonly property bool vertical: edge !== "bottom"
    readonly property int thick: iconSize + 2 * pad
    readonly property int dotSize: Math.max(3, Math.round(iconSize / 12))
    // Top-left of the base icon square inside the slot.
    readonly property int iconX: vertical ? pad : 0
    readonly property int iconY: vertical ? 0 : pad
    readonly property string style: Settings.indicatorStyle
    readonly property bool running: modelData.running
    readonly property bool active: modelData.active
    readonly property bool urgent: modelData.urgent ?? false

    x: vertical ? 0 : main
    y: vertical ? main : 0
    width: vertical ? thick : iconSize
    height: vertical ? iconSize : thick
    // The drag ghost stands in for this icon while it is dragged or settling.
    opacity: dragger.hideKey !== "" && dragger.hideKey === modelData.key ? 0 : 1

    Behavior on x {
        enabled: root.animate && !root.vertical
        NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
    }
    Behavior on y {
        enabled: root.animate && root.vertical
        NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
    }

    // Hover feedback, only when magnification is off (dock.hoverTile).
    Rectangle {
        readonly property int side: root.iconSize + 2 * Math.round(root.iconSize / 12)
        visible: root.magSize <= root.iconSize
        x: root.iconX + (root.iconSize - side) / 2
        y: root.iconY + (root.iconSize - side) / 2
        width: side
        height: side
        radius: Math.round(root.iconSize * 0.22)
        color: Qt.alpha(Theme.hover, 0.6)
        opacity: area.containsMouse && !root.suspended ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.dur(100); easing.type: Easing.OutQuad }
        }
    }

    // Rendered at M and scaled down; the transform origin sits on the screen side so it grows
    // outward once magnification lands (M5).
    Image {
        id: icon
        x: root.edge === "right" ? root.pad + root.iconSize - root.magSize
         : root.edge === "left" ? root.pad
         : (root.iconSize - root.magSize) / 2
        y: root.vertical ? (root.iconSize - root.magSize) / 2 : root.pad + root.iconSize - root.magSize
        width: root.magSize
        height: root.magSize
        sourceSize: Qt.size(root.magSize, root.magSize)
        source: root.modelData.icon
        smooth: true
        mipmap: true
        scale: root.iconSize / root.magSize
        transformOrigin: root.edge === "left" ? Item.Left : root.edge === "right" ? Item.Right : Item.Bottom
        opacity: area.pressedLeft ? 0.7 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: area.pressedLeft ? Theme.dur(60) : Theme.dur(120)
                easing.type: Easing.OutQuad
            }
        }
    }

    // Indicator (UX.md §4): one dot, a pill when active, or one dot per window (max 3).
    // It runs along the edge, centred on the slot, round(p/2) from the screen side.
    Grid {
        id: dots
        readonly property int count: root.style === "dot-per-window" ? Math.min(root.modelData.windowCount, 3)
                                   : root.style === "dot" ? 1 : 0
        readonly property int offset: Math.round(root.pad / 2) - Math.floor(root.dotSize / 2)

        // Exactly `count` columns: with a fixed 3, Grid adds spacing for the empty columns and a
        // single dot or pill ends up off-centre.
        columns: root.vertical ? 1 : Math.max(1, count)
        spacing: root.dotSize
        x: root.edge === "left" ? offset
         : root.edge === "right" ? root.width - offset - root.dotSize
         : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.height - offset - root.dotSize
        opacity: root.running ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.dur(150); easing.type: Easing.OutCubic }
        }

        Repeater {
            model: dots.count

            Rectangle {
                required property int index
                readonly property bool pill: root.active && (root.style === "dot" || index === 0)
                readonly property int len: !pill ? root.dotSize : root.style === "dot" ? 3 * root.dotSize : 2 * root.dotSize

                width: root.vertical ? root.dotSize : len
                height: root.vertical ? len : root.dotSize
                radius: root.dotSize / 2
                color: root.urgent ? Theme.peach : root.active ? Theme.accent : Theme.subtext0

                Behavior on width {
                    enabled: !root.vertical
                    NumberAnimation { duration: Theme.dur(150); easing.type: Easing.OutCubic }
                }
                Behavior on height {
                    enabled: root.vertical
                    NumberAnimation { duration: Theme.dur(150); easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: Theme.dur(150); easing.type: Easing.OutQuad }
                }
            }
        }
    }

    // Hit area: the whole slot plus half of each gap, extended to the screen edge. A left press
    // that moves 8 px starts a drag (UX.md §5.5); a right press on the icon opens its menu, and
    // anywhere else in the slot falls through to the dock's background menu.
    MouseArea {
        id: area

        readonly property bool pressedLeft: pressed && (pressedButtons & Qt.LeftButton) !== 0 && !dragging
        property bool dragging: false
        property bool dragged: false
        property point pressPos

        x: root.vertical ? (root.edge === "left" ? -root.edgeGap : 0) : -root.hitBefore
        y: root.vertical ? -root.hitBefore : 0
        width: root.vertical ? root.thick + root.edgeGap : root.hitBefore + root.iconSize + root.hitAfter
        height: root.vertical ? root.hitBefore + root.iconSize + root.hitAfter : root.thick + root.edgeGap
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true

        function onIcon(mx: real, my: real): bool {
            const p = mapToItem(root, mx, my);
            return p.x >= root.iconX && p.x < root.iconX + root.iconSize
                && p.y >= root.iconY && p.y < root.iconY + root.iconSize;
        }

        onPressed: mouse => {
            dragged = false;
            if (mouse.button === Qt.RightButton) {
                if (!onIcon(mouse.x, mouse.y)) {
                    mouse.accepted = false;
                    return;
                }
                root.menuRequested();
                return;
            }
            pressPos = Qt.point(mouse.x, mouse.y);
        }

        onPositionChanged: mouse => {
            if (!(pressedButtons & Qt.LeftButton))
                return;
            const w = mapToItem(null, mouse.x, mouse.y);
            if (!dragging) {
                if (Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) < 8)
                    return;
                const start = mapToItem(null, pressPos.x, pressPos.y);
                dragging = root.dragger.begin(root, start.x, start.y);
                dragged = dragging;
            }
            if (dragging)
                root.dragger.move(w.x, w.y);
        }

        onReleased: {
            if (dragging) {
                dragging = false;
                root.dragger.drop();
            }
        }

        onCanceled: {
            if (dragging) {
                dragging = false;
                root.dragger.cancel();
            }
        }

        onClicked: mouse => {
            if (dragged)
                return;
            if (mouse.button === Qt.MiddleButton)
                WindowActions.launch(root.modelData);
            else if (mouse.button === Qt.LeftButton)
                WindowActions.activate(root.modelData);
        }
    }
}
