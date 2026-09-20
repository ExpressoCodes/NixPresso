pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// The only Hyprland.rawEvent listener and the only caller of refreshToplevels()/refreshMonitors()
// (ADR-0009). lastIpcObject is never updated by events, so every relevant event schedules one
// debounced refresh. Consumers bind to lastIpcObject directly.
Singleton {
    id: root

    // v2 events only: most events arrive as a v1 + v2 pair.
    readonly property var _refreshEvents: ({
        "openwindow": true,
        "closewindow": true,
        "movewindowv2": true,
        "changefloatingmode": true,
        "fullscreen": true,
        "workspacev2": true,
        "focusedmonv2": true,
        "activewindowv2": true
    })
    // Names verified in the 0.56 binary; not yet observed live (no hotplug, WP-4.1).
    readonly property var _monitorEvents: ({
        "monitoraddedv2": true,
        "monitorremovedv2": true
    })

    function requestRefresh(): void {
        refreshTimer.restart();
    }

    function requestMonitorRefresh(): void {
        Hyprland.refreshMonitors();
        requestRefresh();
    }

    // One-shot debounce: one focus dispatch emits a burst of ~5 events.
    Timer {
        id: refreshTimer
        interval: 50
        repeat: false
        onTriggered: Hyprland.refreshToplevels()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            const name = event.name;
            if (root._refreshEvents[name])
                root.requestRefresh();
            else if (root._monitorEvents[name])
                root.requestMonitorRefresh();
        }
    }

    Component.onCompleted: requestRefresh()
}
