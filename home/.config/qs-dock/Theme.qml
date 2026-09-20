pragma Singleton
import QtQuick
import Quickshell

// Catppuccin Mocha. The first six values are copied verbatim from the bar's Theme.qml (NFR-6).
Singleton {
    readonly property color bg: "#1e1e2e"
    readonly property color fg: "#cdd6f4"
    readonly property color dim: "#6c7086"
    readonly property color accent: "#89b4fa"
    readonly property color hover: "#313244"
    readonly property color popupBg: "#181825"

    readonly property color crust: "#11111b"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color overlay1: "#7f849c"
    readonly property color overlay2: "#9399b2"
    readonly property color subtext0: "#a6adc8"
    readonly property color subtext1: "#bac2de"
    readonly property color red: "#f38ba8"
    readonly property color peach: "#fab387"

    readonly property string font: "sans-serif"
    readonly property int fontSize: 13

    // Every animation duration goes through this (UX.md notation: dur(base)).
    function dur(base: int): int {
        return Math.round(base / Settings.animationSpeed);
    }
}
