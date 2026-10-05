import QtQuick
import qs

// Behaviour group (FR-6, FR-7, D-15, UX.md §7.2). The delays only apply to the hidden modes.
Column {
    width: parent ? parent.width : 492

    GroupTitle {
        text: "Behaviour"
    }

    SettingRow {
        label: "Visibility"
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

    SettingRow {
        label: "Hide on fullscreen"
        Toggle {
            checked: Settings.hideOnFullscreen
            onToggled: on => Settings.hideOnFullscreen = on
        }
    }

    SettingRow {
        label: "Show delay"
        Slider {
            enabled: Settings.hiddenMode
            from: Settings.ranges.showDelay[0]
            to: Settings.ranges.showDelay[1]
            stepSize: 50
            value: Settings.showDelay
            suffix: " ms"
            onMoved: v => Settings.showDelay = v
        }
    }

    SettingRow {
        label: "Hide delay"
        Slider {
            enabled: Settings.hiddenMode
            from: Settings.ranges.hideDelay[0]
            to: Settings.ranges.hideDelay[1]
            stepSize: 50
            value: Settings.hideDelay
            suffix: " ms"
            onMoved: v => Settings.hideDelay = v
        }
    }

    SettingRow {
        label: "Animation speed"
        Slider {
            from: Settings.ranges.animationSpeed[0]
            to: Settings.ranges.animationSpeed[1]
            stepSize: 0.25
            value: Settings.animationSpeed
            formatter: v => (Math.round(v * 10) === v * 10 ? v.toFixed(1) : v.toFixed(2)) + "×"
            onMoved: v => Settings.animationSpeed = v
        }
    }

    SettingRow {
        label: "Click on focused app"
        Segmented {
            options: [
                { value: "cycle", label: "Cycle windows" },
                { value: "none", label: "None" }
            ]
            current: Settings.clickFocused
            onSelected: v => Settings.clickFocused = v
        }
    }

    SettingRow {
        label: "Show running unpinned apps"
        Toggle {
            checked: Settings.showRunning
            onToggled: on => Settings.showRunning = on
        }
    }

    SettingRow {
        label: "Bounce on launch"
        divider: false
        Toggle {
            checked: Settings.bounceOnLaunch
            onToggled: on => Settings.bounceOnLaunch = on
        }
    }
}
