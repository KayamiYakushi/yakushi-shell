import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Programs -> CLEAN UP
//
// SCAN finds what a careful hand clean-up would: leftovers of programs that
// are gone, old backups and copies, broken links, caches, old packages.
// Untick what you want to keep, then CLEAN (twice, as a second look).
// scripts/yakushi-cleanctl.py does the work: your files go to the Yakushi
// trash (REMOVED BEFORE -> UNDO), caches are deleted, package steps ask for
// your password here, in the footer.
Item {
    id: panel

    readonly property string helper: Paths.script("yakushi-cleanctl.py")

    signal cleaned()                     // the Yakushi trash changed (for the count on top)

    property var items: []
    property var groups: []
    property var ticked: ({})            // id -> true
    property bool scanned: false
    property string note: ""
    property bool noteOk: true
    property bool armed: false
    property bool askingPassword: false
    property string secret: ""
    property bool afterClean: false      // the scan after CLEAN keeps CLEAN's message
    readonly property bool working: scanJob.running || cleanJob.running

    readonly property var chosen: items.filter(function(i) { return ticked[i.id] === true })
    readonly property real chosenSize: chosen.reduce(function(s, i) { return s + (i.size || 0) }, 0)
    readonly property bool chosenRoot: chosen.some(function(i) { return i.root })

    function bytes(n) {
        if (n >= 1073741824)
            return (n / 1073741824).toFixed(1) + " GB"
        if (n >= 1048576)
            return (n / 1048576).toFixed(n >= 104857600 ? 0 : 1) + " MB"
        if (n >= 1024)
            return Math.round(n / 1024) + " KB"
        return n > 0 ? n + " B" : ""
    }

    function scan() {
        if (working)
            return
        armed = false
        askingPassword = false
        note = "Looking around…"
        noteOk = true
        scanJob.running = true
    }

    function setTick(id, on) {
        var next = Object.assign({}, ticked)
        if (on)
            next[id] = true
        else
            delete next[id]
        ticked = next
        armed = false
    }

    function tickGroup(key) {
        var members = items.filter(function(i) { return i.group === key })
        var all = members.every(function(i) { return ticked[i.id] === true })
        var next = Object.assign({}, ticked)
        members.forEach(function(i) {
            if (all)
                delete next[i.id]
            else
                next[i.id] = true
        })
        ticked = next
        armed = false
    }

    // headers and items in one list
    readonly property var rows: {
        var out = []
        for (var g = 0; g < groups.length; g++) {
            var key = groups[g].key
            var members = items.filter(function(i) { return i.group === key })
            if (members.length === 0)
                continue
            var size = members.reduce(function(s, i) { return s + (i.size || 0) }, 0)
            out.push({ header: true, key: key, title: groups[g].title, note: groups[g].note, size: size,
                       count: members.length })
            for (var k = 0; k < members.length; k++)
                out.push(members[k])
        }
        return out
    }

    function clean() {
        if (working || chosen.length === 0)
            return
        if (!armed) {
            armed = true
            return
        }
        armed = false
        if (chosenRoot) {
            askingPassword = true
            passwordRow.error = ""
            Qt.callLater(passwordRow.open)
            return
        }
        start("")
    }

    function start(pw) {
        askingPassword = false
        note = "Cleaning…"
        noteOk = true
        secret = pw
        cleanJob.stdinEnabled = pw !== ""
        cleanJob.command = ["python3", helper].concat(pw !== "" ? ["--password-stdin"] : [])
            .concat(["clean", JSON.stringify({ ids: chosen.map(function(i) { return i.id }) })])
        cleanJob.running = true
    }

    function parse(text) {
        try {
            return JSON.parse(text)
        } catch (e) {
            return { ok: false, message: "No answer from the clean-up helper." }
        }
    }

    Process {
        id: scanJob

        command: ["python3", panel.helper, "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.ok === false) {
                    panel.note = d.message || ""
                    panel.noteOk = false
                    return
                }
                panel.groups = d.groups || []
                panel.items = d.items || []
                var next = {}
                panel.items.forEach(function(i) { if (i.checked) next[i.id] = true })
                panel.ticked = next
                panel.scanned = true
                if (!panel.afterClean) {
                    panel.note = panel.items.length === 0 ? "Nothing to clean. Everything is tidy." : ""
                    panel.noteOk = true
                }
                panel.afterClean = false
            }
        }
    }

    Process {
        id: cleanJob

        onStarted: {
            if (stdinEnabled) {
                write(panel.secret + "\n")
                panel.secret = ""
                stdinEnabled = false          // closes its stdin
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.wrongPassword) {
                    panel.askingPassword = true
                    passwordRow.error = "Wrong password. Try again."
                    Qt.callLater(passwordRow.open)
                    panel.note = ""
                    return
                }
                panel.note = d.message || ""
                panel.noteOk = d.ok !== false
                if (d.ok !== false) {
                    panel.cleaned()
                    panel.afterClean = true
                    scanJob.running = true        // what is left
                }
            }
        }
    }

    // ---- intro + SCAN
    Item {
        id: top

        width: parent.width
        height: 40

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: scanButton.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: panel.scanned
                ? "Untick what you want to keep. Your files go to the Yakushi trash (REMOVED BEFORE -> UNDO); caches are deleted."
                : "SCAN looks for leftovers of removed programs, old backups and copies, broken links, caches and old packages. Nothing changes until you press CLEAN."
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
        }

        HeaderButton {
            id: scanButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: scanJob.running ? "SCANNING…" : panel.scanned ? "SCAN AGAIN" : "SCAN"
            icon: String.fromCodePoint(0xF0349)
            onActivated: panel.scan()
        }
    }

    // ---- what was found
    ListView {
        id: list

        anchors.top: top.bottom
        anchors.topMargin: 14
        anchors.bottom: foot.top
        anchors.bottomMargin: 6
        width: parent.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: panel.rows
        opacity: cleanJob.running ? 0.4 : 1

        delegate: Loader {
            required property var modelData

            width: list.width
            sourceComponent: modelData.header ? headerRow : itemRow
        }
    }

    ScrollHint {
        flick: list
    }

    Component {
        id: headerRow

        Item {
            readonly property var row: parent ? parent.modelData : ({})
            readonly property bool all: panel.items.filter(function(i) { return i.group === row.key })
                .every(function(i) { return panel.ticked[i.id] === true })

            width: list.width
            height: 40

            Text {
                id: groupTitle

                textFormat: Text.PlainText
                x: 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: parent.row.title || ""
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: groupTitle.right
                anchors.leftMargin: 10
                anchors.baseline: groupTitle.baseline
                text: (parent.row.count || 0) + (parent.row.note ? "  ·  " + parent.row.note : "")
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
            }

            Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.baseline: groupTitle.baseline
                text: (groupMouse.containsMouse ? (parent.all ? "UNTICK ALL" : "TICK ALL") : panel.bytes(parent.row.size || 0))
                color: groupMouse.containsMouse ? Theme.accent : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
                font.letterSpacing: 1
            }

            MouseArea {
                id: groupMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !panel.working
                onClicked: panel.tickGroup(parent.row.key)
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.line
            }
        }
    }

    Component {
        id: itemRow

        Rectangle {
            id: entry

            readonly property var row: parent ? parent.modelData : ({})
            readonly property bool on: panel.ticked[row.id] === true

            width: list.width
            height: 50
            color: on ? Theme.tint(Theme.accent, 0.06)
                : rowMouse.containsMouse ? Theme.tint(Theme.ink, 0.045) : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !panel.working
                onClicked: panel.setTick(entry.row.id, !entry.on)
            }

            Rectangle {
                id: tick

                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                color: entry.on ? Theme.accent : "transparent"
                border.width: 1
                border.color: entry.on ? Theme.accent : rowMouse.containsMouse ? Theme.ink : Theme.lineHot

                Text {
                    textFormat: Text.PlainText
                    visible: entry.on
                    anchors.centerIn: parent
                    text: "✓"
                    color: Theme.surface
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Column {
                anchors.left: tick.right
                anchors.leftMargin: 14
                anchors.right: sizeText.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: (entry.row.root ? String.fromCodePoint(0xF033E) + "  " : "") + (entry.row.path || entry.row.title || "")
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: (entry.row.path ? entry.row.title + "  ·  " : "") + (entry.row.note || "")
                        + (entry.row.kind === "delete" ? "  ·  deleted" : entry.row.kind === "move" ? "  ·  to the Yakushi trash" : "")
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 9
                }
            }

            Text {
                id: sizeText

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: panel.bytes(entry.row.size || 0) + (entry.row.partial && entry.row.size ? "+" : "")
                color: entry.on ? Theme.ink : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 10
            }

            Rectangle {
                anchors.bottom: parent.bottom
                x: 14
                width: parent.width - 28
                height: 1
                color: Theme.tint(Theme.ink, 0.05)
            }
        }
    }

    // ---- footer: what happened / password / CLEAN
    Item {
        id: foot

        anchors.bottom: parent.bottom
        width: parent.width
        height: 68

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.line
            clip: true

            Rectangle {
                id: sweep

                visible: panel.working
                width: parent.width * 0.2
                height: 1
                color: Theme.accent

                NumberAnimation on x {
                    running: sweep.visible && panel.visible
                    from: -sweep.width
                    to: foot.width
                    duration: 1300
                    loops: Animation.Infinite
                }
            }
        }

        PasswordRow {
            id: passwordRow

            visible: panel.askingPassword
            z: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "Your password, for the package steps"
            action: "CLEAN"
            onAccepted: password => panel.start(password)
            onCanceled: {
                panel.askingPassword = false
                panel.note = "Cancelled. Nothing was changed."
                panel.noteOk = true
            }
        }

        Text {
            textFormat: Text.PlainText
            visible: !panel.askingPassword
            anchors.left: parent.left
            anchors.right: cleanButton.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: panel.note !== "" ? panel.note
                : !panel.scanned ? ""
                : panel.chosen.length === 0 ? "Nothing ticked."
                : panel.chosen.length + " ticked  ·  about " + panel.bytes(panel.chosenSize)
                    + (panel.chosenRoot ? "  ·  package steps ask for your password" : "")
            color: panel.noteOk ? Theme.inkSoft : Theme.alert
            font.family: Theme.mono
            font.pixelSize: 10
        }

        HeaderButton {
            id: cleanButton

            visible: !panel.askingPassword && panel.scanned && panel.items.length > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: cleanJob.running ? "CLEANING…" : panel.armed ? "CLICK AGAIN" : "CLEAN"
            icon: String.fromCodePoint(0xF00E2)
            onActivated: panel.clean()
        }
    }
}
