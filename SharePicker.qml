import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

// Screen-share picker for xdg-desktop-portal-hyprland (share-picker.sh is
// its custom_picker_binary). Built from the Settings pieces: the same card,
// header strip, numbered list, page title, switch and buttons, so it looks
// and behaves like a Settings page. Previews are live.
//
// The choice is written to $YAKUSHI_PICK_OUT in xdph's format and the
// process quits; writing nothing means "cancelled".
//   [SELECTION]<flags>/screen:<output>
//   [SELECTION]<flags>/window:<handle>
//   [SELECTION]<flags>/region:<output>@<x>,<y>,<w>,<h>
PanelWindow {
    id: picker

    property bool showing: false
    property int page: 0
    property bool reuse: false
    property string query: ""
    property bool done: false

    readonly property string outPath: Quickshell.env("YAKUSHI_PICK_OUT") || ""

    readonly property var pages: [
        { name: "Screens", jp: "画面",       glyph: String.fromCodePoint(0xF0379),
          hint: "Share an entire display. Everything shown on it will be visible." },
        { name: "Windows", jp: "ウィンドウ", glyph: String.fromCodePoint(0xF05B0),
          hint: "Share a single window. Other windows and notifications stay private." },
        { name: "Region",  jp: "範囲",       glyph: String.fromCodePoint(0xF0489),
          hint: "Share a fixed area of one display. Drag a rectangle to choose it." }
    ]

    function two(n) {
        return n < 10 ? "0" + n : String(n)
    }

    readonly property color onAccent: 0.299 * Theme.accent.r + 0.587 * Theme.accent.g + 0.114 * Theme.accent.b > 0.55
        ? "#0a0a0a" : "#f5f5f5"

    // ------------------------------------------------------------------
    // Sources
    // ------------------------------------------------------------------
    // Monitor details and the workspaces on screen, read once from hyprctl
    // (Hyprland's QML monitor objects stay empty with the Lua config).
    property var monInfo: ({})
    property var visibleWs: ({})

    Process {
        id: monProc

        command: ["hyprctl", "monitors", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var info = {}, ws = {}
                    var list = JSON.parse(text)
                    for (var i = 0; i < list.length; i++) {
                        var m = list[i]
                        info[m.name] = m
                        if (m.activeWorkspace)
                            ws[m.activeWorkspace.id] = true
                        if (m.specialWorkspace && m.specialWorkspace.id)
                            ws[m.specialWorkspace.id] = true
                    }
                    picker.monInfo = info
                    picker.visibleWs = ws
                } catch (e) {
                }
            }
        }
    }

    readonly property var screenItems: {
        var list = []
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var s = Quickshell.screens[i]
            var m = monInfo[s.name] || null
            var hz = m && m.refreshRate ? Math.round(m.refreshRate) : 0
            var px = m ? m.width + " × " + m.height : s.width + " × " + s.height
            var desc = m && m.description ? m.description : (s.model || "")
            list.push({
                kind: "screen",
                key: s.name,
                value: s.name,
                title: s.name,
                detail: px + (hz ? " · " + hz + " Hz" : "") + (desc ? " · " + desc : ""),
                badge: m && m.activeWorkspace ? "WS " + m.activeWorkspace.name : "",
                live: true,
                source: s,
                icon: ""
            })
        }
        list.sort(function(a, b) { return a.source.x - b.source.x || a.source.y - b.source.y })
        return list
    }

    // xdph: handle[HC>]class[HT>]title[HE>]address[HA>]...
    readonly property var sharingList: {
        var raw = Quickshell.env("XDPH_WINDOW_SHARING_LIST")
        if (!raw)
            return null
        var out = []
        var chunks = String(raw).split("[HA>]")
        for (var i = 0; i < chunks.length; i++) {
            var c = chunks[i]
            var a = c.indexOf("[HC>]"), b = c.indexOf("[HT>]"), e = c.indexOf("[HE>]")
            if (a < 0 || b < a || e < b)
                continue
            var addr = c.slice(e + 5)
            out.push({
                handle: c.slice(0, a),
                cls: c.slice(a + 5, b),
                title: c.slice(b + 5, e),
                addr: String(addr.indexOf("0x") === 0 ? parseInt(addr, 16) : Number(addr))
            })
        }
        return out
    }

    // "" when the icon theme has nothing: the tile shows a glyph instead
    function iconFor(cls) {
        if (!cls)
            return ""
        var entry = DesktopEntries.heuristicLookup(cls)
        var names = [entry && entry.icon ? entry.icon : "", cls, String(cls).toLowerCase()]
        for (var i = 0; i < names.length; i++) {
            if (names[i] === "")
                continue
            if (names[i].charAt(0) === "/")
                return "file://" + names[i]
            var path = Quickshell.iconPath(names[i], true)
            if (path !== "")
                return path
        }
        return ""
    }

    readonly property var windowItems: {
        var tls = Hyprland.toplevels.values
        var byAddr = {}
        for (var i = 0; i < tls.length; i++)
            byAddr[String(parseInt(tls[i].address, 16))] = tls[i]

        var src = sharingList
        if (src === null) {          // started by hand: list Hyprland's windows
            src = []
            for (var k = 0; k < tls.length; k++) {
                var ipc = tls[k].lastIpcObject
                src.push({ handle: "", cls: ipc && ipc["class"] ? ipc["class"] : (tls[k].wayland ? tls[k].wayland.appId : ""),
                           title: tls[k].title, addr: String(parseInt(tls[k].address, 16)) })
            }
        }

        var q = query.trim().toLowerCase().split(/\s+/).filter(function(p) { return p !== "" })
        var list = []
        for (var n = 0; n < src.length; n++) {
            var w = src[n]
            var tl = byAddr[w.addr] || null
            var cls = w.cls || (tl && tl.wayland ? tl.wayland.appId : "")
            var title = w.title || (tl ? tl.title : "") || cls || "Untitled window"
            var hay = (title + " " + cls).toLowerCase()
            var match = true
            for (var p = 0; p < q.length; p++)
                if (hay.indexOf(q[p]) < 0)
                    match = false
            if (!match)
                continue
            var ws = tl && tl.lastIpcObject ? tl.lastIpcObject.workspace : null
            list.push({
                kind: "window",
                key: w.addr,
                value: w.handle,
                title: title,
                detail: cls || "Unknown application",
                badge: ws ? "WS " + ws.name : "",
                live: ws ? visibleWs[ws.id] === true : false,
                source: tl && tl.wayland ? tl.wayland : null,
                icon: iconFor(cls),
                order: n
            })
        }
        list.sort(function(a, b) { return (b.live - a.live) || (a.order - b.order) })
        return list
    }

    // The selection follows the source itself (output name / window
    // address), so it stays put when titles change or the list is filtered.
    property string pickScreen: Quickshell.env("YAKUSHI_PICK_SCREEN") || ""
    property string pickWindow: ""

    function indexOf(list, key) {
        for (var i = 0; i < list.length; i++)
            if (list[i].key === key)
                return i
        return list.length > 0 ? 0 : -1
    }

    readonly property int screenIndex: indexOf(screenItems, pickScreen)
    readonly property int windowIndex: indexOf(windowItems, pickWindow)

    readonly property var currentGrid: page === 0 ? screenGrid : page === 1 ? windowGrid : null
    readonly property var currentItem: page === 0 && screenIndex >= 0 ? screenItems[screenIndex]
        : page === 1 && windowIndex >= 0 ? windowItems[windowIndex] : null

    function select(onPage, index) {
        var list = onPage === 0 ? screenItems : windowItems
        if (index < 0 || index >= list.length)
            return
        if (onPage === 0)
            pickScreen = list[index].key
        else
            pickWindow = list[index].key
        (onPage === 0 ? screenGrid : windowGrid).positionViewAtIndex(index, GridView.Contain)
    }

    // arrow keys: one step sideways, one row up or down
    function move(dx, dy) {
        var g = currentGrid
        var list = page === 0 ? screenItems : windowItems
        var at = page === 0 ? screenIndex : windowIndex
        if (!g || list.length === 0)
            return
        var cols = Math.max(1, Math.floor(g.width / g.cellWidth))
        var next = at + dx + dy * cols
        if (dy !== 0 && (next < 0 || next >= list.length))
            return
        select(page, Math.max(0, Math.min(list.length - 1, next)))
    }
    readonly property bool canShare: page === 2 || currentItem !== null

    // ------------------------------------------------------------------
    // Result
    // ------------------------------------------------------------------
    FileView {
        id: result

        path: picker.outPath
        blockWrites: true
        printErrors: false
    }

    function finish(kind, value) {
        if (done)
            return
        done = true
        var line = "[SELECTION]" + (reuse ? "r" : "") + "/" + kind + ":" + value
        if (outPath !== "")
            result.setText(line + "\n")
        else
            console.log(line)
        close()
    }

    function share() {
        if (page === 2)
            pickRegion()
        else if (currentItem && (currentItem.kind === "screen" || currentItem.value !== ""))
            finish(currentItem.kind, currentItem.value)
    }

    function close() {
        showing = false
        quitTimer.restart()
    }

    function setPage(n) {
        page = (n + pages.length) % pages.length
        if (page === 1)
            search.forceActiveFocus()
        else
            outside.forceActiveFocus()
    }

    // ---- region: hide, let slurp take the screen, come back if cancelled
    property bool regionActive: false

    function pickRegion() {
        regionActive = true
        slurpDelay.restart()
    }

    Timer {
        id: slurpDelay
        interval: Theme.tMid + 60
        onTriggered: slurp.running = true
    }

    Process {
        id: slurp

        command: ["slurp", "-f", "%o %x %y %w %h"]
        stdout: StdioCollector {
            onStreamFinished: {
                var f = text.trim().split(/\s+/)
                if (f.length === 5) {
                    for (var i = 0; i < Quickshell.screens.length; i++) {
                        var s = Quickshell.screens[i]
                        if (s.name === f[0]) {   // slurp gives layout coordinates; xdph wants output-local ones
                            picker.finish("region", f[0] + "@" + (parseInt(f[1]) - s.x) + "," + (parseInt(f[2]) - s.y)
                                          + "," + parseInt(f[3]) + "," + parseInt(f[4]))
                            return
                        }
                    }
                }
                picker.regionActive = false
                outside.forceActiveFocus()
            }
        }
    }

    Timer {
        id: quitTimer
        interval: Theme.tSlow + 160      // the card closes back into its notches first
        onTriggered: Qt.quit()
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
        showing = true
        // YAKUSHI_PICK_PAGE=screens|windows|region opens on that page
        var start = String(Quickshell.env("YAKUSHI_PICK_PAGE") || "").toLowerCase()
        var at = 0
        for (var i = 0; i < pages.length; i++)
            if (pages[i].name.toLowerCase() === start)
                at = i
        Qt.callLater(function() { picker.setPage(at) })
    }

    // ------------------------------------------------------------------
    // Window
    // ------------------------------------------------------------------
    screen: {
        var want = Quickshell.env("YAKUSHI_PICK_SCREEN") || ""
        for (var i = 0; i < Quickshell.screens.length; i++)
            if (Quickshell.screens[i].name === want)
                return Quickshell.screens[i]
        return Quickshell.screens[0]
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "yakushi-share-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: showing && !regionActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    mask: Region {
        item: picker.showing && !picker.regionActive ? outside : null
    }

    ThemeState {
        id: saved
    }


    // A source tile: live preview, number, name, details.
    component SourceTile: Item {
        id: tile

        required property var modelData
        required property int index
        property GridView grid
        property int selected: -1
        readonly property bool here: selected === index

        width: grid.cellWidth
        height: grid.cellHeight

        Rectangle {
            id: box

            anchors.fill: parent
            anchors.rightMargin: 12
            anchors.bottomMargin: 12
            color: tile.here ? Theme.tint(Theme.accent, 0.07)
                : tileMouse.containsMouse ? Theme.tint(Theme.ink, 0.04) : Theme.card
            border.width: 1
            border.color: tile.here ? Theme.accent : tileMouse.containsMouse ? Theme.lineHot : Theme.line

            Behavior on color { ColorAnimation { duration: Theme.tFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.tFast } }

            Rectangle {
                id: shot

                x: 8
                y: 8
                width: parent.width - 16
                height: parent.height - 16 - info.height
                color: "#000000"
                clip: true

                ScreencopyView {
                    id: view

                    readonly property real ratio: sourceSize.width > 0 ? sourceSize.width / sourceSize.height : 16 / 9
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height * ratio)
                    height: Math.min(parent.height, parent.width / ratio)
                    captureSource: tile.modelData.source
                    live: true
                    visible: hasContent
                }

                // nothing to show (yet)
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: !view.hasContent

                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: tile.modelData.icon !== ""
                        source: tile.modelData.icon
                        implicitSize: 40
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: tile.modelData.kind === "window" && tile.modelData.icon === ""
                        text: String.fromCodePoint(0xF05B0)
                        color: Theme.inkSoft
                        font.family: Theme.glyphs
                        font.pixelSize: 34
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "NO PREVIEW"
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                }

                // workspace tag
                Rectangle {
                    visible: tile.modelData.badge !== ""
                    x: 6
                    y: 6
                    width: badgeText.implicitWidth + 12
                    height: 16
                    color: tile.modelData.live ? Theme.accent : Theme.tint("#000000", 0.75)
                    border.width: tile.modelData.live ? 0 : 1
                    border.color: Theme.line

                    Text {
                        id: badgeText

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: tile.modelData.badge
                        color: tile.modelData.live ? picker.onAccent : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }
            }

            Item {
                id: info

                anchors.bottom: parent.bottom
                width: parent.width
                height: 44

                Text {
                    id: num

                    textFormat: Text.PlainText
                    x: 10
                    y: 8
                    text: picker.two(tile.index + 1)
                    color: tile.here ? Theme.accent : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.bold: true
                }

                IconImage {
                    id: appIcon

                    visible: tile.modelData.icon !== ""
                    anchors.left: num.right
                    anchors.leftMargin: 10
                    y: 7
                    source: tile.modelData.icon
                    implicitSize: 14
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: appIcon.visible ? appIcon.right : num.right
                    anchors.leftMargin: appIcon.visible ? 8 : 12
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    y: 7
                    text: tile.modelData.title
                    elide: Text.ElideRight
                    color: tile.here ? Theme.ink : Theme.tint(Theme.ink, 0.86)
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 0.5
                }

                Text {
                    textFormat: Text.PlainText
                    x: 10
                    y: 25
                    width: parent.width - 20
                    text: tile.modelData.detail
                    elide: Text.ElideRight
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 9
                }
            }

            MouseArea {
                id: tileMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.select(picker.page, tile.index)
                onDoubleClicked: {
                    picker.select(picker.page, tile.index)
                    picker.share()
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Outside the card: click or Esc cancels
    // ------------------------------------------------------------------
    Item {
        id: outside

        anchors.fill: parent
        focus: true

        function handleKey(event) {
            var k = event.key
            if (k === Qt.Key_Escape) {
                if (picker.page === 1 && picker.query !== "")
                    search.text = ""
                else
                    picker.close()
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                picker.share()
            } else if (k === Qt.Key_Tab) {
                picker.setPage(picker.page + 1)
            } else if (k === Qt.Key_Backtab) {
                picker.setPage(picker.page - 1)
            } else if (picker.currentGrid && (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down)) {
                picker.move(k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : 0,
                            k === Qt.Key_Up ? -1 : k === Qt.Key_Down ? 1 : 0)
            } else if (!search.activeFocus && k >= Qt.Key_1 && k <= Qt.Key_3) {
                picker.setPage(k - Qt.Key_1)
            } else {
                return false
            }
            return true
        }

        Keys.onPressed: event => { event.accepted = handleKey(event) }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: picker.close()
        }
    }

    // ------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------
    TiltCard {
        id: card

        anchors.centerIn: parent
        width: Math.min(1020, picker.width - 40)
        height: Math.min(660, picker.height - 40)
        shown: picker.showing && !picker.regionActive

        MouseArea {
            anchors.fill: parent
        }

        SakuraPetals {
            anchors.fill: parent
            z: 10
            active: Qt.colorEqual(Theme.accent, "#ff7a9d")
            tint: Theme.accent
        }

        // the card's shape, its corner marks and its opening are TiltCard's
        Item {
            id: frame

            anchors.fill: parent

            // ============ header strip ============
            Item {
                id: strip

                width: parent.width
                height: 46

                Row {
                    x: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "薬"
                        color: Theme.alert
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SHARE SCREEN"
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 6
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "画面共有"
                        color: Theme.inkSoft
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 13
                        font.letterSpacing: 3
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: picker.pages[picker.page].jp
                        color: Theme.inkSoft
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 14
                        color: Theme.tint(Theme.ink, 0.18)
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: picker.two(picker.page + 1) + " / " + picker.two(picker.pages.length)
                        color: Theme.accent
                        font.family: Theme.mono
                        font.pixelSize: 11
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
            }

            // ============ numbered source list ============
            Item {
                id: list

                y: strip.height
                width: 256
                height: parent.height - strip.height

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Theme.tint(Theme.ink, 0.12)
                }

                Column {
                    id: pageList

                    y: 14
                    width: parent.width - 1

                    Repeater {
                        model: picker.pages

                        delegate: Rectangle {
                            id: line

                            required property var modelData
                            required property int index
                            readonly property bool here: picker.page === index
                            readonly property color ink: here ? picker.onAccent : Theme.ink
                            readonly property int count: index === 0 ? picker.screenItems.length
                                : index === 1 ? picker.windowItems.length : -1

                            width: parent.width
                            height: 36
                            color: here ? Theme.accent : lineMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: Theme.tFast }
                            }

                            Rectangle {
                                visible: lineMouse.containsMouse && !line.here
                                width: 3
                                height: parent.height
                                color: Theme.accent
                            }

                            Text {
                                id: number

                                textFormat: Text.PlainText
                                x: 20
                                anchors.verticalCenter: parent.verticalCenter
                                text: picker.two(line.index + 1)
                                color: line.here ? line.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.bold: line.here
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.left: number.right
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: line.modelData.name.toUpperCase()
                                color: line.here || lineMouse.containsMouse ? line.ink : Theme.tint(Theme.ink, 0.78)
                                font.family: Theme.mono
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 1.5
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: line.modelData.jp
                                color: line.here ? Theme.tint(line.ink, 0.8) : Theme.inkSoft
                                font.family: "Noto Sans CJK JP"
                                font.pixelSize: 11
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                id: lineMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.setPage(line.index)
                            }
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    x: 18
                    visible: y >= pageList.y + pageList.height + 8
                    anchors.bottom: listFoot.top
                    anchors.bottomMargin: 10
                    text: "薬\n師"
                    lineHeight: 0.92
                    color: Theme.tint(Theme.ink, 0.09)
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 58
                    font.bold: true
                }

                Item {
                    id: listFoot

                    anchors.bottom: parent.bottom
                    width: parent.width - 1
                    height: 40

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.tint(Theme.ink, 0.12)
                    }

                    Text {
                        textFormat: Text.PlainText
                        x: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ESC ── CANCEL"
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                }
            }

            // ============ the page ============
            Item {
                id: content

                x: list.width + 28
                y: strip.height + 20
                width: parent.width - x - 28
                height: parent.height - y - 16

                PageTitle {
                    id: title

                    width: parent.width
                    title: picker.pages[picker.page].name.toUpperCase()
                }

                Text {
                    id: hint

                    textFormat: Text.PlainText
                    anchors.top: title.bottom
                    anchors.topMargin: 10
                    width: parent.width
                    text: picker.pages[picker.page].hint
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Item {
                    id: body

                    anchors.top: hint.bottom
                    anchors.topMargin: 16
                    anchors.bottom: footer.top
                    anchors.bottomMargin: 12
                    width: parent.width
                    clip: true

                    // ---- 01 screens
                    GridView {
                        id: screenGrid

                        anchors.fill: parent
                        anchors.rightMargin: -12
                        visible: picker.page === 0
                        model: picker.screenItems
                        cellWidth: Math.floor(width / (picker.screenItems.length > 2 ? 3 : 2))
                        cellHeight: Math.round((cellWidth - 12 - 16) * 9 / 16) + 16 + 44 + 12
                        currentIndex: -1
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: SourceTile { grid: screenGrid; selected: picker.screenIndex }
                    }

                    // ---- 02 windows
                    Item {
                        anchors.fill: parent
                        visible: picker.page === 1

                        Rectangle {
                            id: searchBox

                            width: parent.width
                            height: 38
                            color: Theme.card
                            border.width: 1
                            border.color: search.activeFocus ? Theme.accent : Theme.line

                            Text {
                                textFormat: Text.PlainText
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(0xF0349)
                                color: search.activeFocus ? Theme.accent : Theme.inkSoft
                                font.family: Theme.glyphs
                                font.pixelSize: 14
                            }

                            Text {
                                textFormat: Text.PlainText
                                visible: search.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 36
                                text: "Filter by window title or application..."
                                color: Theme.inkMute
                                font.family: Theme.mono
                                font.pixelSize: 10
                            }

                            TextInput {
                                id: search

                                anchors.fill: parent
                                anchors.leftMargin: 36
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.ink
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.surface
                                font.family: Theme.mono
                                font.pixelSize: 10
                                clip: true
                                onTextChanged: picker.query = text
                                Keys.onPressed: event => {
                                    var k = event.key
                                    if (k === Qt.Key_Left || k === Qt.Key_Right)
                                        return          // move the text cursor
                                    event.accepted = outside.handleKey(event)
                                }
                            }
                        }

                        GridView {
                            id: windowGrid

                            anchors.top: searchBox.bottom
                            anchors.topMargin: 14
                            anchors.bottom: parent.bottom
                            width: parent.width + 12
                            model: picker.windowItems
                            cellWidth: Math.floor(width / 3)
                            cellHeight: Math.round((cellWidth - 12 - 16) * 9 / 16) + 16 + 44 + 12
                            currentIndex: -1
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: SourceTile { grid: windowGrid; selected: picker.windowIndex }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: windowGrid
                            visible: picker.windowItems.length === 0
                            text: picker.query !== "" ? "NO MATCHING WINDOWS" : "NO WINDOWS TO SHARE"
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 10
                            font.letterSpacing: 2
                        }
                    }

                    // ---- 03 region: the monitor layout, live
                    Item {
                        id: regionPage

                        anchors.fill: parent
                        visible: picker.page === 2

                        readonly property var bounds: {
                            var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
                            for (var i = 0; i < Quickshell.screens.length; i++) {
                                var s = Quickshell.screens[i]
                                x0 = Math.min(x0, s.x); y0 = Math.min(y0, s.y)
                                x1 = Math.max(x1, s.x + s.width); y1 = Math.max(y1, s.y + s.height)
                            }
                            return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) }
                        }
                        readonly property real k: Math.min((width - 40) / bounds.w, (height - 90) / bounds.h)

                        Item {
                            id: layoutMap

                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            width: regionPage.bounds.w * regionPage.k
                            height: regionPage.bounds.h * regionPage.k

                            Repeater {
                                model: Quickshell.screens

                                delegate: Rectangle {
                                    required property var modelData

                                    x: (modelData.x - regionPage.bounds.x) * regionPage.k
                                    y: (modelData.y - regionPage.bounds.y) * regionPage.k
                                    width: modelData.width * regionPage.k - 6
                                    height: modelData.height * regionPage.k - 6
                                    color: "#000000"
                                    border.width: 1
                                    border.color: Theme.line

                                    ScreencopyView {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        captureSource: picker.page === 2 ? parent.modelData : null
                                        live: true
                                        opacity: 0.55
                                    }

                                    Rectangle {
                                        x: 6
                                        y: 6
                                        width: monName.implicitWidth + 12
                                        height: 16
                                        color: Theme.tint("#000000", 0.75)
                                        border.width: 1
                                        border.color: Theme.line

                                        Text {
                                            id: monName

                                            textFormat: Text.PlainText
                                            anchors.centerIn: parent
                                            text: parent.parent.modelData.name
                                            color: Theme.inkSoft
                                            font.family: Theme.mono
                                            font.pixelSize: 8
                                            font.bold: true
                                            font.letterSpacing: 1
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: layoutMap.bottom
                            anchors.topMargin: 22
                            text: "SELECT REGION, THEN DRAG ON ANY SCREEN  ──  ESC RETURNS HERE"
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }
                    }
                }

                // ============ footer: reuse switch, actions ============
                Item {
                    id: footer

                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 44

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.tint(Theme.ink, 0.12)
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 4
                        spacing: 3

                        Text {
                            textFormat: Text.PlainText
                            text: "REMEMBER THIS CHOICE"
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 1.5
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "The app may share the same source again without asking."
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 9
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 4
                        spacing: 10

                        Switch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: picker.reuse
                            onToggled: picker.reuse = !picker.reuse
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 1
                            height: 18
                            color: Theme.tint(Theme.ink, 0.12)
                        }

                        HeaderButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: String.fromCodePoint(0xF0156)
                            label: "CANCEL"
                            onActivated: picker.close()
                        }

                        Rectangle {
                            id: shareBtn

                            anchors.verticalCenter: parent.verticalCenter
                            width: shareRow.implicitWidth + 28
                            height: 30
                            opacity: picker.canShare ? 1 : 0.4
                            color: shareMouse.containsMouse && picker.canShare ? Theme.tint(Theme.accent, 0.85) : Theme.accent

                            Row {
                                id: shareRow

                                anchors.centerIn: parent
                                spacing: 7

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: picker.page === 2 ? String.fromCodePoint(0xF0489) : String.fromCodePoint(0xF0379)
                                    color: picker.onAccent
                                    font.family: Theme.glyphs
                                    font.pixelSize: 12
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: picker.page === 2 ? "SELECT REGION" : "SHARE"
                                    color: picker.onAccent
                                    font.family: Theme.mono
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1
                                }
                            }

                            MouseArea {
                                id: shareMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: picker.canShare
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.share()
                            }
                        }
                    }
                }
            }
        }
    }
}
