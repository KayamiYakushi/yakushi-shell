import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Security, a group of four tabs on this one file (they share
// what the page has read, so changing tab reads nothing again). Nothing
// runs in the background for it: it asks scripts/yakushi-securityctl.py
// once when it opens (and once at login), and only what you press after that.
//
// On top of every tab stands the watch, in one line: a seal with the
// decision (守 secure, 警 alert), the wall (one stone for each of the eight
// protections) and three sentries (guard, apps, scan). Each part opens its
// tab; a stone opens its own protection.
//
//   SHIELD    firewall, what listens to your network, SSH server, updates and
//             known security holes, auto lock, hardening (kernel and network
//             settings), disk encryption, Secure Boot
//   GUARD     what changed in the places an intruder would use to stay, and
//             failed password attempts, sudo use, SSH logins
//   APPS      what each Flatpak app reaches outside its sandbox; a click cuts
//             one thing or gives it back (your own override, no password)
//   SCAN      every system file compared with its package, and programs
//             with root rights that no package installed (on demand)
//
// Your password, when needed, is asked inside the page (PasswordRow) and goes
// to sudo through a pipe. UPDATE runs pacman -Syu right here with its progress;
// pacman runs on its own, so closing Settings never stops it halfway (opened
// again, the page picks the update up where it is).
Item {
    id: page

    property var hostWindow: null

    // the open tab: 0 shield, 1 guard, 2 apps, 3 scan
    readonly property int tab: hostWindow ? hostWindow.tab : 0

    onTabChanged: scroll.contentY = 0

    function openTab(index) {
        if (hostWindow)
            hostWindow.tab = index
    }

    // a stone of the wall: its protection, on the shield tab
    function openProtection(title) {
        openTab(0)
        Qt.callLater(function() {
            var hit = page.hostWindow ? page.hostWindow.findText(page, [title]) : null
            if (hit)
                page.hostWindow.reveal(hit)
        })
    }

    readonly property string home: Paths.home
    readonly property string helper: Paths.script("yakushi-securityctl.py")

    property var st: null                // the last `status`
    readonly property var fw: st ? st.firewall : null
    readonly property var upd: st ? st.updates : null
    readonly property var guard: st ? st.guard : null
    readonly property var events: guard && guard.events ? guard.events : ({})
    readonly property var scan: st ? st.scan : null
    readonly property var lock: st ? st.autolock : null
    readonly property var hard: st && st.hardening ? st.hardening : null
    readonly property var apps: st && st.apps ? st.apps : []
    property string permHint: ""         // what the thing under the pointer means
    readonly property var hardWeak: hard ? hard.items.filter(function(i) { return !i.ok }) : []

    // ---- one short line under the header
    property string note: ""
    property bool noteOk: true

    function say(text, ok) {
        note = text
        noteOk = ok !== false
    }

    // ---- reading
    property bool readAgain: false        // asked while a read was running

    function refresh() {
        if (statusProc.running) {
            readAgain = true
            return
        }
        statusProc.running = true
    }

    function refreshAll() {
        if (!guardProc.running)
            guardProc.running = true
        refresh()
    }

    Component.onCompleted: {
        // the status shows at once (0.1 s); the guard check (under a
        // second) runs beside it, and the status is read again after it
        refreshAll()
    }

    Process {
        id: guardProc
        command: ["python3", page.helper, "guard"]
        onExited: page.refresh()
    }

    Process {
        id: statusProc
        command: ["python3", page.helper, "status"]
        onExited: {
            if (page.readAgain) {
                page.readAgain = false
                Qt.callLater(function() { statusProc.running = true })
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (d.ok) {
                        page.st = d
                        // an update started earlier still runs: show it again
                        if (d.upgrading && !upgrader.running)
                            page.followUpgrade()
                    }
                    else
                        page.say(d.message || "Could not read the status.", false)
                } catch (e) {
                    page.say("No answer from the helper.", false)
                }
            }
        }
    }

    // ---- doing
    readonly property bool busy: action.running || upgrader.running
    property string busyText: ""
    property var pendingArgs: []          // waiting for your password
    property string pendingLabel: ""
    property string pendingButton: ""
    property string secret: ""
    property var lastArgs: []
    property string armed: ""             // a risky button waiting for its second click

    Timer {
        id: disarm
        interval: 4000
        onTriggered: page.armed = ""
    }

    function confirm(key) {
        if (armed === key)
            return true
        armed = key
        disarm.restart()
        return false
    }

    function ask(args, label, button) {
        if (busy)
            return
        pendingArgs = args
        pendingLabel = label
        pendingButton = button
        passwordAsk.error = ""
        Qt.callLater(passwordAsk.open)
    }

    function run(args, pw, text) {
        if (action.running)
            return
        armed = ""
        busyText = text || "Working…"
        note = ""
        secret = pw
        lastArgs = args
        action.stdinEnabled = pw !== ""
        action.command = ["python3", helper].concat(pw !== "" ? ["--password-stdin"] : []).concat(args)
        action.running = true
    }

    Process {
        id: action

        onStarted: {
            if (stdinEnabled) {
                action.write(page.secret + "\n")
                page.secret = ""
                stdinEnabled = false
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                page.busyText = ""
                try {
                    var d = JSON.parse(text)
                    if (d.wrongPassword) {
                        page.pendingArgs = page.lastArgs
                        passwordAsk.error = "Wrong password. Try again."
                        Qt.callLater(passwordAsk.open)
                        return
                    }
                    if (d.message)
                        page.say(d.message, d.ok !== false)
                } catch (e) {
                    page.say("No answer from the helper.", false)
                }
                page.refresh()
            }
        }
    }

    // ---- UPDATE, right here: pacman -Syu with its progress
    property var up: null                 // { phase, n, total, line } while it runs
    property var upLines: []              // the last few lines pacman wrote
    property var upResult: null           // { ok, message, terminal } when it ended
    property string upSecret: ""

    function startUpgrade(pw) {
        if (busy)
            return
        armed = ""
        note = ""
        upResult = null
        upLines = []
        up = { phase: "Starting", n: 0, total: 0, line: "" }
        upSecret = pw
        upgrader.stdinEnabled = true
        upgrader.command = ["python3", helper, "--password-stdin", "upgrade"]
        upgrader.running = true
    }

    function followUpgrade() {
        upResult = null
        upLines = []
        up = { phase: "Updating", n: 0, total: 0, line: "" }
        upgrader.stdinEnabled = false
        upgrader.command = ["python3", helper, "follow"]
        upgrader.running = true
    }

    Process {
        id: upgrader

        onStarted: {
            if (stdinEnabled) {
                upgrader.write(page.upSecret + "\n")
                page.upSecret = ""
                stdinEnabled = false
            }
        }

        stdout: SplitParser {
            onRead: function(data) {
                var d
                try {
                    d = JSON.parse(data)
                } catch (e) {
                    return
                }
                if (d.done) {
                    page.up = null
                    if (d.wrongPassword) {
                        page.upLines = []
                        page.ask(["upgrade"], "Your password, to update the system", "UPDATE")
                        passwordAsk.error = "Wrong password. Try again."
                        return
                    }
                    page.upResult = d
                    page.say(d.message || "", d.ok !== false)
                    page.refresh()
                    return
                }
                page.up = d
                if (d.line) {
                    var l = page.upLines.slice(-4)
                    l.push(d.line)
                    page.upLines = l
                }
            }
        }

        onExited: {
            if (page.up !== null) {          // it stopped without a last word
                page.up = null
                page.refresh()
            }
        }
    }

    // when pacman needs a decision from you: the same update in your terminal
    Process {
        id: terminal
        command: ["python3", Paths.script("yakushi-launchctl.py"), "terminal",
                  "sh -c 'sudo pacman -Syu; echo; printf \"Done. Press Enter to close.\"; read x'", "--wait"]
        onExited: page.run(["updates"], "", "Checking again for updates…")
    }

    // ---- words
    function ago(t) {
        if (!t)
            return "never"
        var s = Math.max(0, Math.floor(Date.now() / 1000) - t)
        if (s < 90)
            return "just now"
        if (s < 5400)
            return Math.round(s / 60) + " min ago"
        if (s < 129600)
            return Math.round(s / 3600) + " h ago"
        return Math.round(s / 86400) + " days ago"
    }

    function clock(t) {
        var d = new Date(t * 1000)
        return Qt.formatDateTime(d, "dd MMM hh:mm")
    }

    readonly property var holesFixed: upd && upd.holes ? upd.holes.filter(function(h) { return h.fix !== "" }) : []
    readonly property int pendingCount: upd && upd.pending ? upd.pending.length : 0
    readonly property var reachable: st ? st.listening : []

    // one line per program: "spotify   TCP 51885, 57621 · UDP 1900, 5353"
    readonly property var listeners: {
        var by = {}
        var order = []
        for (var i = 0; i < reachable.length; i++) {
            var r = reachable[i]
            var who = r.program !== "" ? r.program : "system services"
            if (!by[who]) {
                by[who] = { who: who, tcp: [], udp: [] }
                order.push(who)
            }
            var list = r.proto === "tcp" ? by[who].tcp : by[who].udp
            if (list.indexOf(r.port) < 0)
                list.push(r.port)
        }
        return order.map(function(w) { return by[w] })
    }

    // ------------------------------------------------------------------
    // The overview: how the shield checks stand, and what needs you
    // ------------------------------------------------------------------
    readonly property string fwMood: fw === null ? "info" : fw.on ? "good" : "bad"
    readonly property string netMood: listeners.length === 0 || (fw && fw.on) ? "good" : "bad"
    readonly property string sshMood: st === null ? "info" : st.ssh.active || st.ssh.enabled ? "bad" : "good"
    readonly property string updMood: upd === null ? "info" : holesFixed.length > 0 ? "bad" : pendingCount > 0 ? "info" : "good"
    readonly property string lockMood: lock === null ? "info" : lock.minutes === "off" ? "bad" : "good"
    readonly property string hardMood: hard === null ? "info" : hard.weak > 0 ? "bad" : "good"
    readonly property string encMood: st === null || !st.encryption.known ? "info" : st.encryption.on ? "good" : "info"
    readonly property string bootMood: st === null || !st.secureBoot.known ? "info" : st.secureBoot.on ? "good" : "info"
    readonly property var moods: [fwMood, netMood, sshMood, updMood, lockMood, hardMood, encMood, bootMood]
    readonly property int goodCount: moods.filter(function(m) { return m === "good" }).length
    readonly property int badCount: moods.filter(function(m) { return m === "bad" }).length

    readonly property int changeCount: guard && guard.changes ? guard.changes.length : 0
    readonly property int failedCount: (events.failed || []).length
    readonly property int sudoCount: (events.sudo || []).length
    readonly property int sshCount: (events.ssh || []).length
    readonly property int scanSuid: scan && scan.suid ? scan.suid.length : 0
    readonly property int scanRed: (scan ? scan.redCount : 0) + scanSuid
    // ---- the watch
    // The wall: the eight protections in the shield tab's order.
    readonly property var stones: [
        { k: "FIREWALL", title: "Firewall", mood: fwMood, say: fw === null ? "…" : fw.on ? "on" : "off" },
        { k: "NETWORK", title: "Open to network", mood: netMood,
          say: listeners.length === 0 ? "nothing listens" : listeners.length + " listening, " + (fw && fw.on ? "firewalled" : "open") },
        { k: "SSH", title: "SSH server", mood: sshMood, say: st === null ? "…" : st.ssh.active ? "on" : st.ssh.enabled ? "starts at boot" : "off" },
        { k: "UPDATES", title: "Updates", mood: updMood,
          say: upd === null ? "not checked yet" : holesFixed.length > 0 ? holesFixed.length + " fix security holes"
             : pendingCount === 0 ? "up to date" : pendingCount + " waiting" },
        { k: "LOCK", title: "Auto lock", mood: lockMood, say: lock === null ? "…" : lock.minutes === "off" ? "off" : "after " + lock.minutes + " min" },
        { k: "HARDEN", title: "Hardening", mood: hardMood,
          say: hard === null ? "…" : hard.weak === 0 ? "all " + hard.total + " settings safe" : hard.weak + " of " + hard.total + " weak" },
        { k: "DISK", title: "Disk encryption", mood: encMood,
          say: st === null || !st.encryption.known ? "unknown" : st.encryption.on ? "encrypted" : "not encrypted" },
        { k: "BOOT", title: "Secure Boot", mood: bootMood,
          say: st === null || !st.secureBoot.known ? "unknown" : st.secureBoot.on ? "on" : "off" }
    ]
    property int stoneAt: -1              // the stone under the pointer

    // One or two wrong passwords here are typos; three, or any from the
    // network, are not.
    readonly property int remoteFailed: (events.failed || []).filter(function(f) { return f.remote === true }).length
    readonly property bool guardAlert: changeCount > 0 || sshCount > 0 || remoteFailed > 0 || failedCount >= 3
    readonly property bool alarm: badCount > 0 || guardAlert || scanRed > 0
    readonly property int alertThings: badCount + scanRed + (guardAlert ? changeCount + failedCount + sshCount : 0)
    readonly property int reviewThings: guardAlert ? 0 : failedCount

    function moodColor(m) {
        return m === "good" ? Theme.good : m === "bad" ? Theme.alert : Theme.inkMute
    }

    property bool showAllLog: false

    // the login log, newest first, in one list
    readonly property var logRows: {
        var rows = []
        var f = events.failed || [], r = events.ssh || [], s = events.sudo || []
        for (var i = 0; i < f.length; i++)
            rows.push({ time: f[i].time, kind: f[i].remote ? "SSH FAIL" : "WRONG", text: f[i].text, hot: true })
        for (var j = 0; j < r.length; j++)
            rows.push({ time: r[j].time, kind: "SSH", text: r[j].text, hot: true })
        for (var k = 0; k < s.length; k++)
            rows.push({ time: s[k].time, kind: "SUDO", text: s[k].text, hot: false })
        rows.sort(function(a, b) { return b.time - a.time })
        return rows
    }

    // ------------------------------------------------------------------
    // Pieces
    // ------------------------------------------------------------------
    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool on: false
        property var host: null

        signal picked()

        width: chipText.implicitWidth + 22
        height: 32
        opacity: host && host.busy ? 0.5 : 1
        color: on ? Theme.tint(Theme.accent, 0.14)
            : chipMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : "transparent"
        border.width: 1
        border.color: on ? Theme.accent : chipMouse.containsMouse ? Theme.lineHot : Theme.line

        Text {
            id: chipText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
            font.bold: chip.on
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: !(chip.host && chip.host.busy)
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    component Button: Rectangle {
        id: btn

        property string key: ""
        property string label: ""
        property bool danger: false
        property var host: null
        readonly property bool armedHere: host !== null && key !== "" && host.armed === key

        signal pressed()

        width: btnText.implicitWidth + 28
        height: 34
        opacity: host && host.busy ? 0.5 : 1
        color: armedHere ? Theme.tint(Theme.alert, 0.3)
            : danger ? (btnMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
            : Theme.tint(Theme.accent, btnMouse.containsMouse ? 0.24 : 0.1)
        border.width: 1
        border.color: danger || armedHere ? Theme.alert : Theme.tint(Theme.accent, 0.6)

        Text {
            id: btnText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: btn.armedHere ? "CLICK AGAIN" : btn.label
            color: btn.danger || btn.armedHere ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        MouseArea {
            id: btnMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: !(btn.host && btn.host.busy)
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.pressed()
        }
    }

    // a section title: a mark, the name, a note on the right, a rule
    component SectionHead: Item {
        property string glyph: ""
        property string label: ""
        property string side: ""
        property bool lead: false        // the first on its tab: no gap above it

        width: parent ? parent.width : 0
        height: lead ? 34 : 64

        Text {
            id: headGlyph

            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 13
            text: parent.glyph
            color: Theme.accent
            font.family: Theme.glyphs
            font.pixelSize: 15
        }

        Text {
            id: headText

            textFormat: Text.PlainText
            anchors.left: headGlyph.right
            anchors.leftMargin: 10
            anchors.verticalCenter: headGlyph.verticalCenter
            text: parent.label
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 2.5
        }

        Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: headGlyph.verticalCenter
            text: parent.side
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 10
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.line
        }
    }

    // one check: a badge in its colour, the name over what it means, buttons
    component ShieldRow: Item {
        id: sr

        property string glyph: ""
        property string title: ""
        property string text: ""
        property string mood: "info"     // good | bad | info
        default property alias buttons: btnRow.data

        readonly property color tone: mood === "good" ? Theme.good : mood === "bad" ? Theme.alert : Theme.inkMute

        width: parent ? parent.width : 0
        height: Math.max(70, srCol.implicitHeight + 32)

        Rectangle {
            id: badge

            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 38
            color: Theme.tint(sr.tone, 0.1)
            border.width: 1
            border.color: Theme.tint(sr.tone, 0.45)

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: sr.glyph
                color: sr.tone
                font.family: Theme.glyphs
                font.pixelSize: 17
            }
        }

        Column {
            id: srCol

            anchors.left: badge.right
            anchors.leftMargin: 16
            anchors.right: btnRow.left
            anchors.rightMargin: btnRow.width > 0 ? 16 : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: sr.title
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 13
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: sr.text
                wrapMode: Text.WordWrap
                color: sr.mood === "bad" ? Theme.tint(Theme.ink, 0.85) : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 11
                lineHeight: 1.25
            }
        }

        Row {
            id: btnRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
        }

        Rectangle {
            anchors.bottom: parent.bottom
            x: 54
            width: parent.width - 54
            height: 1
            color: Theme.tint(Theme.ink, 0.05)
        }
    }

    // the small boxes under a check (ports, security holes)
    component Tag: Rectangle {
        property string label: ""
        property bool hot: false

        width: tagText.implicitWidth + 14
        height: 20
        color: hot ? Theme.tint(Theme.alert, 0.1) : Theme.tint(Theme.ink, 0.04)
        border.width: 1
        border.color: hot ? Theme.tint(Theme.alert, 0.5) : Theme.line

        Text {
            id: tagText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: parent.label
            color: parent.hot ? Theme.alert : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
        }
    }

    // one thing an app reaches outside its sandbox: a click cuts it, or gives it back
    component Perm: Rectangle {
        id: perm

        property var info: ({})
        property string app: ""
        property var host: null
        readonly property bool on: info.on === true

        width: permText.implicitWidth + 18
        height: 24
        opacity: host && host.busy ? 0.5 : 1
        color: permMouse.containsMouse ? Theme.tint(Theme.ink, 0.08) : on ? Theme.tint(Theme.ink, 0.04) : "transparent"
        border.width: 1
        border.color: permMouse.containsMouse ? Theme.lineHot : on ? Theme.line : Theme.tint(Theme.ink, 0.06)

        Component.onDestruction: if (host && host.permHint === info.hint) host.permHint = ""

        Text {
            id: permText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: perm.info.label || ""
            color: perm.on ? Theme.ink : Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 0.5
            font.strikeout: !perm.on
        }

        MouseArea {
            id: permMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: !(perm.host && perm.host.busy)
            cursorShape: Qt.PointingHandCursor
            onEntered: perm.host.permHint = (perm.on ? "" : "Cut now. ") + perm.info.hint
            onExited: perm.host.permHint = ""
            onClicked: perm.host.run(["app", perm.app, perm.info.id, perm.on ? "off" : "on"], "", "")
        }
    }

    // one of the three sentries: its vote, its name, what it has to say
    component Sentry: Item {
        id: sentry

        property string name: ""
        property string say: ""
        property bool voted: true
        property bool alert: false
        property int opens: 0
        property var host: null
        readonly property bool here: host !== null && host.tab === opens

        width: parent ? parent.width : 0
        height: 26

        Rectangle {
            visible: sentry.here || sentryMouse.containsMouse
            width: 2
            height: parent.height - 8
            anchors.verticalCenter: parent.verticalCenter
            color: sentry.alert ? Theme.alert : Theme.accent
        }

        Text {
            id: sentryVote

            textFormat: Text.PlainText
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: !sentry.voted ? "・" : sentry.alert ? "警" : "守"
            color: !sentry.voted ? Theme.inkMute : sentry.alert ? Theme.alert : Theme.accent
            font.family: "Noto Sans CJK JP"
            font.pixelSize: 13
        }

        Text {
            id: sentryName

            textFormat: Text.PlainText
            x: 32
            width: 50
            anchors.verticalCenter: parent.verticalCenter
            text: sentry.name
            color: sentry.here || sentryMouse.containsMouse ? Theme.ink : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 2
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: sentryName.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: sentry.say
            color: sentry.alert ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 11
        }

        MouseArea {
            id: sentryMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (sentry.host) sentry.host.openTab(sentry.opens)
        }
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------
    Item {
        id: head

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36

        PageTitle {
            anchors.left: parent.left
            anchors.right: headButtons.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            title: "SECURITY"
        }

        Row {
            id: headButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Chip {
                host: page
                label: guardProc.running || statusProc.running ? "CHECKING…" : "CHECK NOW"
                onPicked: {
                    page.say("Checked: " + Qt.formatTime(new Date(), "hh:mm") + ".", true)
                    page.refreshAll()
                }
            }
        }
    }

    // the note, or the password row: only while there is something to say
    Item {
        id: bar

        readonly property bool active: passwordAsk.visible || page.up !== null || page.busyText !== "" || page.note !== ""

        anchors.top: head.bottom
        anchors.topMargin: active ? 16 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: active ? 38 : 0
        clip: true

        Behavior on height {
            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
        }

        PasswordRow {
            id: passwordAsk

            anchors.fill: parent
            visible: page.pendingArgs.length > 0
            label: page.pendingLabel
            action: page.pendingButton
            onAccepted: function(password) {
                var args = page.pendingArgs
                page.pendingArgs = []
                if (args[0] === "upgrade")
                    page.startUpgrade(password)
                else
                    page.run(args, password, page.busyFor(args))
            }
            onCanceled: {
                page.pendingArgs = []
                page.say("Cancelled. Nothing was changed.", true)
            }
        }

        Rectangle {
            visible: !passwordAsk.visible
            anchors.fill: parent
            color: page.note !== "" && !page.noteOk ? Theme.tint(Theme.alert, 0.08) : Theme.tint(Theme.accent, 0.06)
            border.width: 1
            border.color: page.note !== "" && !page.noteOk ? Theme.tint(Theme.alert, 0.5) : Theme.tint(Theme.accent, 0.3)

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: page.up !== null ? "Updating the system: " + page.up.phase.toLowerCase()
                        + (page.up.total > 0 ? " (" + page.up.n + " of " + page.up.total + ")" : "") + "…"
                    : page.busyText !== "" ? page.busyText
                    : page.note
                color: page.note !== "" && !page.noteOk && page.busyText === "" && page.up === null ? Theme.alert : Theme.ink
                font.family: Theme.mono
                font.pixelSize: 11
            }
        }
    }

    function busyFor(args) {
        var k = args[0]
        return k === "scan" ? "Comparing every system file with its package… this takes a few minutes."
            : k === "firewall" ? (args[1] === "on" ? "Turning the firewall on…" : "Turning the firewall off…")
            : k === "ssh" ? "Turning the SSH server off…"
            : k === "app" ? (args[3] === "on" ? "Giving it back…" : "Cutting it…")
            : k === "harden" ? (args[1] === "on" ? "Hardening…" : "Putting the settings back…")
            : k === "autolock" ? "Setting auto lock…"
            : "Working…"
    }

    // ================= the watch: seal, wall, sentries =================
    Item {
        id: watch

        readonly property color tone: page.st === null ? Theme.inkMute : page.alarm ? Theme.alert : Theme.accent
        readonly property int gap: 22

        anchors.top: bar.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        height: 84

        // the seal: the decision
        Item {
            id: seal

            width: 84
            height: parent.height

            CutBox {
                anchors.fill: parent
                fill: Theme.tint(watch.tone, 0.07)
                stroke: Theme.tint(watch.tone, 0.6)
                cut: Theme.cut
                cutTopRight: false
                cutBottomLeft: false
            }

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                text: page.st !== null && page.alarm ? "警" : "守"
                color: watch.tone
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 38
                font.bold: true
            }

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 9
                text: page.st === null ? "LOOKING"
                    : page.alarm ? page.alertThings + (page.alertThings === 1 ? " ALERT" : " ALERTS")
                    : page.reviewThings > 0 ? page.reviewThings + " TO REVIEW" : "SECURE"
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.5
            }
        }

        // seal ── wall ── sentries
        Rectangle {
            x: seal.width + 4
            anchors.verticalCenter: parent.verticalCenter
            width: watch.gap - 8
            height: 4
            color: page.st === null ? Theme.tint(Theme.ink, 0.14) : page.badCount > 0 ? Theme.alert : Theme.tint(Theme.accent, 0.6)
        }

        Rectangle {
            x: wall.x + wall.width + 4
            anchors.verticalCenter: parent.verticalCenter
            width: watch.gap - 8
            height: 4
            color: page.st === null ? Theme.tint(Theme.ink, 0.14)
                 : page.guardAlert || page.scanRed > 0 ? Theme.alert : Theme.tint(Theme.accent, 0.6)
        }

        // the wall: one stone for each protection
        Item {
            id: wall

            readonly property int space: 5
            readonly property real stone: (width - space * (page.stones.length - 1)) / page.stones.length

            x: seal.width + watch.gap
            width: parent.width - x - sentries.width - watch.gap
            height: parent.height

            Text {
                id: wallName

                textFormat: Text.PlainText
                y: 2
                visible: page.stoneAt < 0
                text: "SHIELD"
                color: page.tab === 0 ? Theme.ink : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 2
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: wallName.right
                anchors.leftMargin: 10
                anchors.baseline: wallName.baseline
                visible: page.stoneAt < 0
                text: page.st === null ? "" : page.goodCount + " / " + page.stones.length
                color: page.badCount > 0 ? Theme.alert : Theme.ink
                font.family: Theme.mono
                font.pixelSize: 11
            }

            // when the guard last looked
            Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.baseline: wallName.baseline
                visible: page.stoneAt < 0
                text: page.guard && page.guard.time ? "checked " + page.ago(page.guard.time) : ""
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
            }

            // the stone under the pointer, in words, on the whole line
            Text {
                textFormat: Text.PlainText
                width: parent.width
                anchors.baseline: wallName.baseline
                visible: page.stoneAt >= 0
                elide: Text.ElideRight
                text: page.stoneAt >= 0 ? page.stones[page.stoneAt].title.toUpperCase() + "  ·  " + page.stones[page.stoneAt].say : ""
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1
            }

            Repeater {
                model: page.stones

                delegate: Item {
                    id: stone

                    required property var modelData
                    required property int index
                    readonly property color tone: page.moodColor(modelData.mood)
                    readonly property bool plain: modelData.mood === "info"

                    x: Math.round(index * (wall.stone + wall.space))
                    y: 24
                    width: Math.round(wall.stone)
                    height: wall.height - y

                    CutBox {
                        width: parent.width
                        height: 38
                        cut: 10
                        cutTopLeft: false
                        cutBottomRight: false
                        fill: stone.plain ? Theme.tint(Theme.ink, stoneMouse.containsMouse ? 0.08 : 0.03)
                            : Theme.tint(stone.tone, stoneMouse.containsMouse ? 0.4 : 0.22)
                        stroke: stone.plain ? Theme.tint(Theme.ink, 0.16) : Theme.tint(stone.tone, 0.75)
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        horizontalAlignment: Text.AlignHCenter
                        text: stone.modelData.k
                        color: stone.modelData.mood === "bad" ? Theme.alert : stoneMouse.containsMouse ? Theme.ink : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 8
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 6
                    }

                    MouseArea {
                        id: stoneMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: page.stoneAt = stone.index
                        onExited: if (page.stoneAt === stone.index) page.stoneAt = -1
                        onClicked: page.openProtection(stone.modelData.title)
                    }
                }
            }
        }

        // the sentries: the other three tabs
        Column {
            id: sentries

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(210, Math.round(parent.width * 0.3))
            spacing: 2

            Sentry {
                host: page
                opens: 1
                name: "GUARD"
                voted: page.guard !== null
                alert: page.guardAlert
                say: page.guard === null ? "…"
                    : page.changeCount > 0 ? page.changeCount + (page.changeCount === 1 ? " change" : " changes")
                    : page.sshCount > 0 ? page.sshCount + (page.sshCount === 1 ? " SSH login" : " SSH logins")
                    : page.failedCount > 0 ? page.failedCount + " wrong password" + (page.failedCount === 1 ? "" : "s")
                    : "quiet"
            }

            Sentry {
                host: page
                opens: 2
                name: "APPS"
                voted: false
                say: page.st === null ? "…" : page.apps.length === 0 ? "all boxed in" : page.apps.length + " reach out"
            }

            Sentry {
                host: page
                opens: 3
                name: "SCAN"
                voted: page.scan !== null
                alert: page.scanRed > 0
                say: page.st === null ? "…" : page.scan === null ? "not run yet"
                    : page.scanRed === 0 ? "intact, " + page.ago(page.scan.time) : page.scanRed + " to look at"
            }
        }
    }

    Flickable {
        id: scroll

        anchors.top: watch.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: body.implicitHeight + 24
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body

            width: scroll.width
            spacing: 0

            Column {
                visible: page.tab === 0
                width: parent.width

                // ================= SHIELD =================
                ShieldRow {
                    glyph: String.fromCodePoint(0xF0498)
                    title: "Firewall"
                    mood: page.fwMood
                    text: page.fw ? page.fw.text : "…"

                    Button {
                        host: page
                        visible: page.fw !== null && !page.fw.on
                        label: "TURN ON"
                        onPressed: page.ask(["firewall", "on"], "Your password, to turn the firewall on", "TURN ON")
                    }

                    Button {
                        host: page
                        key: "fwoff"
                        visible: page.fw !== null && page.fw.on && page.fw.tool === "ufw"
                        label: "TURN OFF"
                        danger: true
                        onPressed: if (page.confirm("fwoff")) page.ask(["firewall", "off"], "Your password, to turn the firewall off", "TURN OFF")
                    }
                }

                ShieldRow {
                    glyph: String.fromCodePoint(0xF0317)
                    title: "Open to network"
                    mood: page.netMood
                    text: page.st === null ? "…"
                        : page.listeners.length === 0 ? "Nothing on this computer listens to your network."
                        : page.listeners.length + (page.listeners.length === 1 ? " program listens" : " programs listen")
                          + " to your network." + (page.fw && page.fw.on
                              ? " The firewall keeps them closed unless you allowed them."
                              : " Without a firewall, anyone on your network can try them.")
                }

                // who listens, with their ports
                Column {
                    width: parent.width
                    visible: page.listeners.length > 0
                    leftPadding: 54
                    bottomPadding: 16
                    spacing: 10

                    Repeater {
                        model: page.listeners

                        delegate: Item {
                            id: listener

                            required property var modelData

                            width: body.width - 54
                            height: Math.max(20, portFlow.implicitHeight)

                            Text {
                                id: listenerName

                                textFormat: Text.PlainText
                                width: 150
                                anchors.top: parent.top
                                anchors.topMargin: 2
                                elide: Text.ElideRight
                                text: listener.modelData.who
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }

                            Flow {
                                id: portFlow

                                anchors.left: listenerName.right
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                spacing: 6

                                Repeater {
                                    model: listener.modelData.tcp.map(function(p) { return "TCP " + p })
                                        .concat(listener.modelData.udp.map(function(p) { return "UDP " + p }))

                                    delegate: Tag {
                                        required property var modelData
                                        label: modelData
                                    }
                                }
                            }
                        }
                    }
                }

                ShieldRow {
                    glyph: String.fromCodePoint(0xF018D)
                    title: "SSH server"
                    mood: page.sshMood
                    text: page.st === null ? "…"
                        : page.st.ssh.active ? "On: others can try to log in to this computer over the network."
                        : page.st.ssh.enabled ? "Off now, but it starts at boot."
                        : "Off: nobody can log in to this computer over the network."

                    Button {
                        host: page
                        visible: page.st !== null && (page.st.ssh.active || page.st.ssh.enabled)
                        label: "TURN OFF"
                        danger: true
                        onPressed: page.ask(["ssh", "off"], "Your password, to turn the SSH server off", "TURN OFF")
                    }
                }

                ShieldRow {
                    id: updatesRow

                    glyph: String.fromCodePoint(0xF06B0)
                    title: "Updates"
                    mood: page.updMood
                    text: page.upd === null ? "Not checked yet. CHECK asks the Arch mirrors and the Arch security tracker."
                        : (page.pendingCount === 0 ? "Everything is up to date."
                           : page.pendingCount + (page.pendingCount === 1 ? " update waits" : " updates wait")
                             + (page.holesFixed.length > 0 ? ", " + page.holesFixed.length
                                + (page.holesFixed.length === 1 ? " of them fixes" : " of them fix") + " a known security hole." : "."))
                          + "  Checked " + page.ago(page.upd.time) + "."
                          + (page.upd.errors && page.upd.errors.length ? "  (" + page.upd.errors[0] + ")" : "")

                    Button {
                        host: page
                        label: "CHECK"
                        onPressed: page.run(["updates"], "", "Asking the mirrors and the security tracker…")
                    }

                    Button {
                        host: page
                        visible: page.pendingCount > 0 && page.up === null
                        label: "UPDATE"
                        onPressed: page.ask(["upgrade"], "Your password, to update the system", "UPDATE")
                    }

                    Button {
                        host: page
                        visible: page.up === null && page.upResult !== null && page.upResult.terminal === true
                        label: "OPEN IN TERMINAL"
                        onPressed: terminal.running = true
                    }
                }

                // the update, while it runs (and what went wrong, if it did)
                Item {
                    id: upPanel

                    readonly property bool running: page.up !== null
                    readonly property bool failed: !running && page.upResult !== null && page.upResult.ok === false

                    width: parent.width
                    visible: running || failed
                    height: visible ? upCol.implicitHeight + 28 : 0

                    Rectangle {
                        x: 54
                        y: 6
                        width: parent.width - 54
                        height: parent.height - 14
                        color: Theme.tint(Theme.ink, 0.025)
                        border.width: 1
                        border.color: upPanel.failed ? Theme.tint(Theme.alert, 0.5) : Theme.line
                    }

                    Column {
                        id: upCol

                        x: 70
                        y: 20
                        width: parent.width - 86
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 16
                            visible: upPanel.running

                            Text {
                                textFormat: Text.PlainText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.up ? page.up.phase.toUpperCase() : ""
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.letterSpacing: 2
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.up && page.up.total > 0 ? page.up.n + " / " + page.up.total : ""
                                color: Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                            }
                        }

                        // the bar: steps when pacman counts them, a moving block when it does not
                        Rectangle {
                            id: track

                            visible: upPanel.running
                            width: parent.width
                            height: 4
                            color: Theme.groove
                            clip: true

                            readonly property bool counted: page.up !== null && page.up.total > 0

                            Rectangle {
                                visible: track.counted
                                width: track.counted ? track.width * Math.min(1, page.up.n / page.up.total) : 0
                                height: parent.height
                                color: Theme.accent

                                Behavior on width {
                                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                                }
                            }

                            Rectangle {
                                id: sweep

                                visible: !track.counted
                                width: track.width * 0.22
                                height: parent.height
                                color: Theme.accent

                                NumberAnimation on x {
                                    running: upPanel.running && !track.counted && page.visible
                                    from: -sweep.width
                                    to: track.width
                                    duration: 1300
                                    loops: Animation.Infinite
                                }
                            }
                        }

                        Repeater {
                            model: page.upLines

                            Text {
                                required property var modelData

                                textFormat: Text.PlainText
                                width: upCol.width
                                elide: Text.ElideRight
                                text: modelData
                                color: /^error/.test(modelData) ? Theme.alert : Theme.inkMute
                                font.family: Theme.mono
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            visible: upPanel.running
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "You can close Settings: the update goes on, and this page shows it again when you come back."
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }
                    }
                }

                // known security holes in what is installed
                Column {
                    width: parent.width
                    visible: page.upd !== null && page.upd.holes && page.upd.holes.length > 0
                    leftPadding: 54
                    topPadding: 4
                    bottomPadding: 16
                    spacing: 8

                    Repeater {
                        model: page.upd && page.upd.holes ? page.upd.holes : []

                        delegate: Item {
                            id: hole

                            required property var modelData
                            readonly property bool hot: modelData.fix !== "" && (modelData.risk === "high" || modelData.risk === "critical")

                            width: body.width - 54
                            height: 22

                            Tag {
                                id: riskTag

                                anchors.verticalCenter: parent.verticalCenter
                                label: hole.modelData.risk.toUpperCase()
                                hot: hole.hot
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.left: riskTag.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: hole.modelData.name + "   " + hole.modelData.issues.join(", ")
                                    + (hole.modelData.count > hole.modelData.issues.length ? " +" + (hole.modelData.count - hole.modelData.issues.length) : "")
                                    + (hole.modelData.fix !== "" ? "   ·   fixed in " + hole.modelData.fix : "   ·   no fix yet")
                                color: hole.hot ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                ShieldRow {
                    glyph: String.fromCodePoint(0xF033E)
                    title: "Auto lock"
                    mood: page.lockMood
                    text: page.lock === null ? "…"
                        : page.lock.minutes === "off" ? "Off: the screen stays open when you walk away."
                        : "Locks after " + page.lock.minutes + " idle minutes (a playing video keeps it open), and on Suspend."

                    Repeater {
                        model: [["off", "OFF"], ["5", "5"], ["10", "10"], ["15", "15"], ["30", "30 MIN"]]

                        Chip {
                            required property var modelData

                            host: page
                            label: modelData[1]
                            on: page.lock !== null && page.lock.minutes === modelData[0]
                            onPicked: {
                                if (on)
                                    return
                                page.run(["autolock", modelData[0]], "", "Setting auto lock…")
                            }
                        }
                    }
                }

                ShieldRow {
                    glyph: String.fromCodePoint(0xF099D)
                    title: "Hardening"
                    mood: page.hardMood
                    text: page.hard === null ? "…"
                        : page.hard.weak === 0
                          ? "All " + page.hard.total + " kernel and network settings are at their safe value."
                        : page.hard.weak + " of " + page.hard.total + " kernel and network settings are weaker than they need to be."
                          + " HARDEN closes them; games and apps keep working, and UNDO puts everything back."

                    Button {
                        host: page
                        visible: page.hard !== null && page.hard.weak > 0
                        label: "HARDEN"
                        onPressed: page.ask(["harden", "on"], "Your password, to harden the system", "HARDEN")
                    }

                    Button {
                        host: page
                        key: "hardoff"
                        visible: page.hard !== null && page.hard.applied
                        label: "UNDO"
                        danger: true
                        onPressed: if (page.confirm("hardoff")) page.ask(["harden", "off"], "Your password, to undo the hardening", "UNDO")
                    }
                }

                // what is still open
                Flow {
                    visible: page.hardWeak.length > 0
                    x: 54
                    width: parent.width - 54
                    bottomPadding: 16
                    spacing: 6

                    Repeater {
                        model: page.hardWeak

                        delegate: Tag {
                            required property var modelData
                            label: modelData.label
                            hot: true
                        }
                    }
                }

                ShieldRow {
                    glyph: String.fromCodePoint(0xF02CA)
                    title: "Disk encryption"
                    mood: page.encMood
                    text: page.st === null ? "…"
                        : !page.st.encryption.known ? "Could not tell how your system disk is set up."
                        : page.st.encryption.on ? "On: without your passphrase the disk cannot be read, even if it is taken out."
                        : "Off: someone holding the disk could read it. Encryption is chosen when installing; it cannot be turned on safely from here."
                }

                ShieldRow {
                    glyph: String.fromCodePoint(0xF061A)
                    title: "Secure Boot"
                    mood: page.bootMood
                    text: page.st === null ? "…"
                        : !page.st.secureBoot.efi ? "This computer starts in legacy (BIOS) mode, without Secure Boot."
                        : !page.st.secureBoot.known ? "Could not read the Secure Boot setting."
                        : page.st.secureBoot.on ? "On: the firmware only starts signed boot files."
                        : "Off. It is a firmware (BIOS) setting and needs signed boot files; leave it unless you plan for it."
                }
            }

            Column {
                visible: page.tab === 1
                width: parent.width

                // ================= GUARD =================
                SectionHead {
                    id: guardHead
                    lead: true
                    glyph: String.fromCodePoint(0xF0208)
                    label: "GUARD"
                    side: page.guard && page.guard.time ? "checked " + page.ago(page.guard.time) : ""
                }

                Item {
                    width: parent.width
                    height: guardText.implicitHeight + 32

                    Text {
                        id: guardText

                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: guardButtons.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        text: page.guard === null ? "…"
                            : page.changeCount === 0
                              ? "Nothing changed. Watching what starts at login, services and timers, users and the wheel group, SSH keys, shell start files, commands and launchers in your home, PAM, kernel modules and boot options, pacman.conf and who listens to your network."
                              : page.changeCount + (page.changeCount === 1 ? " change" : " changes")
                                + " since you last accepted. If you did it (installed something, edited a file), press THAT WAS ME. If not, look closer before anything else."
                        color: page.changeCount > 0 ? Theme.ink : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 11
                        lineHeight: 1.25
                    }

                    Row {
                        id: guardButtons

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter

                        Button {
                            host: page
                            visible: page.changeCount > 1
                            label: "ALL WERE ME"
                            onPressed: page.run(["accept", "all"], "", "Taking them as yours…")
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    bottomPadding: page.changeCount > 0 ? 8 : 0

                    Repeater {
                        model: page.guard ? page.guard.changes : []

                        Rectangle {
                            id: change

                            required property var modelData
                            readonly property bool gone: modelData.kind === "gone"

                            width: body.width
                            height: 50
                            color: change.gone ? Theme.tint(Theme.ink, 0.03) : Theme.tint(Theme.alert, 0.06)
                            border.width: 1
                            border.color: change.gone ? Theme.line : Theme.tint(Theme.alert, 0.3)

                            Rectangle {
                                width: 2
                                height: parent.height
                                color: change.gone ? Theme.inkMute : Theme.alert
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.left: parent.left
                                anchors.leftMargin: 18
                                anchors.right: meButton.left
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideMiddle
                                text: change.modelData.text
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }

                            Button {
                                id: meButton

                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                host: page
                                label: "THAT WAS ME"
                                onPressed: page.run(["accept", change.modelData.key], "", "Taking it as yours…")
                            }
                        }
                    }
                }

                // ================= LOGINS =================
                SectionHead {
                    id: loginHead
                    glyph: String.fromCodePoint(0xF0342)
                    label: "PASSWORDS AND LOGINS"
                    side: page.events.since ? "since " + page.clock(page.events.since) : ""
                }

                Item {
                    width: parent.width
                    height: loginText.implicitHeight + 32

                    Text {
                        id: loginText

                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: seenButton.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        text: page.events.readable === false
                              ? "Your user cannot read the system journal. Being in the wheel group allows it."
                              : (page.failedCount === 0 ? "No wrong passwords." : page.failedCount + (page.failedCount === 1 ? " wrong password." : " wrong passwords."))
                                + "  " + (page.sudoCount === 0 ? "sudo was not used." : "sudo used " + page.sudoCount + (page.sudoCount === 1 ? " time." : " times."))
                                + (page.sshCount > 0 ? "  " + page.sshCount + " SSH login" + (page.sshCount === 1 ? "." : "s.") : "")
                        color: page.failedCount > 0 || page.sshCount > 0 ? Theme.ink : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 11
                        lineHeight: 1.25
                    }

                    Button {
                        id: seenButton

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        host: page
                        visible: page.logRows.length > 0
                        label: "SEEN"
                        onPressed: page.run(["seen"], "", "Clearing the list…")
                    }
                }

                // the log: when, what, the command
                Rectangle {
                    visible: page.logRows.length > 0
                    width: parent.width
                    height: visible ? logCol.implicitHeight + 2 : 0
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.line

                    Column {
                        id: logCol

                        x: 1
                        y: 1
                        width: parent.width - 2

                        Repeater {
                            model: page.showAllLog ? page.logRows : page.logRows.slice(0, 5)

                            delegate: Rectangle {
                                id: logRow

                                required property var modelData
                                required property int index

                                width: logCol.width
                                height: 34
                                color: index % 2 === 1 ? Theme.tint(Theme.ink, 0.02) : "transparent"

                                Text {
                                    id: logTime

                                    textFormat: Text.PlainText
                                    x: 14
                                    width: 104
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.clock(logRow.modelData.time)
                                    color: Theme.inkMute
                                    font.family: Theme.mono
                                    font.pixelSize: 10
                                }

                                Tag {
                                    id: logKind

                                    anchors.left: logTime.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 64
                                    label: logRow.modelData.kind
                                    hot: logRow.modelData.hot
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.left: logKind.right
                                    anchors.leftMargin: 14
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: logRow.modelData.text
                                    color: logRow.modelData.hot ? Theme.ink : Theme.inkSoft
                                    font.family: Theme.mono
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // show the rest
                        Rectangle {
                            visible: page.logRows.length > 5
                            width: logCol.width
                            height: 34
                            color: moreMouse.containsMouse ? Theme.tint(Theme.ink, 0.04) : "transparent"

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Theme.line
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: page.showAllLog ? "SHOW LESS" : "SHOW ALL " + page.logRows.length
                                color: moreMouse.containsMouse ? Theme.ink : Theme.accent
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.letterSpacing: 2
                            }

                            MouseArea {
                                id: moreMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.showAllLog = !page.showAllLog
                            }
                        }
                    }
                }
            }

            Column {
                visible: page.tab === 2
                width: parent.width

                // ================= APPS =================
                Text {
                    textFormat: Text.PlainText
                    visible: page.st !== null && page.apps.length === 0
                    topPadding: 8
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "No Flatpak app reaches outside its own box (or none is installed)."
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                SectionHead {
                    visible: page.apps.length > 0
                    lead: true
                    glyph: String.fromCodePoint(0xF003B)
                    label: "APP SANDBOX"
                    side: page.apps.length + (page.apps.length === 1 ? " Flatpak app reaches out" : " Flatpak apps reach out")
                }

                // two lines, always: the words change under the pointer, the page does not move
                Item {
                    visible: page.apps.length > 0
                    width: parent.width
                    height: 62

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: page.permHint !== "" ? page.permHint
                            : "What each app reaches outside its own box. Click one to cut it, click again to give it back. It counts from the app's next start; no password is needed."
                        color: page.permHint !== "" ? Theme.ink : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 11
                        lineHeight: 1.25
                    }
                }

                Column {
                    visible: page.apps.length > 0
                    width: parent.width
                    bottomPadding: 8
                    spacing: 12

                    Repeater {
                        model: page.apps

                        delegate: Item {
                            id: appRow

                            required property var modelData

                            width: body.width
                            height: Math.max(24, permFlow.implicitHeight)

                            Text {
                                id: appName

                                textFormat: Text.PlainText
                                width: 150
                                anchors.top: parent.top
                                anchors.topMargin: 5
                                elide: Text.ElideRight
                                text: appRow.modelData.name
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 12
                            }

                            Flow {
                                id: permFlow

                                anchors.left: appName.right
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                spacing: 6

                                Repeater {
                                    model: appRow.modelData.perms

                                    delegate: Perm {
                                        required property var modelData

                                        host: page
                                        app: appRow.modelData.id
                                        info: modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Column {
                visible: page.tab === 3
                width: parent.width

                // ================= DEEP SCAN =================
                SectionHead {
                    lead: true
                    glyph: String.fromCodePoint(0xF0349)
                    label: "DEEP SCAN"
                    side: page.scan ? "last " + page.ago(page.scan.time) : ""
                }

                ShieldRow {
                    glyph: String.fromCodePoint(page.scan && page.scanRed === 0 ? 0xF05E0 : 0xF0028)
                    title: page.scan === null ? "Not run yet" : page.scanRed === 0 ? "Every system file matches"
                        : page.scan.redCount === 0 ? page.scanSuid + (page.scanSuid === 1 ? " program" : " programs") + " with root rights from no package"
                        : page.scan.redCount + (page.scan.redCount === 1 ? " system file differs" : " system files differ")
                    mood: page.scan === null ? "info" : page.scanRed === 0 ? "good" : "bad"
                    text: page.scan === null
                          ? "Compares every program and library with the copy its package installed, to find anything swapped or patched, and looks for programs with root rights that no package installed. Takes a few minutes; nothing is changed."
                          : page.scanRed === 0
                            ? "Every system program and library matches its package"
                              + (page.scan.suid ? ", and every program with root rights came from one. " : ". ") + page.scan.configs
                              + " settings files in /etc differ from their defaults"
                              + (page.scan.caches ? " and " + page.scan.caches + " caches were rebuilt on this computer" : "")
                              + ", which is normal."
                          : page.scan.redCount === 0
                            ? "A program that runs with root rights and belongs to no package is how an intruder keeps the keys. If you did not put it there, look closer before anything else."
                            : "A broken update can do this too: reinstalling the package (sudo pacman -S <name>) puts the right copy back."

                    Button {
                        host: page
                        label: page.scan ? "SCAN AGAIN" : "SCAN"
                        onPressed: page.ask(["scan"], "Your password, to read every system file", "SCAN")
                    }
                }

                Column {
                    width: parent.width
                    visible: page.scan !== null && page.scanRed > 0
                    leftPadding: 54
                    topPadding: 4
                    bottomPadding: 8
                    spacing: 6

                    Repeater {
                        model: page.scan && page.scan.red ? page.scan.red.slice(0, 20) : []

                        Text {
                            required property var modelData

                            textFormat: Text.PlainText
                            width: body.width - 54
                            elide: Text.ElideMiddle
                            text: modelData.path + "   ·   " + modelData.package + "   ·   " + modelData.why.toLowerCase()
                            color: Theme.alert
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }
                    }

                    Repeater {
                        model: page.scan && page.scan.suid ? page.scan.suid.slice(0, 20) : []

                        Text {
                            required property var modelData

                            textFormat: Text.PlainText
                            width: body.width - 54
                            elide: Text.ElideMiddle
                            text: modelData + "   ·   runs with root rights, from no package"
                            color: Theme.alert
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // how this page works
            Text {
                textFormat: Text.PlainText
                topPadding: 28
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: "Nothing here runs in the background. The guard checks once at login and tells you only what is serious."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }
    }

    ScrollHint {
        flick: scroll
    }
}
