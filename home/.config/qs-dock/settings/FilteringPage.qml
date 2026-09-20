import QtQuick
import qs

// Filtering group (FR-5, FR-6, D-14, UX.md §7.2).
Column {
    width: parent ? parent.width : 492

    GroupTitle {
        text: "Filtering"
    }

    SettingRow {
        label: "Hide NoDisplay apps"
        help: "Apps whose desktop entry is hidden from menus"
        divider: false
        Toggle {
            checked: Settings.hideNoDisplay
            onToggled: on => Settings.hideNoDisplay = on
        }
    }

    SectionLabel {
        text: "Excluded apps"
        hint: "(exact appId, or /regex/)"
    }

    ExclusionEditor {}

    SectionLabel {
        text: "Running apps"
    }

    RunningApps {}
}
