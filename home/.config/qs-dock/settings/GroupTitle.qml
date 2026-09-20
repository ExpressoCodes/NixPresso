import QtQuick
import qs

// Group heading (UX.md §7.1): 17 px bold, 32 px row, 16 px space below.
Item {
    property alias text: title.text

    width: parent ? parent.width : 492
    height: 48

    Text {
        id: title
        height: 32
        verticalAlignment: Text.AlignVCenter
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 17
        font.bold: true
    }
}
