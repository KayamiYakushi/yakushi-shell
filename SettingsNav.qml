import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes

// The Settings header strip: 薬 on the left, one icon per page in the
// middle, where you are on the right. Hovering an icon hangs its name
// below it, written downward (English, then Japanese). Search is an icon
// too: click it, or just start typing; its results hang below it the same
// way.
//
// Double-click an icon and keep the button down to move it; let go to
// drop it. System always stays first. The order is saved in
// config.json (appearance.settingsOrder, scripts/yakushi-uistatectl.py).
//
// The search field itself belongs to SettingsWindow (its keys live there);
// it sits in `fieldSlot`.
Item {
    id: nav

    required property var host            // the Settings window

    property Item fieldSlot: null          // the search icon's place for the field
    property bool searchOpen: false
    readonly property bool searching: host.searchQuery.trim() !== ""

    readonly property int cell: 42
    readonly property int gap: 8
    readonly property int step: cell + gap
    readonly property int searchWidth: 240

    height: 56

    // true over the icons (and the open search field): the card's drag
    // handle under the strip lets those clicks through
    function covers(x, y) {
        return x >= icons.x - 4 && x <= icons.x + icons.width + 4 && y >= 0 && y <= height
    }

    // ------------------------------------------------------------------
    // Order
    // ------------------------------------------------------------------
    function keyOf(p) {
        return p.name.toLowerCase().replace(/[^a-z]/g, "")
    }

    // every icon, in the default order: System, Search, then the pages
    readonly property var known: {
        var list = host.pages.map(keyOf)
        list.splice(1, 0, "search")
        return list
    }

    // known keys once each, System first; one the saved order does not
    // know yet goes after its neighbour in the default order
    function clean(saved) {
        var out = ["system"]
        if (Array.isArray(saved))
            saved.forEach(function(k) {
                if (known.indexOf(k) >= 0 && out.indexOf(k) < 0)
                    out.push(k)
            })
        known.forEach(function(k, i) {
            if (out.indexOf(k) >= 0)
                return
            var at = out.length
            for (var j = i - 1; j >= 0; j--) {
                var before = out.indexOf(known[j])
                if (before >= 0) {
                    at = before + 1
                    break
                }
            }
            out.splice(at, 0, k)
        })
        return out
    }

    property var order: clean(null)

    function loadOrder() {
        if (dragKey !== "")
            return
        var next = clean(Config.appearance.settingsOrder)
        if (next.join() !== order.join())
            order = next
    }

    Component.onCompleted: loadOrder()

    Connections {
        target: Config

        function onAppearanceChanged() {
            nav.loadOrder()
        }
    }

    Process {
        id: saveOrder
    }

    function pageOf(key) {
        for (var i = 0; i < host.pages.length; i++)
            if (keyOf(host.pages[i]) === key)
                return i
        return -1
    }

    // ------------------------------------------------------------------
    // Moving an icon: double-click, hold, drag
    // ------------------------------------------------------------------
    property string dragKey: ""
    property int dragFrom: -1
    property real dragDx: 0
    readonly property int dragTo: dragKey === "" ? -1
        : Math.max(1, Math.min(order.length - 1, dragFrom + Math.round(dragDx / step)))

    function beginDrag(key) {
        var from = order.indexOf(key)
        if (from <= 0 || searchOpen)              // System stays put
            return false
        dragFrom = from
        dragDx = 0
        dragKey = key
        return true
    }

    function endDrag() {
        if (dragKey === "")
            return
        var from = dragFrom
        var to = dragTo
        if (to !== from) {
            var next = order.slice()
            next.splice(from, 1)
            next.splice(to, 0, dragKey)
            order = next
            saveOrder.command = ["python3", Paths.script("yakushi-uistatectl.py"), "order", next.join(",")]
            saveOrder.running = true
        }
        dragKey = ""
        dragFrom = -1
        dragDx = 0
        // the icons were made anew: the field needs the keyboard back
        Qt.callLater(host.focusSearch)
    }

    // how far the icon at `i` steps aside for the one being moved
    function shiftOf(i) {
        if (dragKey === "" || i === dragFrom)
            return 0
        if (dragFrom < dragTo && i > dragFrom && i <= dragTo)
            return -step
        if (dragTo < dragFrom && i >= dragTo && i < dragFrom)
            return step
        return 0
    }

    // ------------------------------------------------------------------
    // The name under the pointer
    // ------------------------------------------------------------------
    property string hoverKey: ""
    property real hoverX: 0
    property string tipKey: ""
    property real tipX: 0
    property bool tipOpen: false

    onHoverKeyChanged: {
        if (hoverKey === "") {
            tipDelay.stop()
            tipLinger.restart()
            return
        }
        tipLinger.stop()
        if (tipOpen) {
            tipKey = hoverKey
            tipX = hoverX
        } else {
            tipDelay.restart()
        }
    }
    onHoverXChanged: if (tipOpen && hoverKey !== "") tipX = hoverX
    onDragKeyChanged: if (dragKey !== "") tipOpen = false

    Timer {
        id: tipDelay
        interval: 110
        onTriggered: {
            if (nav.hoverKey === "" || nav.dragKey !== "")
                return
            nav.tipKey = nav.hoverKey
            nav.tipX = nav.hoverX
            nav.tipOpen = true
        }
    }

    Timer {
        id: tipLinger
        interval: 140
        onTriggered: nav.tipOpen = false
    }

    function tipName(key) {
        if (key === "search")
            return "SEARCH"
        var i = pageOf(key)
        return i < 0 ? "" : host.pages[i].name.toUpperCase()
    }

    function tipJp(key) {
        if (key === "search")
            return "検索"
        var i = pageOf(key)
        // the long-vowel mark stands upright in vertical writing
        return i < 0 ? "" : String(host.pages[i].jp).replace(/ー/g, "︱")
    }

    // ------------------------------------------------------------------
    // Search
    // ------------------------------------------------------------------
    function openSearch() {
        searchOpen = true
        host.focusSearch()
    }

    // ------------------------------------------------------------------
    // The strip
    // ------------------------------------------------------------------
    Text {
        id: mark

        textFormat: Text.PlainText
        x: 22
        anchors.verticalCenter: parent.verticalCenter
        text: "薬"
        color: Theme.alert
        font.family: "Noto Sans CJK JP"
        font.pixelSize: 26
        font.bold: true
    }

    Row {
        id: where

        // steps out of the way of a wide open search on a narrow card
        opacity: icons.x + icons.width < x - 16 ? 1 : 0
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: nav.host.pages[nav.host.page].jp
            color: Theme.inkSoft
            font.family: "Noto Sans CJK JP"
            font.pixelSize: 13
            font.letterSpacing: 2
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 16
            color: Theme.tint(Theme.ink, 0.18)
        }

        Text {
            readonly property int at: nav.order.filter(function(k) { return k !== "search" })
                .indexOf(nav.keyOf(nav.host.pages[nav.host.page])) + 1

            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: nav.host.two(at) + " / " + nav.host.two(nav.host.pages.length)
            color: Theme.accent
            font.family: Theme.mono
            font.pixelSize: 12
            font.bold: true
            font.letterSpacing: 2
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.tint(Theme.ink, 0.12)
    }

    // ---- the icons
    Row {
        id: icons

        // centred, but never over 薬
        x: Math.max(mark.x + mark.width + 18, (nav.width - width) / 2)
        anchors.verticalCenter: parent.verticalCenter
        spacing: nav.gap

        Repeater {
            model: nav.order

            delegate: Item {
                id: icon

                required property string modelData
                required property int index

                readonly property bool isSearch: modelData === "search"
                readonly property int pageIndex: nav.pageOf(modelData)
                readonly property bool here: pageIndex >= 0 && nav.host.page === pageIndex
                readonly property bool open: isSearch && nav.searchOpen
                readonly property bool lifted: nav.dragKey === modelData
                readonly property bool hot: mouse.containsMouse || lifted

                width: open ? nav.searchWidth : nav.cell
                height: nav.cell - 6
                z: lifted ? 5 : 0
                clip: isSearch

                Behavior on width {
                    NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                }

                transform: Translate {
                    x: icon.lifted
                        ? Math.max(-nav.step * (icon.index - 1),
                                   Math.min(nav.step * (nav.order.length - 1 - icon.index), nav.dragDx))
                        : nav.shiftOf(icon.index)

                    Behavior on x {
                        enabled: !icon.lifted
                        NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                    }
                }

                CutBox {
                    anchors.fill: parent
                    cut: Theme.cutSmall
                    cutTopLeft: false
                    cutBottomRight: false
                    fill: icon.here ? Theme.accent
                        : icon.open ? Theme.tint(Theme.ink, 0.03)
                        : icon.hot ? Theme.tint(Theme.ink, 0.07) : "transparent"
                    stroke: icon.lifted ? Theme.accent
                        : icon.open ? (nav.host.searchFocused ? Theme.accent : Theme.line)
                        : "transparent"
                }

                Text {
                    id: glyph

                    textFormat: Text.PlainText
                    x: icon.open ? 13 : (nav.cell - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: icon.isSearch ? String.fromCodePoint(0xF0349)
                        : icon.pageIndex >= 0 ? nav.host.pages[icon.pageIndex].glyph : ""
                    color: icon.here ? nav.host.onAccent
                        : icon.hot || (icon.open && nav.host.searchFocused) ? Theme.accent
                        : Theme.inkSoft
                    font.family: Theme.glyphs
                    font.pixelSize: 19

                    Behavior on x {
                        NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Theme.tFast }
                    }
                }

                // the search field (SettingsWindow's) sits here, also while
                // closed: it keeps the keyboard, so typing opens it
                Item {
                    id: slot

                    visible: icon.isSearch
                    anchors.left: glyph.right
                    anchors.leftMargin: 9
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    opacity: icon.open ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.tFast }
                    }

                    Component.onCompleted: if (icon.isSearch) nav.fieldSlot = slot
                }

                MouseArea {
                    id: mouse

                    // the open field takes its own clicks
                    anchors.fill: icon.open ? glyph : parent
                    anchors.margins: icon.open ? -6 : 0
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: icon.lifted ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    property real pressX: 0

                    onContainsMouseChanged: {
                        if (containsMouse) {
                            nav.hoverX = icon.mapToItem(nav, icon.width / 2, 0).x
                            nav.hoverKey = icon.modelData
                        } else if (nav.hoverKey === icon.modelData) {
                            nav.hoverKey = ""
                        }
                    }

                    onPressed: mouse => pressX = mapToItem(nav, mouse.x, 0).x
                    onClicked: {
                        if (icon.isSearch)
                            nav.openSearch()
                        else if (icon.pageIndex >= 0)
                            nav.host.page = icon.pageIndex
                    }
                    onDoubleClicked: mouse => {
                        pressX = mapToItem(nav, mouse.x, 0).x
                        nav.beginDrag(icon.modelData)
                    }
                    onPositionChanged: mouse => {
                        if (icon.lifted)
                            nav.dragDx = mapToItem(nav, mouse.x, 0).x - pressX
                    }
                    onReleased: nav.endDrag()
                    onCanceled: nav.endDrag()
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Things hanging from the strip: a 45-degree shoulder on each side
    // into the strip's rule, cut lower corners (the island's cards' shape)
    // ------------------------------------------------------------------
    component Hang: Item {
        id: hang

        property real openness: 0
        property real fullHeight: 100
        property real ear: 8
        default property alias content: hangInner.data

        y: nav.height - 1
        height: fullHeight * openness
        visible: openness > 0.01
        clip: true

        Shape {
            id: hangShape

            readonly property real h: hang.height
            readonly property real e: Math.max(0.01, Math.min(hang.ear, h))
            readonly property real r: Math.max(0.01, Math.min(Theme.cutSmall + 3, (h - e) / 2))

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.tint(Theme.surface, Math.max(0.96, Theme.glass))
                strokeColor: "transparent"
                strokeWidth: 0

                startX: 0
                startY: 0
                PathLine { x: hang.width; y: 0 }
                PathLine { x: hang.width - hang.ear; y: hangShape.e }
                PathLine { x: hang.width - hang.ear; y: hangShape.h - hangShape.r }
                PathLine { x: hang.width - hang.ear - hangShape.r; y: hangShape.h }
                PathLine { x: hang.ear + hangShape.r; y: hangShape.h }
                PathLine { x: hang.ear; y: hangShape.h - hangShape.r }
                PathLine { x: hang.ear; y: hangShape.e }
                PathLine { x: 0; y: 0 }
            }

            // the outline, open at the top: the strip's rule runs into it
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.tint(Theme.ink, 0.12)
                strokeWidth: 1
                joinStyle: ShapePath.MiterJoin

                startX: 0
                startY: 0.5
                PathLine { x: hang.ear + 0.5; y: hangShape.e }
                PathLine { x: hang.ear + 0.5; y: hangShape.h - hangShape.r }
                PathLine { x: hang.ear + hangShape.r; y: hangShape.h - 0.5 }
                PathLine { x: hang.width - hang.ear - hangShape.r; y: hangShape.h - 0.5 }
                PathLine { x: hang.width - hang.ear - 0.5; y: hangShape.h - hangShape.r }
                PathLine { x: hang.width - hang.ear - 0.5; y: hangShape.e }
                PathLine { x: hang.width; y: 0.5 }
            }
        }

        Item {
            id: hangInner

            x: hang.ear
            width: hang.width - 2 * hang.ear
            height: hang.fullHeight
        }
    }

    // ---- the name, written downward
    Hang {
        id: tip

        readonly property string name: nav.tipName(nav.tipKey)
        readonly property string jp: nav.tipJp(nav.tipKey)

        z: 2
        width: 40 + 2 * ear
        x: nav.tipX - width / 2
        fullHeight: words.implicitHeight + 30
        openness: nav.tipOpen && !nav.searching && !(nav.tipKey === "search" && nav.searchOpen) ? 1 : 0

        Behavior on openness {
            NumberAnimation { duration: Theme.tMid + 40; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            enabled: tip.openness > 0.5
            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
        }

        Column {
            id: words

            y: 14
            width: parent.width
            spacing: 0

            Repeater {
                model: tip.name.split("")

                delegate: Text {
                    required property string modelData

                    width: parent.width
                    height: 16
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: modelData
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 14
                    font.bold: true
                }
            }

            Item {
                width: parent.width
                height: 18

                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 2
                    color: Theme.accent
                }
            }

            Repeater {
                model: tip.jp.split("")

                delegate: Text {
                    required property string modelData

                    width: parent.width
                    height: 18
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: modelData
                    color: Theme.inkSoft
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 13
                }
            }
        }
    }

    // ---- search results, hanging below the search icon
    Hang {
        id: results

        readonly property Item anchorIcon: nav.fieldSlot ? nav.fieldSlot.parent : null

        z: 3
        width: 400
        x: {
            if (!anchorIcon)
                return 0
            var at = anchorIcon.mapToItem(nav, 0, 0).x - 10
            return Math.max(12, Math.min(nav.width - width - 12, at))
        }
        fullHeight: resultList.implicitHeight + 16
        openness: nav.searching ? 1 : 0

        Behavior on openness {
            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
        }

        Column {
            id: resultList

            y: 6
            width: parent.width

            Repeater {
                model: nav.host.searchResults

                delegate: Rectangle {
                    id: hit

                    required property var modelData
                    required property int index
                    readonly property bool here: nav.host.searchIndex === index
                    readonly property color ink: here ? nav.host.onAccent : Theme.ink

                    width: parent.width
                    height: 50
                    color: here ? Theme.accent : hitMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.tFast }
                    }

                    Column {
                        x: 18
                        width: parent.width - 36
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            elide: Text.ElideRight
                            text: hit.modelData.entry.title
                            color: hit.ink
                            font.family: Theme.mono
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            elide: Text.ElideRight
                            text: hit.modelData.entry.page ? nav.host.placeOf(hit.modelData.entry.page) : "OPENS ON ITS OWN"
                            color: hit.here ? Theme.tint(hit.ink, 0.75) : Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 10
                            font.letterSpacing: 1.5
                        }
                    }

                    MouseArea {
                        id: hitMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: nav.host.searchIndex = hit.index
                        onClicked: nav.host.openResult(hit.index)
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: nav.host.searchResults.length === 0
                x: 16
                width: parent.width - 32
                topPadding: 10
                bottomPadding: 10
                wrapMode: Text.Wrap
                text: "No setting matches. Try other words."
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 12
            }
        }
    }
}
