pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// One dock per screen (ADR-0005/0006). The surface spans the full screen length along its edge
// and is thicker than the body to leave room for magnification; the mask keeps the rest click-through.
// Geometry is computed along a main axis (along the edge) and a cross axis (away from it),
// then mapped to x/y for the configured edge (UX.md §2.3).
PanelWindow {
    id: dock

    required property var modelData
    screen: modelData

    // App lists for this screen. The attached `t.HyprlandToplevel` has no monitor, so the
    // per-monitor filter joins through Hyprland.toplevels (only evaluated when the option is on).
    readonly property var pinnedItems: AppModel.pinnedItems
    readonly property var runningItems: {
        if (!Settings.onlyCurrentMonitorApps)
            return AppModel.runningItems;
        const here = Hyprland.toplevels.values.filter(h => h.monitor?.name === dock.modelData.name).map(h => h.wayland);
        return AppModel.runningItems.filter(i => i.windows.some(t => here.includes(t)));
    }
    readonly property int pinnedCount: pinnedItems.length
    readonly property int runningCount: runningItems.length
    readonly property int count: pinnedCount + runningCount
    readonly property bool sepOn: Settings.showSeparator && pinnedCount > 0 && runningCount > 0

    readonly property string edge: Settings.edge
    readonly property bool vertical: edge !== "bottom"

    // Main-axis lengths. A side-edge surface in reserve mode is shortened by other surfaces'
    // zones (the bar's top zone), so the body is centred on the screen, not the surface
    // (ADR-0006). The zones are assumed to sit at the top, which holds for this setup.
    readonly property int screenLength: vertical ? modelData.height : modelData.width
    readonly property int surfaceLength: {
        const l = vertical ? dock.height : dock.width;
        return l > 0 ? l : screenLength;
    }
    readonly property int surfaceOffset: vertical ? Math.max(0, screenLength - surfaceLength) : 0

    // Geometry (UX.md §2). `s` is the icon size after the fit rule (§2.2).
    readonly property int sp: Settings.spacing
    readonly property int m: Settings.margin
    readonly property int s: fitSize(Settings.iconSize)
    readonly property int p: padFor(s)
    readonly property int thick: s + 2 * p                  // T
    readonly property int st: Math.max(1, Math.round(s / 48))
    readonly property int sg: Math.max(sp, Math.round(s / 6))
    readonly property int sepSlot: 2 * sg + st
    // Layout counts: the real ones, or the drag preview (UX.md §5.5), where the dragged icon's gap
    // moves to `drag.target` or closes in the remove zone. Only change when the target does.
    readonly property int layPinned: !drag.active ? pinnedCount
        : pinnedCount - (drag.fromPinned ? 1 : 0) + (drag.target >= 0 ? 1 : 0)
    readonly property int layRunning: !drag.active ? runningCount
        : runningCount - (!drag.fromPinned && drag.target >= 0 ? 1 : 0)
    readonly property bool laySep: Settings.showSeparator && layPinned > 0 && layRunning > 0
    readonly property int sepExtra: laySep ? sepSlot - sp : 0
    readonly property int layCount: layPinned + layRunning
    readonly property int bodyLength: Math.max(thick, 2 * p + layCount * s + Math.max(0, layCount - 1) * sp + sepExtra)
    readonly property int magSize: Settings.magnification && Settings.maxMagnifiedSize > s ? Settings.maxMagnifiedSize : s
    readonly property int bounceH: Math.round(s / 2)
    readonly property int surfaceThickness: m + 2 * p + magSize + bounceH
    readonly property int radius: Math.min(Settings.cornerRadius, Math.floor(thick / 2))
    readonly property real opacityBg: Settings.backgroundOpacity / 100

    // Body start along the main axis, in surface coordinates, kept inside the surface.
    readonly property int bodyMain: Math.max(0, Math.min(surfaceLength - bodyLength,
                                    Math.round((screenLength - bodyLength) / 2) - surfaceOffset))

    // Resting body position (the body itself may be mid-animation during a drag).
    readonly property int bodyX: edge === "bottom" ? bodyMain : edge === "left" ? m : width - m - thick
    readonly property int bodyY: vertical ? bodyMain : height - m - thick

    function padFor(size: int): int {
        return Math.max(4, Math.round(size / 6));
    }

    // Shrinks the icons if the row would not fit along the edge (8 px clearance each end).
    function fitSize(req: int): int {
        const n = count;
        if (n === 0)
            return req;
        const rp = padFor(req);
        const extra = sepOn ? 2 * Math.max(sp, Math.round(req / 6)) + Math.max(1, Math.round(req / 48)) - sp : 0;
        const avail = surfaceLength - 2 * m - 16;
        const fixed = 2 * rp + (n - 1) * sp + extra;
        if (fixed + n * req <= avail)
            return req;
        return Math.min(req, Math.max(24, Math.floor((avail - fixed) / n)));
    }

    // Base layout: start of slot i along the main axis, relative to the body.
    function slotStart(i: int): int {
        return p + i * (s + sp) + (laySep && i >= layPinned ? sepExtra : 0);
    }

    // Layout slot of pinned item i / running item j, shifted around the drag gap.
    function pinnedSlot(i: int): int {
        if (!drag.active)
            return i;
        let v = i;
        if (drag.fromPinned) {
            if (i === drag.fromIndex)
                return drag.target >= 0 ? drag.target : i;
            if (i > drag.fromIndex)
                v--;
        }
        return drag.target >= 0 && v >= drag.target ? v + 1 : v;
    }

    function runningSlot(j: int): int {
        const moved = drag.active && !drag.fromPinned && drag.target >= 0;
        return layPinned + (moved && j > drag.fromIndex ? j - 1 : j);
    }

    function gapBefore(i: int): real {
        if (i === 0)
            return p;
        return (sepOn && i === pinnedCount ? sepSlot : sp) / 2;
    }

    function gapAfter(i: int): real {
        if (i === count - 1)
            return p;
        return (sepOn && i === pinnedCount - 1 ? sepSlot : sp) / 2;
    }

    // Main-axis / outward window coordinates for the drag maths.
    readonly property real rowMain: vertical ? row.y : row.x

    function mainOf(wx: real, wy: real): real {
        return vertical ? wy : wx;
    }

    // Distance from the body's inner edge (the one facing the screen content), outward.
    function outwardOf(wx: real, wy: real): real {
        return edge === "bottom" ? bodyY - wy : edge === "left" ? wx - bodyX - thick : bodyX - wx;
    }

    // Midpoint of the gap between the pinned and running sections, relative to the body.
    function pinnedBoundary(): real {
        return runningCount > 0 ? slotStart(pinnedCount) - gapBefore(pinnedCount) : Infinity;
    }

    // Window position of an app's icon in its current slot, or null if it isn't in this dock.
    function restingIconPos(key: string): var {
        let i = pinnedItems.findIndex(o => o.key === key);
        if (i < 0) {
            const j = runningItems.findIndex(o => o.key === key);
            if (j < 0)
                return null;
            i = pinnedCount + j;
        }
        const main = slotStart(i);
        return vertical ? Qt.point(bodyX + p, bodyY + main) : Qt.point(bodyX + main, bodyY + p);
    }

    // Delegate for item i (pinned first, then running).
    function delegateAt(i: int): var {
        return i < pinnedCount ? pinnedRepeater.itemAt(i) : runningRepeater.itemAt(i - pinnedCount);
    }

    // Context menus anchor to the collapsed layout, 8 px off the inner edge (UX.md §6.4).
    function openItemMenu(delegate: var): void {
        if (drag.active || !delegate)
            return;
        const c = delegate.main + s / 2;
        openMenuAt(delegate.modelData, vertical ? 0 : bodyX + c, vertical ? bodyY + c : 0);
    }

    function openBackgroundMenu(wx: real, wy: real): void {
        if (!drag.active)
            openMenuAt(null, wx, wy);
    }

    function openMenuAt(appItem: var, wx: real, wy: real): void {
        if (edge === "bottom")
            menu.openFor(appItem, wx, bodyY - 8);
        else if (edge === "left")
            menu.openFor(appItem, bodyX + thick + 8, wy);
        else
            menu.openFor(appItem, bodyX - 8, wy);
    }

    function closeMenu(): void {
        menu.close();
    }

    // Hover effects pause while a menu is open or an icon is dragged (UX.md §3.4).
    readonly property bool hoverSuspended: menu.open || drag.active || drag.settling
    // Keeps a hidden-mode dock revealed (ScreenVisibility.holdOpen, M4).
    readonly property bool holdOpen: menu.open || drag.active

    // Nothing is shown (and no zone reserved) until the app list is resolved.
    visible: AppModel.ready
    color: "transparent"

    anchors {
        bottom: true
        top: dock.vertical
        left: dock.edge !== "right"
        right: dock.edge !== "left"
    }
    implicitWidth: vertical ? surfaceThickness : modelData.width
    implicitHeight: vertical ? modelData.height : surfaceThickness

    // Reserve vs. overlap (D-2). ScreenVisibility takes this over in WP-4.1; until then the
    // hidden modes behave like overlap.
    exclusionMode: Settings.visibilityMode === "reserve" ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: thick + m
    WlrLayershell.namespace: "qs-dock"

    // While dragging, the whole surface takes input so the ghost (clamped inside it) never
    // leaves the mask; it shrinks back on release (ADR-0006).
    mask: drag.active ? dragRegion : envelopeRegion

    readonly property Region envelopeRegion: Region {
        item: envelope
    }
    readonly property Region dragRegion: Region {
        item: drag
    }

    // Hover/input envelope: the body extended to the screen edge (UX.md §3.5, at rest).
    Item {
        id: envelope
        x: dock.edge === "left" ? 0 : body.x
        y: body.y
        width: dock.vertical ? dock.thick + dock.m : dock.bodyLength
        height: dock.vertical ? dock.bodyLength : dock.thick + dock.m

        // Right click on empty dock space (items pass right presses outside their icon down here).
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onPressed: mouse => {
                const w = mapToItem(null, mouse.x, mouse.y);
                dock.openBackgroundMenu(w.x, w.y);
            }
        }
    }

    // Neighbours shift and the body resizes with an animation only during a drag and its settle.
    readonly property bool animateLayout: drag.active || drag.settling

    Rectangle {
        id: body
        x: dock.bodyX
        y: dock.bodyY
        width: dock.vertical ? dock.thick : dock.bodyLength
        height: dock.vertical ? dock.bodyLength : dock.thick
        radius: dock.radius
        color: Qt.alpha(Theme.bg, dock.opacityBg)
        border.width: 1
        border.color: Qt.alpha(Theme.hover, dock.opacityBg >= 0.5 ? 1 : dock.opacityBg * 2)

        Behavior on x {
            enabled: dock.animateLayout && !dock.vertical
            NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: dock.animateLayout && dock.vertical
            NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: dock.animateLayout && !dock.vertical
            NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: dock.animateLayout && dock.vertical
            NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
        }
    }

    // Base-layout origin for the icons. Kept separate from `body` so the body can widen
    // around the pointer later without moving this coordinate space.
    Item {
        id: row
        x: body.x
        y: body.y
        width: body.width
        height: body.height

        Repeater {
            id: pinnedRepeater
            model: ScriptModel {
                values: dock.pinnedItems
            }

            DockItem {
                id: pinnedDelegate
                main: dock.slotStart(dock.pinnedSlot(index))
                pinnedSection: true
                edge: dock.edge
                iconSize: dock.s
                pad: dock.p
                magSize: dock.magSize
                edgeGap: dock.m
                hitBefore: dock.gapBefore(index)
                hitAfter: dock.gapAfter(index)
                dragger: drag
                suspended: dock.hoverSuspended
                animate: dock.animateLayout
                onMenuRequested: dock.openItemMenu(pinnedDelegate)
            }
        }

        DockSeparator {
            readonly property int mainPos: dock.slotStart(dock.layPinned - 1) + dock.s + dock.sg
            readonly property real crossPos: dock.p + (dock.s - length) / 2

            visible: dock.laySep
            thickness: dock.st
            length: Math.round(0.7 * dock.s)
            x: dock.vertical ? crossPos : mainPos
            y: dock.vertical ? mainPos : crossPos
            width: dock.vertical ? length : thickness
            height: dock.vertical ? thickness : length

            Behavior on x {
                enabled: dock.animateLayout && !dock.vertical
                NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: dock.animateLayout && dock.vertical
                NumberAnimation { duration: Theme.dur(200); easing.type: Easing.OutCubic }
            }
        }

        Repeater {
            id: runningRepeater
            model: ScriptModel {
                values: dock.runningItems
            }

            DockItem {
                id: runningDelegate
                main: dock.slotStart(dock.runningSlot(index))
                edge: dock.edge
                iconSize: dock.s
                pad: dock.p
                magSize: dock.magSize
                edgeGap: dock.m
                hitBefore: dock.gapBefore(dock.pinnedCount + index)
                hitAfter: dock.gapAfter(dock.pinnedCount + index)
                dragger: drag
                suspended: dock.hoverSuspended
                animate: dock.animateLayout
                onMenuRequested: dock.openItemMenu(runningDelegate)
            }
        }
    }

    DragController {
        id: drag
        owner: dock
        anchors.fill: parent
    }

    ContextMenu {
        id: menu
        owner: dock
        edge: dock.edge
    }
}
