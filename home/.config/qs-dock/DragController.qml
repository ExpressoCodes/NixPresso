pragma ComponentBehavior: Bound
import QtQuick

// Reorder / pin / unpin by drag (FR-4, UX.md §5.5). Holds the drag state and draws the ghost.
// The dock lays its items out from `target` and `removing` while `active`; the model changes
// once, on drop. Pointer positions are dock-window coordinates.
Item {
    id: ctl

    required property var owner

    readonly property bool active: _active
    readonly property bool settling: _settling
    // The real delegate of the dragged app stays hidden while the ghost stands in for it.
    readonly property string hideKey: _active || _settling ? key : ""

    property var item: null
    property string key: ""
    property bool fromPinned: false
    property int fromIndex: -1
    // Pinned-section index where the gap is, or -1 for no gap in the pinned section.
    property int target: -1
    // A pinned icon is in the remove zone (≥ one icon size outward from the body).
    property bool removing: false

    property bool _active: false
    property bool _settling: false
    property bool _cancel: false
    // Frozen at drag start so a re-centring body can't feed back into the target maths.
    property real _frame: 0
    property real _boundary: 0
    property real _grabX: 0
    property real _grabY: 0

    function _clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    // `delegate` is the DockItem under the press, (wx, wy) the pointer.
    function begin(delegate: var, wx: real, wy: real): bool {
        if (_active || !delegate?.modelData)
            return false;
        settleAnim.stop();
        poofAnim.stop();
        _settling = false;
        owner.closeMenu();
        item = delegate.modelData;
        key = item.key;
        fromPinned = delegate.pinnedSection;
        fromIndex = delegate.index;
        target = fromPinned ? fromIndex : -1;
        removing = false;
        _frame = owner.rowMain;
        _boundary = owner.pinnedBoundary();
        const tl = delegate.mapToItem(null, delegate.iconX, delegate.iconY);
        _grabX = wx - tl.x;
        _grabY = wy - tl.y;
        ghost.source = item.icon;
        ghost.scale = 1;
        ghost.opacity = 0.9;
        _active = true;
        move(wx, wy);
        return true;
    }

    function move(wx: real, wy: real): void {
        if (!_active)
            return;
        // The ghost stays inside the surface; the pointer keeps its implicit grab beyond it.
        ghost.x = _clamp(wx - _grabX, 0, width - ghost.width);
        ghost.y = _clamp(wy - _grabY, 0, height - ghost.height);

        const s = owner.s;
        const unit = s + owner.sp;
        const u = owner.mainOf(wx, wy) - _frame;
        const out = owner.outwardOf(wx, wy) >= s;
        const inPinned = u < _boundary;
        const raw = Math.floor((u - owner.p + unit / 2) / unit);
        removing = fromPinned && out;
        if (fromPinned)
            target = out ? -1 : inPinned ? _clamp(raw, 0, owner.pinnedCount - 1) : fromIndex;
        else
            target = !out && inPinned && item.entryId !== "" ? _clamp(raw, 0, owner.pinnedCount) : -1;
        _cancel = fromPinned ? !out && !inPinned : target < 0;
        ghost.opacity = removing ? 0.5 : 0.9;
    }

    function drop(): void {
        if (!_active)
            return;
        const it = item;
        let poof = false;
        if (fromPinned && removing) {
            poof = AppModel.unpin(key);
        } else if (fromPinned && target >= 0 && target !== fromIndex) {
            const pins = Settings.pins;
            const rest = pins.filter(k => k !== key);
            const others = owner.pinnedItems.filter(i => i !== it);
            const to = target < others.length ? rest.indexOf(others[target].key) : rest.length;
            AppModel.movePin(pins.indexOf(key), to);
        } else if (!fromPinned && target >= 0) {
            const pinned = owner.pinnedItems;
            AppModel.pin(it.entryId, target < pinned.length ? Settings.pins.indexOf(pinned[target].key) : -1);
        }
        _active = false;
        _settling = true;
        if (poof) {
            poofAnim.start();
            return;
        }
        const dest = owner.restingIconPos(key);
        if (!dest) {
            poofAnim.start();
            return;
        }
        settleX.to = dest.x;
        settleY.to = dest.y;
        settleX.duration = settleY.duration = Theme.dur(_cancel ? 220 : 180);
        settleAnim.start();
    }

    // Esc, or an interrupted press: the ghost returns to its slot.
    function cancel(): void {
        if (!_active)
            return;
        _cancel = true;
        target = fromPinned ? fromIndex : -1;
        removing = false;
        drop();
    }

    Image {
        id: ghost
        visible: ctl._active || ctl._settling
        width: ctl.owner.s
        height: ctl.owner.s
        sourceSize: Qt.size(ctl.owner.magSize, ctl.owner.magSize)
        smooth: true
        mipmap: true
    }

    ParallelAnimation {
        id: settleAnim
        NumberAnimation { id: settleX; target: ghost; property: "x"; easing.type: Easing.OutCubic }
        NumberAnimation { id: settleY; target: ghost; property: "y"; easing.type: Easing.OutCubic }
        onFinished: ctl._settling = false
    }

    // Unpin poof: scale and fade only, no particles (D-16).
    ParallelAnimation {
        id: poofAnim
        NumberAnimation { target: ghost; property: "scale"; to: 1.4; duration: Theme.dur(300); easing.type: Easing.OutQuad }
        NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: Theme.dur(300); easing.type: Easing.OutQuad }
        onFinished: ctl._settling = false
    }
}
