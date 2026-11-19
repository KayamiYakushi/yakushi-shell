import QtQuick
import "../"

// The tray on the island: one small icon per program (TrayState.qml).
// Click: the program's own action (or its menu, when that is all it has);
// right-click: its menu, as a card under the island (TrayMenu.qml);
// middle-click: its second action; scroll: passed on to it.
// Press and drag an icon sideways to move it among the others; the order
// is saved by program id (BarConfig.trayOrder), so a program that comes
// back later takes its old place. New programs line up at the end.
// Icons rest a little faded and come up to full on hover.
Item {
    id: m

    required property var tray            // TrayState
    property int barHeight: 32
    property var order: []                // saved program ids
    property bool moduleMoving: false     // the whole tray is being moved on the island
    property var openItem: null           // the program whose menu is open

    signal menuRequested(var item, real centerX)
    signal dragStarted()
    signal reordered(var ids)

    readonly property int iconSize: 16
    readonly property int gap: 10
    readonly property int stride: iconSize + gap

    implicitWidth: row.implicitWidth
    implicitHeight: barHeight
    height: barHeight

    function keyOf(item) {
        return item ? (item.id || item.title || "") : ""
    }

    // the programs in the saved order; unknown ones after, as they arrived
    readonly property var items: {
        if (!tray)
            return []
        var saved = order
        return tray.items.map(function(item, i) {
            var at = saved.indexOf(m.keyOf(item))
            return { item: item, arrived: i, rank: at < 0 ? saved.length : at }
        }).sort(function(a, b) {
            return a.rank - b.rank || a.arrived - b.arrived
        }).map(function(entry) {
            return entry.item
        })
    }

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

    // -------------------------
    // Dragging an icon
    // -------------------------
    property int dragFrom: -1
    property real dragDx: 0

    // every icon is as wide as the next, so the drop place is a division
    readonly property int dragTo: dragFrom < 0 ? -1
        : Math.max(0, Math.min(items.length - 1, dragFrom + Math.round(dragDx / stride)))

    // how far the icon at `i` steps aside for the one being moved
    function shiftOf(i) {
        if (dragFrom < 0 || i === dragFrom)
            return 0
        if (dragFrom < dragTo && i > dragFrom && i <= dragTo)
            return -stride
        if (dragTo < dragFrom && i >= dragTo && i < dragFrom)
            return stride
        return 0
    }

    function dragBy(dx) {
        dragDx = Math.max(-dragFrom * stride, Math.min((items.length - 1 - dragFrom) * stride, dx))
    }

    // Applied a moment later: the new order rebuilds the icons, the one
    // under the pointer included, which must not happen inside its own
    // mouse handler. Until then the icons stay where they were dropped.
    function drop() {
        var from = dragFrom
        var to = dragTo
        Qt.callLater(function() {
            if (to >= 0 && to !== from) {
                var list = m.items.slice()
                list.splice(to, 0, list.splice(from, 1)[0])
                var ids = []
                list.forEach(function(item) {
                    var key = m.keyOf(item)
                    if (key !== "" && ids.indexOf(key) < 0)
                        ids.push(key)
                })
                // programs not running now keep their place in the memory
                m.order.forEach(function(key) {
                    if (ids.indexOf(key) < 0)
                        ids.push(key)
                })
                m.reordered(ids)
            }
            m.dragFrom = -1
            m.dragDx = 0
        })
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: m.gap

        Repeater {
            model: m.items

            delegate: Item {
                id: slot

                required property var modelData
                required property int index

                readonly property bool open: m.openItem === modelData
                readonly property bool lifted: m.dragFrom === index
                readonly property bool hot: mouse.containsMouse || open || lifted

                width: m.iconSize
                height: m.barHeight
                z: lifted ? 5 : 0
                // the others step back a little while one is moved
                opacity: m.dragFrom < 0 || lifted ? 1 : 0.6

                Behavior on opacity {
                    NumberAnimation { duration: Theme.tFast }
                }

                transform: Translate {
                    x: slot.lifted ? m.dragDx : m.shiftOf(slot.index)

                    Behavior on x {
                        enabled: !slot.lifted
                        NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                    }
                }

                Image {
                    id: image

                    anchors.centerIn: parent
                    width: m.iconSize
                    height: m.iconSize
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

                // under it: an accent mark while its menu is open or it is
                // being moved, a red one while it asks for attention
                // (Status.NeedsAttention = 2)
                Rectangle {
                    visible: slot.modelData.status === 2 || slot.open || slot.lifted
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: m.barHeight - 7
                    width: slot.open || slot.lifted ? 10 : 4
                    height: 2
                    color: slot.open || slot.lifted ? Theme.accent : Theme.alert
                }

                MouseArea {
                    id: mouse

                    property real pressX: 0
                    property bool moved: false

                    anchors.fill: parent
                    anchors.leftMargin: -5
                    anchors.rightMargin: -5
                    hoverEnabled: true
                    preventStealing: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: moved ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    function centerX() {
                        return slot.mapToItem(null, slot.width / 2, 0).x
                    }

                    // the pointer in the tray's own coordinates: the icon
                    // itself moves under it while dragged
                    function trayX(event) {
                        return mapToItem(m, event.x, 0).x
                    }

                    onPressed: function(event) {
                        moved = false
                        if (event.button === Qt.LeftButton)
                            pressX = trayX(event)
                    }

                    onPositionChanged: function(event) {
                        if (!(pressedButtons & Qt.LeftButton) || m.moduleMoving)
                            return
                        var dx = trayX(event) - pressX
                        if (!moved && Math.abs(dx) > 6 && m.items.length > 1 && m.dragFrom < 0) {
                            moved = true
                            m.dragFrom = slot.index
                            m.dragStarted()
                        }
                        if (moved)
                            m.dragBy(dx)
                    }

                    onReleased: if (moved) m.drop()

                    onCanceled: {
                        if (moved) {
                            m.dragFrom = -1
                            m.dragDx = 0
                        }
                        moved = false
                    }

                    onClicked: function(event) {
                        if (moved)
                            return
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
