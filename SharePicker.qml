import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

// Screen-share picker for xdg-desktop-portal-hyprland (share-picker.sh is
// its custom_picker_binary). A plain window, drawn like the file manager
// and its file dialog (Settings -> Appearance -> Apps): header bar, sidebar,
// grid, in the same surface, opacity and accent. Previews are live.
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
        { name: "Screens", glyph: String.fromCodePoint(0xF0379) },
        { name: "Windows", glyph: String.fromCodePoint(0xF05AF) },
        { name: "Area",    glyph: String.fromCodePoint(0xF0489) }
    ]

    // The look of the file manager (Settings -> Appearance -> Apps). While
    // GTK apps wear the shell's colours: the same surface at the same
    // opacity, with the sidebar a faint lighter pane, as yakushi-gtkctl.py
    // writes them for Files; Hyprland blurs what shows through (the layer
    // rule in hypr/rules.lua), with the one blur it uses for every window.
    // Otherwise: Adwaita dark, as Files is then.
    readonly property bool likeFiles: Config.apps.colours === true
    readonly property real filesOpacity: {
        var o = Config.apps.filesOpacity
        return typeof o === "number" ? Math.max(0.30, Math.min(1.0, o)) : 1.0
    }
    readonly property color cardFill: likeFiles ? Theme.tint(Theme.surface, filesOpacity) : "#222226"
    readonly property color sideFill: !likeFiles ? "#2e2e32" : filesOpacity < 1.0 ? white(0.03) : Theme.card
    readonly property string sans: "Adwaita Sans"

    function white(alpha) {
        return Qt.rgba(1, 1, 1, alpha)
    }

    // the corner cut Hyprland gives windows, so the picker has their shape
    property real windowCut: Theme.cutLarge

    Process {
        command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var n = JSON.parse(text)["int"]
                    if (typeof n === "number" && n >= 0)
                        picker.windowCut = Math.min(n, 40)
                } catch (e) {
                }
            }
        }
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
        interval: Theme.tFast + 40       // the window fades out first
        onTriggered: Qt.quit()
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
        showing = true
        // YAKUSHI_PICK_PAGE=screens|windows|region opens on that page
        var start = String(Quickshell.env("YAKUSHI_PICK_PAGE") || "").toLowerCase().replace("region", "area")
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


    // ------------------------------------------------------------------
    // Pieces, drawn as GTK draws them in Files and its file dialog
    // (the "soft tiles" of chooser_css in yakushi-gtkctl.py)
    // ------------------------------------------------------------------
    component Label: Text {
        textFormat: Text.PlainText
        color: Theme.ink
        font.family: picker.sans
        font.pixelSize: 14
        elide: Text.ElideRight
    }

    component PlainButton: Rectangle {
        id: button

        property string label: ""
        property bool suggested: false
        signal clicked()

        width: Math.max(86, buttonLabel.implicitWidth + 28)
        height: 34
        radius: 9
        opacity: enabled ? 1 : 0.4
        color: suggested
            ? (buttonMouse.pressed ? Qt.darker(Theme.accent, 1.1) : buttonMouse.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
            : picker.white(buttonMouse.pressed ? 0.24 : buttonMouse.containsMouse ? 0.15 : 0.10)

        Label {
            id: buttonLabel

            anchors.centerIn: parent
            text: button.label
            color: button.suggested ? picker.onAccent : Theme.ink
            font.bold: button.suggested
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            onClicked: button.clicked()
        }
    }

    // A source: live preview, name under it, as a file in the grid of Files.
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
            anchors.fill: parent
            anchors.margins: 4
            radius: 9
            color: tile.here ? Theme.tint(Theme.accent, 0.30)
                : tileMouse.containsMouse ? picker.white(0.07) : "transparent"

            Rectangle {
                id: shot

                x: 10
                y: 10
                width: parent.width - 20
                height: parent.height - 20 - info.height
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

                // nothing to show (yet): the app's icon
                IconImage {
                    anchors.centerIn: parent
                    visible: !view.hasContent && tile.modelData.icon !== ""
                    source: tile.modelData.icon
                    implicitSize: 48
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: !view.hasContent && tile.modelData.icon === ""
                    text: picker.pages[tile.modelData.kind === "window" ? 1 : 0].glyph
                    color: picker.white(0.55)
                    font.family: Theme.glyphs
                    font.pixelSize: 34
                }
            }

            Column {
                id: info

                anchors.top: shot.bottom
                anchors.topMargin: 8
                x: 10
                width: parent.width - 20
                height: 44
                spacing: 2

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.title
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.detail
                    color: picker.white(0.55)
                    font.pixelSize: 12
                }
            }

            MouseArea {
                id: tileMouse

                anchors.fill: parent
                hoverEnabled: true
                onClicked: picker.select(picker.page, tile.index)
                onDoubleClicked: {
                    picker.select(picker.page, tile.index)
                    picker.share()
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Outside the window: click or Esc cancels
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
    // The window: a header bar (Cancel, title, Share), the kinds of source
    // in a sidebar, the sources in a grid. The file dialog's layout.
    // ------------------------------------------------------------------
    Item {
        id: card

        readonly property bool shown: picker.showing && !picker.regionActive

        anchors.centerIn: parent
        width: Math.min(920, picker.width - 40)
        height: Math.min(620, picker.height - 40)
        opacity: shown ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

        MouseArea {
            anchors.fill: parent
        }

        // the shape Hyprland gives every window (decoration:rounding)
        CutBox {
            anchors.fill: parent
            fill: picker.cardFill
            cut: picker.windowCut
        }

        // ============ header bar ============
        Item {
            id: header

            width: parent.width
            height: 50

            PlainButton {
                x: Math.max(8, picker.windowCut)
                anchors.verticalCenter: parent.verticalCenter
                label: "Cancel"
                onClicked: picker.close()
            }

            Label {
                anchors.centerIn: parent
                text: "Share Screen"
                font.bold: true
            }

            PlainButton {
                anchors.right: parent.right
                anchors.rightMargin: Math.max(8, picker.windowCut)
                anchors.verticalCenter: parent.verticalCenter
                label: picker.page === 2 ? "Select Area" : "Share"
                suggested: true
                enabled: picker.canShare
                onClicked: picker.share()
            }
        }

        // ============ sidebar ============
        CutBox {
            id: side

            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            width: 190
            fill: picker.sideFill
            cut: picker.windowCut
            cutTopLeft: false
            cutTopRight: false
            cutBottomRight: false

            Column {
                y: 6
                width: parent.width

                Repeater {
                    model: picker.pages

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool here: picker.page === index

                        width: side.width
                        height: 36

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.topMargin: 1
                            anchors.bottomMargin: 1
                            radius: 6
                            color: row.here ? picker.white(rowMouse.containsMouse ? 0.13 : 0.10)
                                : rowMouse.containsMouse ? picker.white(0.07) : "transparent"

                            Text {
                                textFormat: Text.PlainText
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.glyph
                                color: Theme.ink
                                font.family: Theme.glyphs
                                font.pixelSize: 16
                            }

                            Label {
                                x: 38
                                width: parent.width - x - 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.name
                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: picker.setPage(row.index)
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.left: side.right
            anchors.top: side.top
            anchors.bottom: side.bottom
            width: 1
            color: Theme.tint("#000000", 0.36)
        }

        // ============ sources ============
        Item {
            id: main

            anchors.left: side.right
            anchors.leftMargin: 1
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: parent.bottom

            Item {
                id: body

                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 8
                anchors.bottomMargin: footer.height
                clip: true

                // ---- screens
                GridView {
                    id: screenGrid

                    anchors.fill: parent
                    visible: picker.page === 0
                    model: picker.screenItems
                    cellWidth: Math.floor(width / (picker.screenItems.length > 2 ? 3 : 2))
                    cellHeight: Math.round((cellWidth - 28) * 9 / 16) + 80
                    currentIndex: -1
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: SourceTile { grid: screenGrid; selected: picker.screenIndex }
                }

                // ---- windows
                Item {
                    anchors.fill: parent
                    visible: picker.page === 1

                    Rectangle {
                        id: searchBox

                        x: 4
                        width: parent.width - 8
                        height: 34
                        radius: 9
                        color: picker.white(0.10)
                        border.width: search.activeFocus ? 2 : 0
                        border.color: Theme.tint(Theme.accent, 0.65)

                        Text {
                            textFormat: Text.PlainText
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF0349)
                            color: picker.white(0.7)
                            font.family: Theme.glyphs
                            font.pixelSize: 15
                        }

                        Label {
                            x: 34
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: "Search windows"
                            color: picker.white(0.55)
                        }

                        TextInput {
                            id: search

                            anchors.fill: parent
                            anchors.leftMargin: 34
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            selectionColor: Theme.tint(Theme.accent, 0.45)
                            selectedTextColor: Theme.ink
                            font.family: picker.sans
                            font.pixelSize: 14
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
                        anchors.topMargin: 8
                        anchors.bottom: parent.bottom
                        width: parent.width
                        model: picker.windowItems
                        cellWidth: Math.floor(width / 3)
                        cellHeight: Math.round((cellWidth - 28) * 9 / 16) + 80
                        currentIndex: -1
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: SourceTile { grid: windowGrid; selected: picker.windowIndex }
                    }

                    Label {
                        anchors.centerIn: windowGrid
                        visible: picker.windowItems.length === 0
                        text: picker.query !== "" ? "No matching windows" : "No windows to share"
                        color: picker.white(0.55)
                    }
                }

                // ---- region: the monitor layout, live
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
                    readonly property real k: Math.min((width - 40) / bounds.w, (height - 80) / bounds.h)

                    Item {
                        id: layoutMap

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 14
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

                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: picker.page === 2 ? parent.modelData : null
                                    live: true
                                }
                            }
                        }
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: layoutMap.bottom
                        anchors.topMargin: 18
                        width: Math.min(implicitWidth, parent.width)
                        text: "Choose Select Area, then drag over the part of the screen to share."
                        color: picker.white(0.55)
                    }
                }
            }

            // ---- may the app share this again without asking
            Item {
                id: footer

                anchors.bottom: parent.bottom
                width: parent.width
                height: 46

                Row {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 6
                        color: picker.reuse ? Theme.accent : picker.white(reuseMouse.containsMouse ? 0.15 : 0.10)

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            visible: picker.reuse
                            text: String.fromCodePoint(0xF012C)
                            color: picker.onAccent
                            font.family: Theme.glyphs
                            font.pixelSize: 14
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Let the app share this again without asking"
                    }
                }

                MouseArea {
                    id: reuseMouse

                    anchors.fill: parent
                    anchors.rightMargin: parent.width - 360
                    hoverEnabled: true
                    onClicked: picker.reuse = !picker.reuse
                }
            }
        }
    }
}
