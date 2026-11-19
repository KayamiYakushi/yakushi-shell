import QtQuick
import "../"

// The tray on the island: one small icon per program (TrayState.qml).
// Click: the program's own action (or its menu, when that is all it has);
// right-click: its menu, as a card under the island (TrayMenu.qml);
// middle-click: its second action; scroll: passed on to it.
// Icons rest a little faded and come up to full on hover.
Item {
    id: m

    required property var tray            // TrayState
    property int barHeight: 32
    property var openItem: null           // the program whose menu is open

    signal menuRequested(var item, real centerX)

    implicitWidth: row.implicitWidth
    implicitHeight: barHeight
    height: barHeight

    // Some programs (Electron ones, Spotify) give an icon name with a
    // ?path= to look in, which the icon theme cannot resolve.
    function iconSource(icon) {
        if (typeof icon !== "string" || icon === "")
            return ""
        var at = icon.indexOf("?path=")
        if (at < 0)
            return icon
        var name = icon.slice(0, at)
        return "file://" + icon.slice(at + 6) + "/" + name.slice(name.lastIndexOf("/") + 1)
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
            model: m.tray ? m.tray.items : []

            delegate: Item {
                id: slot

                required property var modelData

                readonly property bool open: m.openItem === modelData
                readonly property bool hot: mouse.containsMouse || open

                width: 16
                height: m.barHeight

                Image {
                    id: image

                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    sourceSize: Qt.size(32, 32)
                    source: m.iconSource(slot.modelData.icon)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    opacity: slot.hot ? 1 : 0.78

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.tFast }
                    }
                }

                // no icon at all: the first letter of its name
                Text {
                    visible: image.status !== Image.Ready
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: (slot.modelData.title || slot.modelData.id || "?").charAt(0).toUpperCase()
                    color: slot.hot ? Theme.accent : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.bold: true
                }

                // a program asking for attention: an accent mark under it
                Rectangle {
                    visible: slot.modelData.status === 2 || slot.open
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: m.barHeight - 7
                    width: slot.open ? 10 : 4
                    height: 2
                    color: slot.open ? Theme.accent : Theme.alert
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    anchors.leftMargin: -5
                    anchors.rightMargin: -5
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor

                    function centerX() {
                        return slot.mapToItem(null, slot.width / 2, 0).x
                    }

                    onClicked: function(event) {
                        var item = slot.modelData
                        if (event.button === Qt.MiddleButton) {
                            item.secondaryActivate()
                        } else if (event.button === Qt.RightButton || item.onlyMenu) {
                            if (item.hasMenu)
                                m.menuRequested(item, centerX())
                            else if (item.onlyMenu)
                                item.activate()
                        } else {
                            item.activate()
                        }
                    }

                    // the second click of a double-click moves the module
                    // (TopBar.qml); it is not a second activation
                    onDoubleClicked: {}

                    onWheel: function(event) {
                        slot.modelData.scroll(event.angleDelta.y, false)
                    }
                }
            }
        }
    }
}
