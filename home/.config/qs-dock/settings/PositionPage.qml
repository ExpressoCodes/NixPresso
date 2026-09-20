import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs

// Position group (FR-6, UX.md §7.2). "Monitors" is all / focused / a connector name.
Column {
    id: root

    readonly property string monitorMode: Settings.monitors === "all" || Settings.monitors === "focused" ? Settings.monitors : "specific"
    // Connected screens, plus the stored name when that monitor is unplugged (so it stays visible).
    readonly property var monitorChips: {
        const names = Quickshell.screens.map(s => s.name);
        const out = names.map(n => ({ value: n, label: n }));
        if (monitorMode === "specific" && !names.includes(Settings.monitors))
            out.push({ value: Settings.monitors, label: Settings.monitors + " (disconnected)" });
        return out;
    }

    width: parent ? parent.width : 492

    GroupTitle {
        text: "Position"
    }

    SettingRow {
        label: "Edge"
        Segmented {
            options: [
                { value: "bottom", label: "Bottom" },
                { value: "left", label: "Left" },
                { value: "right", label: "Right" }
            ]
            current: Settings.edge
            onSelected: v => Settings.edge = v
        }
    }

    SettingRow {
        label: "Margin from edge"
        Slider {
            from: Settings.ranges.margin[0]
            to: Settings.ranges.margin[1]
            value: Settings.margin
            suffix: " px"
            onMoved: v => Settings.margin = v
        }
    }

    SettingRow {
        label: "Monitors"
        Column {
            spacing: 8

            Segmented {
                options: [
                    { value: "all", label: "All" },
                    { value: "focused", label: "Focused" },
                    { value: "specific", label: "Specific" }
                ]
                current: root.monitorMode
                onSelected: v => {
                    if (v !== "specific")
                        Settings.monitors = v;
                    else
                        Settings.monitors = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "all";
                }
            }

            Chips {
                enabled: root.monitorMode === "specific"
                options: root.monitorChips
                current: Settings.monitors
                onSelected: v => Settings.monitors = v
            }
        }
    }

    SettingRow {
        label: "Only show apps on this monitor"
        help: "Running apps with a window on the dock's monitor"
        divider: false
        Toggle {
            checked: Settings.onlyCurrentMonitorApps
            onToggled: on => Settings.onlyCurrentMonitorApps = on
        }
    }
}
