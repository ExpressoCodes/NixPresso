import QtQuick
import qs

// Appearance group (FR-6, UX.md §7.2/§7.3). Every control writes Settings directly.
Column {
    width: parent ? parent.width : 492

    GroupTitle {
        text: "Appearance"
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
        label: "Magnification"
        Toggle {
            checked: Settings.magnification
            onToggled: on => Settings.magnification = on
        }
    }

    SettingRow {
        label: "Max magnified size"
        Slider {
            enabled: Settings.magnification
            from: Settings.iconSize
            to: Settings.ranges.maxMagnifiedSize[1]
            stepSize: 2
            value: Settings.maxMagnifiedSize
            suffix: " px"
            onMoved: v => Settings.maxMagnifiedSize = v
        }
    }

    SettingRow {
        label: "Magnification spread"
        help: "Icons affected on each side"
        Slider {
            enabled: Settings.magnification
            from: Settings.ranges.magnificationSpread[0]
            to: Settings.ranges.magnificationSpread[1]
            stepSize: 0.5
            decimals: 1
            value: Settings.magnificationSpread
            onMoved: v => Settings.magnificationSpread = v
        }
    }

    SettingRow {
        label: "Spacing"
        Slider {
            from: Settings.ranges.spacing[0]
            to: Settings.ranges.spacing[1]
            value: Settings.spacing
            suffix: " px"
            onMoved: v => Settings.spacing = v
        }
    }

    SettingRow {
        label: "Background opacity"
        Slider {
            from: Settings.ranges.backgroundOpacity[0]
            to: Settings.ranges.backgroundOpacity[1]
            stepSize: 5
            value: Settings.backgroundOpacity
            suffix: " %"
            onMoved: v => Settings.backgroundOpacity = v
        }
    }

    SettingRow {
        label: "Corner radius"
        Slider {
            from: Settings.ranges.cornerRadius[0]
            to: Settings.ranges.cornerRadius[1]
            value: Settings.cornerRadius
            suffix: " px"
            onMoved: v => Settings.cornerRadius = v
        }
    }

    SettingRow {
        label: "Show separator"
        Toggle {
            checked: Settings.showSeparator
            onToggled: on => Settings.showSeparator = on
        }
    }

    SettingRow {
        label: "Indicator style"
        divider: false
        Segmented {
            options: [
                { value: "none", label: "None" },
                { value: "dot", label: "Dot" },
                { value: "dot-per-window", label: "Per window" }
            ]
            current: Settings.indicatorStyle
            onSelected: v => Settings.indicatorStyle = v
        }
    }
}
