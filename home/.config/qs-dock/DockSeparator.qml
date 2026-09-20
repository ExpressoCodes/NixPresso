import QtQuick

// Thin line between the pinned and running sections (UX.md §2.1, dock.separator).
Rectangle {
    required property int thickness
    required property int length

    width: thickness
    height: length
    radius: thickness / 2
    color: Theme.surface2
}
