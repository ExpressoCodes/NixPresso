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
        divider: false
        Toggle {
            checked: Settings.enabled
            onToggled: on => Settings.enabled = on
        }
    }
}
