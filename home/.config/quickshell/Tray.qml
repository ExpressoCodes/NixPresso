import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Row {
    id: root
    required property var bar
    spacing: 4

    Repeater {
        model: SystemTray.items

        MouseArea {
            id: item
            required property SystemTrayItem modelData
            width: 18
            height: 18
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            IconImage {
                anchors.fill: parent
                source: item.modelData.icon
            }

            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    modelData.secondaryActivate();
                } else if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                    if (modelData.hasMenu) {
                        if (modelData.menu?.menu) modelData.menu.menu.updateLayout();
                        menuPopup.toggle();
                    }
                } else {
                    modelData.activate();
                }
            }

            QsMenuOpener {
                id: menuOpener
                menu: item.modelData.menu
            }

            TrayMenuPopup {
                id: menuPopup
                anchorItem: item

                Repeater {
                    model: menuOpener.children

                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        implicitHeight: modelData.isSeparator ? 9 : Theme.barHeight - 6

                        Rectangle {
                            visible: modelData.isSeparator
                            anchors.centerIn: parent
                            width: parent.width
                            height: 1
                            color: Theme.hover
                        }

                        BarButton {
                            visible: !modelData.isSeparator
                            width: parent.width
                            text: modelData.text
                            textColor: modelData.enabled ? Theme.fg : Theme.dim
                            onClicked: {
                                const label = modelData.text;
                                const sniId = item.modelData.id;
                                menuPopup.visible = false;
                                Quickshell.execDetached([
                                    Quickshell.shellDir + "/tray-trigger.sh",
                                    sniId,
                                    label
                                ]);
                            }
                        }
                    }
                }
            }
        }
    }
}
