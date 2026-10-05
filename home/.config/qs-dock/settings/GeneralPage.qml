import QtQuick
import qs

// General group (FR-6, UX.md §7.2). Top-level dock settings; room for more general options later.
Column {
    width: parent ? parent.width : 492

    GroupTitle {
        text: "General"
    }

    SettingRow {
        label: "Enable dock"
        Toggle {
            checked: Settings.enabled
            onToggled: on => Settings.enabled = on
        }
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
        label: "Icon size"
        Slider {
            from: Settings.ranges.iconSize[0]
            to: Settings.ranges.iconSize[1]
            stepSize: 2
            value: Settings.iconSize
            suffix: " px"
            onMoved: v => Settings.iconSize = v
        }
    }

    SettingRow {
        label: "Visibility"
        divider: false
        RadioList {
            options: [
                { value: "reserve", label: "Always visible, reserve space", description: "Windows stop above the dock" },
                { value: "overlap", label: "Always visible, overlap", description: "Windows can go under the dock" },
                { value: "autohide", label: "Autohide", description: "Shows when the pointer touches the edge" },
                { value: "intelligent", label: "Intelligent autohide", description: "Hides when a window overlaps it" }
            ]
            current: Settings.visibilityMode
            onSelected: v => Settings.setMode(v)
        }
    }
}
