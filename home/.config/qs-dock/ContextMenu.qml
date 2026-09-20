pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// App and background context menus (FR-3, UX.md §6). One per dock, anchored to a point in the dock
// window; closes on outside click through HyprlandFocusGrab, like the bar's Popup.qml.
PopupWindow {
    id: menu

    required property var owner         // the Dock PanelWindow (anchor window)
    required property string edge       // "bottom" | "left" | "right"

    // The AppItem the menu is for; null for the background menu.
    property var item: null
    property bool forItem: false
    property var rows: []
    property int highlighted: -1
    // True from open() until close(); `visible` stays on until the fade-out ends.
    readonly property bool open: _open
    property bool _open: false

    readonly property int maxWindows: 10

    anchor.window: owner
    anchor.edges: edge === "left" ? Edges.Right : edge === "right" ? Edges.Left : Edges.Top
    anchor.gravity: anchor.edges
    anchor.adjustment: edge === "bottom" ? PopupAdjustment.SlideX : PopupAdjustment.SlideY
    color: "transparent"
    visible: false
    implicitWidth: panel.width
    implicitHeight: panel.height

    // (x, y) is the point on the gap line next to the body, in dock window coordinates (UX.md §6.4).
    function openFor(appItem: var, x: real, y: real): void {
        if (visible)
            visible = false;
        item = appItem;
        forItem = appItem !== null;
        sub.visible = false;
        _build();
        highlighted = -1;
        anchor.rect.x = Math.round(x);
        anchor.rect.y = Math.round(y);
        anchor.rect.width = 1;
        anchor.rect.height = 1;
        _open = true;
        visible = true;
        openAnim.restart();
        keys.forceActiveFocus();
    }

    function close(): void {
        if (!_open)
            return;
        _open = false;
        sub.visible = false;
        openAnim.stop();
        closeAnim.restart();
    }

    function _build(): void {
        const out = [];
        const sep = () => {
            if (out.length > 0 && out[out.length - 1].kind !== "sep")
                out.push({ kind: "sep" });
        };
        const it = item;
        if (forItem && it) {
            out.push({ kind: "header" });
            sep();
            const wins = WindowActions.windowsByRecency(it);
            for (const t of wins.slice(0, maxWindows))
                out.push({ kind: "window", t: t, ws: _wsLabel(t) });
            if (wins.length > maxWindows)
                out.push({ kind: "more", n: wins.length - maxWindows });
            sep();
            for (const a of (it.entry?.actions ?? []))
                out.push({ kind: "action", action: a });
            sep();
            out.push({ kind: "new" });
            sep();
            out.push({ kind: "pin" });
            out.push({ kind: "hide" });
            if (it.running) {
                sep();
                out.push({ kind: "quit" });
            }
        } else {
            out.push({ kind: "settings" });
            sep();
            out.push({ kind: "autohide" });
            out.push({ kind: "position" });
        }
        while (out.length > 0 && out[out.length - 1].kind === "sep")
            out.pop();
        rows = out;
    }

    // Workspace badge: name, special workspaces as "S", at most 4 characters.
    function _wsLabel(t: var): string {
        const name = WindowActions.hyprFor(t)?.workspace?.name ?? "";
        return (name.startsWith("special") ? "S" : name).slice(0, 4);
    }

    function enabledRow(r: var): bool {
        switch (r?.kind) {
        case "header":
        case "sep":
        case "more":
        case undefined:
            return false;
        case "new":
            return !!item?.entry;
        case "pin":
            return !!item && (item.pinned || !!item.entry);
        default:
            return true;
        }
    }

    function label(r: var): string {
        switch (r.kind) {
        case "header": return item?.name ?? "";
        case "window": return r.t?.title || (item?.name ?? "");
        case "more": return "+" + r.n + (r.n === 1 ? " more window" : " more windows");
        case "action": return r.action?.name ?? "";
        case "new": return "New Window";
        case "pin": return item?.pinned ? "Remove from Dock" : "Keep in Dock";
        case "hide": return "Hide from Dock";
        case "quit": return "Quit";
        case "settings": return "Dock Settings…";
        case "autohide": return "Autohide";
        case "position": return "Position";
        }
        return "";
    }

    function activate(i: int): void {
        const r = rows[i];
        if (!enabledRow(r))
            return;
        const it = item;
        switch (r.kind) {
        case "window": WindowActions.focus(r.t); break;
        case "action": WindowActions.runAction(it, r.action); break;
        case "new": WindowActions.launch(it); break;
        case "pin":
            if (it.pinned)
                AppModel.unpin(it.key);
            else
                AppModel.pin(it.entryId);
            break;
        case "hide": AppModel.hide(it.key); break;
        case "quit": WindowActions.closeAll(it); break;
        case "settings": UiState.openSettings(); break;
        case "autohide": Settings.toggleAutohide(); break;
        case "position":
            openSub(true);
            return;
        }
        close();
    }

    // Moves the highlight by `step`, skipping disabled rows (UX.md §6.5).
    function moveHighlight(step: int): void {
        const n = rows.length;
        if (n === 0)
            return;
        let i = highlighted;
        for (let k = 0; k < n; k++) {
            i = i < 0 ? (step > 0 ? 0 : n - 1) : (i + step + n) % n;
            if (enabledRow(rows[i])) {
                highlighted = i;
                return;
            }
        }
    }

    function positionRow(): int {
        return rows.findIndex(r => r.kind === "position");
    }

    function openSub(keyboard: bool): void {
        const i = positionRow();
        const row = i >= 0 ? rowRepeater.itemAt(i) : null;
        if (!row)
            return;
        highlighted = i;
        const p = row.mapToItem(null, edge === "right" ? 4 : row.width - 4, 0);
        sub.anchor.rect.x = Math.round(p.x);
        sub.anchor.rect.y = Math.round(p.y - 6);
        sub.anchor.rect.width = 1;
        sub.anchor.rect.height = 1;
        sub.highlighted = keyboard ? Math.max(0, sub.edges.indexOf(Settings.edge)) : -1;
        sub.visible = true;
        subFade.restart();
    }

    // Keyboard navigation (UX.md §6.5). Returns whether the key was used.
    function handleKey(k: int): bool {
        const enter = k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space;
        if (sub.visible) {
            if (k === Qt.Key_Up || k === Qt.Key_Down)
                sub.highlighted = (Math.max(0, sub.highlighted) + (k === Qt.Key_Down ? 1 : 2)) % 3;
            else if (enter)
                chooseEdge(sub.edges[Math.max(0, sub.highlighted)]);
            else if (k === Qt.Key_Left || k === Qt.Key_Escape)
                closeSub();
            else
                return false;
        } else if (k === Qt.Key_Up || k === Qt.Key_Down) {
            moveHighlight(k === Qt.Key_Down ? 1 : -1);
        } else if (enter) {
            activate(highlighted);
        } else if (k === Qt.Key_Right && highlighted >= 0 && highlighted === positionRow()) {
            openSub(true);
        } else if (k === Qt.Key_Escape) {
            close();
        } else {
            return false;
        }
        return true;
    }

    function closeSub(): void {
        sub.visible = false;
    }

    function chooseEdge(e: string): void {
        Settings.edge = e;
        close();
    }

    // Close when the item leaves this dock (app quit, hidden, unpinned while not running).
    // (Not reading _open here: close() writes it.)
    readonly property bool _itemGone: forItem && (!item || !AppModel.items.includes(item))
    on_ItemGoneChanged: if (_itemGone) close()
    onEdgeChanged: close()

    Connections {
        target: menu.forItem ? menu.item : null
        function onWindowsChanged() {
            if (menu._open)
                menu._build();
        }
    }

    HyprlandFocusGrab {
        windows: sub.visible ? [menu, sub] : [menu]
        active: menu._open
        onCleared: menu.close()
    }

    Timer {
        id: hoverOpen
        interval: 150
        onTriggered: if (menu._open && menu.highlighted === menu.positionRow()) menu.openSub(false)
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: panel; property: "opacity"; from: 0; to: 1; duration: Theme.dur(120); easing.type: Easing.OutCubic }
        NumberAnimation { target: panel; property: "scale"; from: 0.96; to: 1; duration: Theme.dur(120); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: panel; property: "opacity"; to: 0; duration: Theme.dur(80); easing.type: Easing.InCubic }
        ScriptAction { script: if (!menu._open) menu.visible = false }
    }

    Rectangle {
        id: panel
        readonly property int contentWidth: Math.max(220, Math.min(320, column.implicitWidth + 12))

        width: contentWidth
        height: column.implicitHeight + 12
        color: Theme.popupBg
        border.width: 1
        border.color: Theme.hover
        radius: 10
        transformOrigin: menu.edge === "left" ? Item.Left : menu.edge === "right" ? Item.Right : Item.Bottom

        Item {
            id: keys
            focus: true
            Keys.onPressed: event => event.accepted = menu.handleKey(event.key)
        }

        Column {
            id: column
            x: 6
            y: 6
            width: panel.width - 12

            Repeater {
                id: rowRepeater
                model: menu.rows

                // One row: header, divider, or an activatable entry with optional leading dot/icon and trailing
                // badge, switch or arrow (UX.md §6.1–6.3).
                Item {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property string kind: modelData.kind
                    readonly property bool enabled_: menu.enabledRow(modelData)
                    readonly property bool lit: enabled_ && menu.highlighted === index
                    readonly property bool secondary: kind === "more" || (kind === "window" && !(modelData.t?.title))
                    readonly property int trailing: kind === "window" && modelData.ws !== "" ? badge.width + 8
                                                  : kind === "autohide" ? 32 + 8
                                                  : kind === "position" ? 16 : 0

                    width: column.width
                    height: kind === "sep" ? 9 : kind === "header" ? 32 : 28
                    implicitWidth: kind === "sep" ? 0 : 10 + 24 + text.implicitWidth + trailing + 10

                    Rectangle {
                        visible: row.kind === "sep"
                        y: 4
                        width: parent.width
                        height: 1
                        color: Theme.hover
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: row.lit
                        radius: 6
                        color: Theme.hover
                    }

                    // Leading column: header icon, focused-window dot.
                    Image {
                        visible: row.kind === "header"
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        sourceSize: Qt.size(32, 32)
                        source: row.kind === "header" ? (menu.item?.icon ?? "") : ""
                        smooth: true
                    }

                    Rectangle {
                        visible: row.kind === "window" && row.modelData.t === ToplevelManager.activeToplevel
                        x: 10 + 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: Theme.accent
                    }

                    Text {
                        id: text
                        visible: row.kind !== "sep"
                        x: 10 + 24
                        width: row.width - x - 10 - row.trailing
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.kind === "sep" ? "" : menu.label(row.modelData)
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.bold: row.kind === "header"
                        color: row.kind === "quit" ? Theme.red
                             : row.kind === "header" ? Theme.fg
                             : row.secondary ? Theme.subtext0
                             : !row.enabled_ ? Theme.dim
                             : Theme.fg
                    }

                    // Workspace badge.
                    Rectangle {
                        id: badge
                        visible: row.kind === "window" && row.modelData.ws !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 18
                        width: Math.max(18, badgeText.implicitWidth + 12)
                        radius: 9
                        color: row.lit ? Theme.surface1 : Theme.hover

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: row.kind === "window" ? row.modelData.ws : ""
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.subtext1
                        }
                    }

                    // Autohide switch (D-13): on for the hidden modes.
                    Rectangle {
                        readonly property bool on: Settings.hiddenMode
                        visible: row.kind === "autohide"
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 18
                        radius: 9
                        color: on ? Theme.accent : Theme.surface1
                        border.width: on ? 0 : 1
                        border.color: Theme.dim

                        Rectangle {
                            x: parent.on ? parent.width - width - 3 : 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: parent.on ? Theme.crust : Theme.overlay2
                        }
                    }

                    Text {
                        visible: row.kind === "position"
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: menu.edge === "right" ? "◂" : "▸"
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.subtext0
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: row.kind !== "sep"
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onEntered: {
                            if (!row.enabled_)
                                return;
                            menu.highlighted = row.index;
                            if (row.kind === "position") {
                                hoverOpen.restart();
                            } else {
                                hoverOpen.stop();
                                menu.closeSub();
                            }
                        }
                        onClicked: menu.activate(row.index)
                    }
                }
            }
        }
    }

    // Position ▸ submenu (UX.md §6.3), a popup of the menu so both share the focus grab.
    PopupWindow {
        id: sub

        readonly property var edges: ["bottom", "left", "right"]
        property int highlighted: -1

        anchor.window: menu
        anchor.edges: menu.edge === "right" ? Edges.Left | Edges.Top : Edges.Right | Edges.Top
        anchor.gravity: menu.edge === "right" ? Edges.Left | Edges.Bottom : Edges.Right | Edges.Bottom
        anchor.adjustment: PopupAdjustment.SlideY | PopupAdjustment.FlipX
        color: "transparent"
        visible: false
        implicitWidth: subPanel.width
        implicitHeight: subPanel.height

        NumberAnimation {
            id: subFade
            target: subPanel
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.dur(100)
            easing.type: Easing.OutCubic
        }

        Rectangle {
            id: subPanel
            width: 140
            height: subColumn.implicitHeight + 12
            color: Theme.popupBg
            border.width: 1
            border.color: Theme.hover
            radius: 10

            Column {
                id: subColumn
                x: 6
                y: 6
                width: subPanel.width - 12

                Repeater {
                    model: sub.edges

                    Item {
                        id: subRow
                        required property string modelData
                        required property int index

                        width: subColumn.width
                        height: 28

                        Rectangle {
                            anchors.fill: parent
                            visible: sub.highlighted === subRow.index
                            radius: 6
                            color: Theme.hover
                        }

                        Rectangle {
                            visible: Settings.edge === subRow.modelData
                            x: 10 + 5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.accent
                        }

                        Text {
                            x: 10 + 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: subRow.modelData.charAt(0).toUpperCase() + subRow.modelData.slice(1)
                            font.family: Theme.font
                            font.pixelSize: 13
                            color: Theme.fg
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: sub.highlighted = subRow.index
                            onClicked: menu.chooseEdge(subRow.modelData)
                        }
                    }
                }
            }
        }
    }
}
