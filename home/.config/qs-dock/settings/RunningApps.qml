pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// Running-apps picker (UX.md §7.3). Lists every running appId, excluded ones included. The switch
// adds the exact appId to the exclusion list, and removes the pattern that hides it (the appId,
// or the `entry:` pattern left by "Hide from Dock"). Apps hidden by a default or regex pattern,
// or by NoDisplay, get a disabled switch and say why.
Rectangle {
    id: root

    readonly property var apps: AppModel.runningAppIds.map(id => {
        const e = AppModel.resolve(id);
        return {
            appId: id,
            name: e?.name || id,
            icon: Quickshell.iconPath(e?.icon || id, "application-x-generic"),
            noDisplay: e?.noDisplay ?? false
        };
    }).sort((a, b) => a.name.localeCompare(b.name))

    width: parent ? parent.width : 492
    height: Math.max(36, list.height) + 2
    radius: 6
    color: Theme.popupBg
    border.width: 1
    border.color: Theme.surface1

    Text {
        visible: root.apps.length === 0
        x: 12
        height: 38
        verticalAlignment: Text.AlignVCenter
        text: "No running apps"
        color: Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 12
    }

    Column {
        id: list
        x: 1
        y: 1
        width: parent.width - 2

        Repeater {
            model: root.apps

            Item {
                id: row
                required property var modelData
                required property int index

                readonly property string appId: modelData.appId
                readonly property string match: Settings.matchExclusion(appId)
                readonly property bool isDefault: Settings.defaultExclusions.includes(match)
                // Only a user-added exact appId, or the `entry:` pattern "Hide from Dock" stores, can be
                // toggled back from here.
                readonly property bool ownEntry: match !== "" && !isDefault && (match === appId || match.startsWith("entry:"))
                readonly property bool inDock: AppModel.items.some(i => i.appIds.includes(row.appId))
                readonly property string lockReason: {
                    if (match !== "" && !ownEntry)
                        return isDefault ? "matched by default" : "matched by " + match;
                    if (match === "" && Settings.hideNoDisplay && modelData.noDisplay && !inDock)
                        return "NoDisplay";
                    return "";
                }

                width: list.width
                height: 36

                Image {
                    x: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    sourceSize: Qt.size(40, 40)
                    source: row.modelData.icon
                    smooth: true
                    mipmap: true
                }

                Text {
                    id: name
                    x: 41
                    width: 130
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                }

                Text {
                    x: name.x + name.width + 12
                    width: status.x - x - 12
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                    text: row.appId
                    color: Theme.subtext0
                    font.family: "monospace"
                    font.pixelSize: 12
                }

                Text {
                    id: status
                    anchors.right: toggle.left
                    anchors.rightMargin: 8
                    width: Math.min(implicitWidth, 150)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideMiddle
                    text: row.lockReason !== "" ? row.lockReason : row.match === "" ? "Shown" : "Hidden"
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 12
                }

                Toggle {
                    id: toggle
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: row.lockReason === ""
                    checked: row.match === "" && row.lockReason === ""
                    onToggled: on => {
                        if (on)
                            Settings.removeExclusion(row.match);
                        else
                            Settings.addExclusion(row.appId);
                    }
                }

                Rectangle {
                    visible: row.index < root.apps.length - 1
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.hover
                }
            }
        }
    }
}
