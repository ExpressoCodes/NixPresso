pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property color bg: "#1e1e2e"
    readonly property color fg: "#cdd6f4"
    readonly property color dim: "#6c7086"
    readonly property color accent: "#89b4fa"
    readonly property color hover: "#313244"
    readonly property color popupBg: "#181825"
    readonly property int barHeight: 30
    readonly property real barOpacity: 0.85   // island background opacity (0.0–1.0)
    readonly property int fontSize: 13
    readonly property string font: "sans-serif"
}
