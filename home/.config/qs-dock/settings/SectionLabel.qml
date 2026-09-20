import QtQuick
import qs

// Heading above a full-width block (exclusion list, running apps), with an optional hint.
Row {
    property alias text: label.text
    property alias hint: hintText.text

    topPadding: 16
    bottomPadding: 8
    spacing: 8

    Text {
        id: label
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 13
        font.bold: true
    }

    Text {
        id: hintText
        anchors.baseline: label.baseline
        visible: text !== ""
        color: Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 12
    }
}
