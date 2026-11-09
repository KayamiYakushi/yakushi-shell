import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../"

// The launcher (SUPER + Space) and clipboard history (SUPER + SHIFT + V): one card in
// the Settings shape, opening from its notches like Settings does.
//
//   type          filter
//   Up / Down     move (also Ctrl+P / Ctrl+N, Page Up / Page Down)
//   Enter         open the app / copy the entry
//   Tab           apps <-> clipboard
//   Esc           close (a click outside the card too)
//
// Apps: every desktop entry that wants to be shown, ranked by how well the
// name matches (exact, start, word start, inside, then description,
// keywords and a fuzzy match), with apps you open often a little higher.
// Clipboard: cliphist's history, newest first; an entry is copied back by its
// id, so its text never passes through a shell command.
//
// shell.qml loads this only while it is open.
PanelWindow {
    id: launcher

    property string mode: "apps"         // "apps" | "clipboard"
    property bool showing: false
    property int selected: 0
    property alias query: search.text

    signal dismissed()      // fully closed (after the animation): the shell frees it

    function focusedScreen() {
        var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        var list = Quickshell.screens
        for (var i = 0; i < list.length; i++)
            if (list[i].name === name)
                return list[i]
        return list.length > 0 ? list[0] : null
    }

    screen: focusedScreen()
    Component.onCompleted: screen = focusedScreen()

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yakushi-launcher"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Clipboard history can be turned off (Settings -> Default
    // Apps): then there is no clipboard side at all.
    readonly property bool clipboardOn: Config.launcher.clipboard !== false

    function open(which) {
        closeTimer.stop()
        mode = which === "clipboard" && clipboardOn ? "clipboard" : "apps"
        search.text = ""
        selected = 0
        if (mode === "clipboard")
            clipList.running = true
        else
            countsFile.reload()
        showing = true
        search.forceActiveFocus()
    }

    function hide() {
        if (!showing)
            return
        showing = false
        closeTimer.restart()
    }

    function switchMode() {
        if (clipboardOn)
            open(mode === "apps" ? "clipboard" : "apps")
    }

    // Opening / closing time, Settings -> Appearance -> Launcher (0 = none)
    readonly property int animation: {
        var ms = Config.launcher.animationMs
        return typeof ms === "number" ? Math.max(0, Math.min(1000, Math.round(ms))) : 480
    }

    // Card opacity, Settings -> Appearance -> Launcher; until set there it
    // follows the panel opacity (Glass)
    readonly property real backdropOpacity: {
        var o = Config.launcher.opacity
        return typeof o === "number" ? Math.max(0.3, Math.min(1, o)) : Theme.backdrop.a
    }

    // the card closes back into its notches first
    Timer {
        id: closeTimer
        interval: launcher.animation + 60
        onTriggered: launcher.dismissed()
    }

    // ------------------------------------------------------------------
    // Apps
    // ------------------------------------------------------------------
    property var counts: ({})

    FileView {
        id: countsFile

        path: Paths.stateHome + "/yakushi/launcher.json"
        printErrors: false
        onLoaded: {
            try {
                var data = JSON.parse(text())
                launcher.counts = data && data.counts ? data.counts : {}
            } catch (e) {
                launcher.counts = {}
            }
        }
    }

    function lower(value) {
        return String(value || "").toLowerCase()
    }

    // how well `q` matches an entry; -1 = not at all
    function score(entry, q) {
        var name = lower(entry.name)
        if (q === "")
            return 0
        if (name === q)
            return 1000
        if (name.indexOf(q) === 0)
            return 800
        if ((" " + name).indexOf(" " + q) >= 0 || name.indexOf("-" + q) >= 0)
            return 600
        if (name.indexOf(q) >= 0)
            return 400
        var extra = lower(entry.genericName) + " " + lower(entry.keywords) + " "
            + lower(entry.comment) + " " + lower(entry.categories) + " " + lower(entry.execString)
        if (extra.indexOf(q) >= 0)
            return 250
        // fuzzy: the letters of q in order, fewer gaps = better
        var at = -1, gaps = 0
        for (var i = 0; i < q.length; i++) {
            var next = name.indexOf(q.charAt(i), at + 1)
            if (next < 0)
                return -1
            if (at >= 0)
                gaps += next - at - 1
            at = next
        }
        // letters scattered all over the name are not a match
        if (gaps > q.length * 2)
            return -1
        return Math.max(1, 150 - gaps * 5)
    }

    readonly property var apps: {
        var q = lower(search.text).trim()
        var list = DesktopEntries.applications.values
        var out = []
        for (var i = 0; i < list.length; i++) {
            var entry = list[i]
            if (entry.noDisplay)
                continue
            var s = score(entry, q)
            if (s < 0)
                continue
            // how often it was opened, on a log scale: the real order holds
            // (296 opens > 214), yet while typing it never outweighs a better
            // name match (at most ~90 against steps of 150+)
            var used = Math.log(1 + (launcher.counts[entry.id] || 0))
            out.push({ entry: entry, rank: s + used * (q === "" ? 60 : 15) })
        }
        out.sort(function(a, b) {
            return b.rank - a.rank || lower(a.entry.name).localeCompare(lower(b.entry.name))
        })
        return out.slice(0, 60)
    }

    // Apps start without the shell's allocator setting (bin/yakushi sets
    // MALLOC_CONF for Quickshell only); otherwise as entry.execute() would.
    Process {
        id: appStarter

        environment: ({ MALLOC_CONF: null })
    }

    function launch(entry) {
        if (entry.runInTerminal) {
            appStarter.command = ["python3", Paths.script("yakushi-launchctl.py"), "terminal", entry.execString]
            appStarter.workingDirectory = ""
        } else {
            appStarter.command = entry.command
            appStarter.workingDirectory = entry.workingDirectory
        }
        appStarter.startDetached()
        Quickshell.execDetached(["python3", Paths.script("yakushi-launchctl.py"), "used", entry.id])
        hide()
    }

    // ------------------------------------------------------------------
    // Clipboard
    // ------------------------------------------------------------------
    property var clips: []

    Process {
        id: clipList

        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = text.split("\n")
                for (var i = 0; i < lines.length && out.length < 400; i++) {
                    var tab = lines[i].indexOf("\t")
                    if (tab <= 0)
                        continue
                    var id = lines[i].slice(0, tab)
                    if (!/^[0-9]+$/.test(id))
                        continue
                    out.push({ id: id, text: lines[i].slice(tab + 1) })
                }
                launcher.clips = out
            }
        }
    }

    readonly property var clipResults: {
        var q = lower(search.text).trim()
        if (q === "")
            return clips
        return clips.filter(function(c) { return lower(c.text).indexOf(q) >= 0 })
    }

    function copy(clip) {
        // the id goes in as an argument, never as shell code
        Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", clip.id])
        hide()
    }

    // ------------------------------------------------------------------
    readonly property int count: mode === "apps" ? apps.length : clipResults.length

    onCountChanged: selected = Math.max(0, Math.min(selected, count - 1))

    function move(step) {
        if (count === 0)
            return
        selected = Math.max(0, Math.min(count - 1, selected + step))
        results.positionViewAtIndex(selected, ListView.Contain)
    }

    function choose(index) {
        if (index < 0 || index >= count)
            return
        if (mode === "apps")
            launch(apps[index].entry)
        else
            copy(clipResults[index])
    }

    // a click outside the card closes
    MouseArea {
        anchors.fill: parent
        onClicked: launcher.hide()
    }

    // ------------------------------------------------------------------
    // The card: a search line and the list, nothing else. Big, calm type;
    // the chosen row is marked by an accent bar, and only it shows what
    // the app is.
    // ------------------------------------------------------------------
    readonly property int pad: 28

    TiltCard {
        id: card

        anchors.centerIn: parent
        width: Math.min(460, launcher.width - 40)
        height: Math.min(490, launcher.height - 40)
        leanDegrees: 2
        duration: launcher.animation
        fill: Qt.rgba(Theme.backdrop.r, Theme.backdrop.g, Theme.backdrop.b, launcher.backdropOpacity)
        shown: launcher.showing

        // clicks on the card stay on the card
        MouseArea {
            anchors.fill: parent
        }

        // ---- search line
        Item {
            id: field

            x: launcher.pad
            y: 26
            width: parent.width - 2 * launcher.pad
            height: 46

            Text {
                id: glyph

                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(launcher.mode === "apps" ? 0xF0349 : 0xF0147)
                color: Theme.accent
                font.family: Theme.glyphs
                font.pixelSize: 18
            }

            TextInput {
                id: search

                anchors.left: glyph.right
                anchors.leftMargin: 14
                anchors.right: hint.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.ink
                selectionColor: Theme.tint(Theme.accent, 0.4)
                font.family: Theme.mono
                font.pixelSize: 16
                clip: true
                focus: true

                onTextChanged: {
                    launcher.selected = 0
                    results.positionViewAtBeginning()
                }

                Keys.onPressed: function(event) {
                    var ctrl = event.modifiers & Qt.ControlModifier
                    if (event.key === Qt.Key_Escape) {
                        launcher.hide()
                    } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
                        launcher.move(1)
                    } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
                        launcher.move(-1)
                    } else if (event.key === Qt.Key_PageDown) {
                        launcher.move(6)
                    } else if (event.key === Qt.Key_PageUp) {
                        launcher.move(-6)
                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        launcher.switchMode()
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        launcher.choose(launcher.selected)
                    } else {
                        return
                    }
                    event.accepted = true
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text === ""
                    text: launcher.mode === "apps" ? "Search apps" : "Search the clipboard"
                    color: Theme.inkMute
                    font: search.font
                }
            }

            // the one hint: Tab switches over
            Text {
                id: hint

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: launcher.clipboardOn
                text: "Tab  " + (launcher.mode === "apps" ? "Clipboard" : "Apps")
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 11
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: search.text !== "" ? Theme.tint(Theme.accent, 0.6) : Theme.line

                Behavior on color {
                    ColorAnimation { duration: Theme.tFast }
                }
            }
        }

        // ---- list
        ListView {
            id: results

            x: launcher.pad - 8
            anchors.top: field.bottom
            anchors.topMargin: 20
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 26
            width: parent.width - 2 * launcher.pad + 16
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: launcher.mode === "apps" ? launcher.apps : launcher.clipResults
            currentIndex: launcher.selected

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool here: index === launcher.selected
                readonly property var entry: launcher.mode === "apps" ? modelData.entry : null

                width: results.width
                height: launcher.mode === "apps" ? 46 : 40

                Rectangle {
                    anchors.fill: parent
                    color: row.here ? Theme.tint(Theme.accent, 0.13)
                        : rowMouse.containsMouse ? Theme.tint(Theme.ink, 0.04) : "transparent"
                }

                // the chosen row's mark
                Rectangle {
                    visible: row.here
                    width: 3
                    height: parent.height
                    color: Theme.accent
                }

                Image {
                    id: icon

                    visible: launcher.mode === "apps" && status === Image.Ready
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: row.entry && row.entry.icon !== ""
                        ? (row.entry.icon.charAt(0) === "/" ? "file://" + row.entry.icon : Quickshell.iconPath(row.entry.icon, true))
                        : ""
                }

                Text {
                    id: rowName

                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: launcher.mode === "apps" ? 54 : 16
                    anchors.verticalCenter: parent.verticalCenter
                    // the name comes first; the description only gets what is left
                    width: Math.min(implicitWidth, parent.width - anchors.leftMargin - 16)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: row.entry ? row.entry.name : String(row.modelData.text).replace(/\s+/g, " ")
                    color: row.here ? Theme.ink : (launcher.mode === "apps" ? Theme.ink : Theme.inkSoft)
                    font.family: Theme.mono
                    font.pixelSize: launcher.mode === "apps" ? 14 : 13
                }

                // what the app is: only on the chosen row
                Text {
                    id: rowWhat

                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real room: parent.width - rowName.x - rowName.width - 16 - 16
                    width: Math.min(implicitWidth, room)
                    visible: row.here && row.entry !== null && text !== "" && room >= 70
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: row.entry ? (row.entry.genericName || row.entry.comment || "") : ""
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcher.choose(row.index)
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: launcher.count === 0
                text: launcher.mode === "apps" ? "No app matches" : (launcher.clips.length === 0 ? "The clipboard is empty" : "Nothing matches")
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 13
            }
        }
    }
}
