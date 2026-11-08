import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Tasks: what runs on this computer, and why.
// scripts/yakushi-taskctl.py streams CPU, memory and every process every
// 1.5 s while this page is open (it stops with the page); PAUSE freezes the
// view so you can read it. The three tiles on top keep a short history.
//
// The list groups processes of the same program (firefox ×12) and opens a
// group with a click. Click a column title to sort by it. Processes in
// trouble get a tag (NOT RESPONDING, STUCK, PAUSED, ...) and apps that stopped
// answering are named in a banner on top.
//
// Pick a process to open its drawer on the right: live numbers, which package
// it comes from, why it is installed and who started it, and the buttons to
// end it (END asks it to quit, FORCE END stops it at once). REMOVE PACKAGE
// switches to Settings -> Programs with that package's removal plan.
// SUPER + Esc opens this page.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: Paths.script("yakushi-taskctl.py")

    // ---- live data
    property real cpu: -1
    property real memUsed: 0
    property real memTotal: 0
    property int cores: 1
    property int total: 0
    property int mineCount: 0
    property int withWindows: 0
    property int threads: 0
    property var busiest: null
    property var procs: []
    property var trouble: []           // apps not responding / stuck: shown in the banner
    property var cpuHistory: []
    property var memHistory: []
    readonly property int historyLength: 48
    property bool paused: false
    property var fixedCache: ({})      // "pid:start" -> { name, proc, user, mine, cmd }
    property int ticks: 0

    // ---- what you look at
    property string scope: "mine"      // apps | mine | all
    property string sortBy: "cpu"      // cpu | mem | name
    property string search: ""
    property bool grouped: true
    property var expanded: ({})        // group name -> true
    property int selected: -1          // pid
    property var order: []             // top-level keys in the order shown
    property var kidOrder: ({})        // group name -> keys of its open rows

    readonly property bool sideBySide: width >= 1000
    readonly property bool drawerOpen: selected >= 0

    Process {
        id: stream

        command: ["python3", page.helper, "stream"]
        running: true

        stdout: SplitParser {
            onRead: data => page.take(data)
        }
    }

    function remember(list, value) {
        var h = list.slice()
        h.push(value)
        if (h.length > historyLength)
            h.shift()
        return h
    }

    function take(line) {
        var d
        try {
            d = JSON.parse(line)
        } catch (e) {
            return
        }
        // name, user and command line come once per process: kept here
        var fresh = {}
        for (var c = 0; c < d.procs.length; c++) {
            var q = d.procs[c]
            var key = q.pid + ":" + q.start
            var f = q.fixed !== undefined ? q.fixed : fixedCache[key]
            if (f === undefined)
                f = { name: "?", proc: "?", user: "", mine: false, cmd: "" }
            if (q.fixed !== undefined)
                fixedCache[key] = f
            q.name = f.name
            q.proc = f.proc
            q.user = f.user
            q.mine = f.mine
            q.cmd = f.cmd
            fresh[key] = f
        }
        if (++ticks % 40 === 0)
            fixedCache = fresh            // forget processes that ended
        if (paused)
            return
        cpu = d.cpu
        memUsed = d.memUsed
        memTotal = d.memTotal
        cores = d.cores || 1
        cpuHistory = remember(cpuHistory, d.cpu)
        memHistory = remember(memHistory, d.memTotal ? 100 * d.memUsed / d.memTotal : 0)

        var w = 0, m = 0, t = 0, top = null
        var bad = []
        for (var i = 0; i < d.procs.length; i++) {
            var p = d.procs[i]
            if (p.window !== "")
                w++
            if (p.mine)
                m++
            t += p.threads || 0
            if (top === null || p.cpu > top.cpu)
                top = p
            if (p.flag === "anr" || (p.flag === "stuck" && p.mine))
                bad.push(p)
        }
        total = d.procs.length
        withWindows = w
        mineCount = m
        threads = t
        busiest = top && top.cpu >= 0.5 ? { name: top.name, cpu: top.cpu } : null
        procs = d.procs
        if (JSON.stringify(bad.map(function(p) { return p.pid + p.flag })) !== JSON.stringify(trouble.map(function(p) { return p.pid + p.flag })))
            trouble = bad
        refresh()
    }

    function visibleProcs() {
        var q = search.trim().toLowerCase()
        return procs.filter(function(p) {
            if (scope === "apps" && p.window === "")
                return false
            if (scope === "mine" && !p.mine)
                return false
            if (q === "")
                return true
            return (p.name + " " + p.proc + " " + p.cmd + " " + p.pid + " " + p.window).toLowerCase().indexOf(q) >= 0
        })
    }

    function sortList(list) {
        var key = sortBy
        return list.sort(function(a, b) {
            if (key === "name")
                return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : a.pid - b.pid
            var x = key === "mem" ? b.mem - a.mem : b.cpu - a.cpu
            return x !== 0 ? x : (key === "cpu" ? b.mem - a.mem : a.pid - b.pid)
        })
    }

    function flagRank(f) {
        return f === "anr" ? 5 : f === "stuck" ? 4 : f === "busy" ? 3 : f === "stopped" ? 2 : f === "zombie" ? 1 : 0
    }

    // one row of the list: a process, or a group of processes of one program
    function entry(p, depth) {
        return { key: "p:" + p.pid, kind: "proc", pid: p.pid, name: p.name, proc: p.proc, user: p.user,
                 cpu: p.cpu, mem: p.mem, state: p.state, window: p.window, mine: p.mine,
                 flag: p.flag || "", count: 1, depth: depth, open: false, members: null }
    }

    function groupOf(name, members) {
        var g = { key: "g:" + name, kind: "group", pid: members[0].pid, name: name, proc: members[0].proc,
                  user: members[0].user, cpu: 0, mem: 0, state: "S", window: "", mine: false, flag: "",
                  count: members.length, depth: 0, open: expanded[name] === true, members: members }
        for (var i = 0; i < members.length; i++) {
            var m = members[i]
            g.cpu += m.cpu
            g.mem += m.mem
            g.pid = Math.min(g.pid, m.pid)
            if (m.state === "R")
                g.state = "R"
            if (g.window === "" && m.window !== "")
                g.window = m.window
            g.mine = g.mine || m.mine
            if (flagRank(m.flag || "") > flagRank(g.flag))
                g.flag = m.flag
        }
        g.cpu = Math.round(g.cpu * 10) / 10
        return g
    }

    // `list` in the order of `keys`; rows that are new go after them
    function keep(list, keys) {
        var by = {}
        for (var i = 0; i < list.length; i++)
            by[list[i].key] = list[i]
        var out = []
        for (var j = 0; j < keys.length; j++)
            if (by[keys[j]] !== undefined) {
                out.push(by[keys[j]])
                delete by[keys[j]]
            }
        for (var k = 0; k < list.length; k++)
            if (by[list[k].key] !== undefined)
                out.push(list[k])
        return out
    }

    // rows keep their place while the pointer is over the list, so what
    // you are about to click does not run away
    function refresh() {
        var list = visibleProcs()
        var top = []
        if (grouped) {
            var byName = {}
            var names = []
            for (var i = 0; i < list.length; i++) {
                var n = list[i].name
                if (byName[n] === undefined) {
                    byName[n] = []
                    names.push(n)
                }
                byName[n].push(list[i])
            }
            for (var j = 0; j < names.length; j++)
                top.push(byName[names[j]].length === 1 ? entry(byName[names[j]][0], 0) : groupOf(names[j], byName[names[j]]))
        } else {
            for (var a = 0; a < list.length; a++)
                top.push(entry(list[a], 0))
        }

        var frozen = listHover.hovered && rows.count > 0
        top = frozen ? keep(top, order) : sortList(top)
        order = top.map(function(e) { return e.key })

        var flat = []
        for (var t = 0; t < top.length; t++) {
            flat.push(top[t])
            if (top[t].kind === "group" && top[t].open) {
                var kids = sortList(top[t].members.map(function(m) { return page.entry(m, 1) }))
                if (frozen && kidOrder[top[t].name] !== undefined)
                    kids = keep(kids, kidOrder[top[t].name])
                kidOrder[top[t].name] = kids.map(function(e) { return e.key })
                for (var c = 0; c < kids.length; c++)
                    flat.push(kids[c])
            }
        }

        // same rows, new values: the view is not rebuilt
        for (var k = 0; k < flat.length; k++) {
            var e = flat[k]
            var row = { key: e.key, kind: e.kind, pid: e.pid, name: e.name, proc: e.proc, user: e.user,
                        cpu: e.cpu, mem: e.mem, state: e.state, window: e.window, mine: e.mine,
                        flag: e.flag, count: e.count, depth: e.depth, open: e.open }
            if (k < rows.count)
                rows.set(k, row)
            else
                rows.append(row)
        }
        if (rows.count > flat.length)
            rows.remove(flat.length, rows.count - flat.length)
    }

    function toggleGroup(name) {
        var copy = Object.assign({}, expanded)
        if (copy[name])
            delete copy[name]
        else
            copy[name] = true
        expanded = copy
        refresh()
    }

    onScopeChanged: refresh()
    onSortByChanged: refresh()
    onSearchChanged: refresh()
    onGroupedChanged: refresh()

    ListModel {
        id: rows
    }

    // ---- details of the picked process
    property var info: null

    function pick(pid) {
        if (selected === pid) {
            close()
            return
        }
        inspect(pid)
    }

    function close() {
        selected = -1
        info = null
        armed = ""
        pendingAct = ""
        actionNote = ""
    }

    function inspect(pid) {
        selected = pid
        info = null
        armed = ""
        pendingAct = ""
        actionNote = ""
        why.command = ["python3", helper, "why", String(pid)]
        why.running = true
    }

    // the picked process as the stream sees it now
    readonly property var current: {
        for (var i = 0; i < procs.length; i++)
            if (procs[i].pid === selected)
                return procs[i]
        return null
    }
    readonly property bool selectedAlive: current !== null && current.state !== "Z"
    readonly property string selectedFlag: current ? current.flag || "" : ""

    // ---- ending: END / FORCE END / CONTINUE / STOP SERVICE
    property string armed: ""          // the action waiting for its second click
    property string actionNote: ""
    property bool actionOk: true
    readonly property bool acting: action.running

    function act(kind) {
        if (!info || !info.facts || acting)
            return
        if (kind === "remove") {
            var id = info.flatpak ? "flatpak:" + info.flatpak : info.package ? info.package.name : ""
            if (id !== "" && hostWindow)
                hostWindow.openPrograms([id])
            return
        }
        var risky = kind === "force" || kind === "stop" || (info.guard && info.guard.level !== "")
        if (risky && armed !== kind) {
            armed = kind
            disarm.restart()
            return
        }
        armed = ""
        // other users' processes and system services need your password:
        // it is asked right here (no dialog that would open behind Settings)
        if (info.other || (kind === "stop" && info.unit && !info.unit.user)) {
            pendingAct = kind
            actionNote = ""
            passwordAsk.error = ""
            Qt.callLater(passwordAsk.open)
            return
        }
        run(kind, "")
    }

    property string pendingAct: ""     // the action waiting for your password
    property string secret: ""
    property string lastKind: ""

    function run(kind, pw) {
        var f = info.facts
        actionNote = kind === "end" ? "Asking it to quit…" : kind === "force" ? "Stopping it…"
            : kind === "cont" ? "Letting it go on…" : "Stopping the service…"
        actionOk = true
        secret = pw
        action.stdinEnabled = pw !== ""
        lastKind = kind
        var head = ["python3", helper].concat(pw !== "" ? ["--password-stdin"] : [])
        action.command = kind === "stop"
            ? head.concat(["stop-unit", info.unit.name, info.unit.user ? "user" : "system"])
            : head.concat([kind, String(f.pid), String(f.start)])
        action.running = true
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: page.armed = ""
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
                try {
                    var d = JSON.parse(text)
                    if (d.wrongPassword) {
                        page.pendingAct = page.lastKind
                        page.actionNote = ""
                        passwordAsk.error = "Wrong password. Try again."
                        Qt.callLater(passwordAsk.open)
                        return
                    }
                    page.actionNote = d.message || ""
                    page.actionOk = d.ok !== false
                } catch (e) {
                    page.actionNote = "No answer from the helper."
                    page.actionOk = false
                }
            }
        }
    }

    Process {
        id: why

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.info = JSON.parse(text)
                } catch (e) {
                    page.info = { ok: false, message: "No answer from the helper." }
                }
            }
        }
    }

    function flagText(flag) {
        return flag === "anr" ? "NOT RESPONDING" : flag === "stuck" ? "STUCK" : flag === "stopped" ? "PAUSED"
            : flag === "zombie" ? "ENDED" : flag === "busy" ? "BUSY" : ""
    }

    function flagHint(flag) {
        return flag === "anr" ? "Its window stopped answering Hyprland. END may not work; FORCE END will."
            : flag === "stuck" ? "It has been waiting on a disk or a driver for a while."
            : flag === "stopped" ? "Paused (stopped). CONTINUE lets it go on."
            : flag === "zombie" ? "It has ended; its parent has not collected it yet."
            : flag === "busy" ? "Using a whole CPU core for a while. Often fine (a game, a build)."
            : ""
    }

    // ---- formatting
    function bytes(n) {
        if (n >= 1073741824)
            return (n / 1073741824).toFixed(n >= 10737418240 ? 0 : 1) + " GB"
        if (n >= 1048576)
            return Math.round(n / 1048576) + " MB"
        return Math.round(n / 1024) + " KB"
    }

    function percent(v) {
        return v >= 10 ? Math.round(v) + "%" : v.toFixed(1) + "%"
    }

    function stateText(s) {
        return s === "R" ? "running" : s === "S" ? "sleeping" : s === "D" ? "waiting on disk"
            : s === "T" || s === "t" ? "stopped" : s === "Z" ? "ended, not collected" : s === "I" ? "idle" : s
    }

    function kindGlyph(kind) {
        return kind === "package" ? String.fromCodePoint(0xF03D7)
            : kind === "reason" ? String.fromCodePoint(0xF02FD)
            : kind === "start" ? String.fromCodePoint(0xF040A)
            : kind === "window" ? String.fromCodePoint(0xF05AF)
            : kind === "kernel" || kind === "core" ? String.fromCodePoint(0xF033D)
            : kind === "yakushi" ? "薬"
            : String.fromCodePoint(0xF0214)
    }

    // ------------------------------------------------------------------
    // Small parts (inline components do not see the page's ids: they get
    // what they need through properties)
    // ------------------------------------------------------------------
    component Caption: Text {
        textFormat: Text.PlainText
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool on: false

        signal picked()

        width: chipText.implicitWidth + 28
        height: 36
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
            font.letterSpacing: 1.5
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    component ActButton: Rectangle {
        id: act

        property string key: ""
        property string label: ""
        property bool danger: false
        property var host: null
        readonly property bool armedHere: host !== null && host.armed === key

        width: actText.implicitWidth + 30
        height: 34
        opacity: host && host.acting ? 0.5 : 1
        color: armedHere ? Theme.tint(Theme.alert, 0.3)
            : danger ? (actMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
            : Theme.tint(Theme.accent, actMouse.containsMouse ? 0.24 : 0.1)
        border.width: 1
        border.color: danger || armedHere ? Theme.alert : Theme.tint(Theme.accent, 0.6)

        Text {
            id: actText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: act.armedHere ? "CLICK AGAIN" : act.label
            color: act.danger || act.armedHere ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        MouseArea {
            id: actMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: act.host !== null && !act.host.acting
            cursorShape: Qt.PointingHandCursor
            onClicked: act.host.act(act.key)
        }
    }

    // a number on top, its last minute as a line underneath
    component Tile: Rectangle {
        id: tile

        property string label: ""
        property string value: ""
        property string sub: ""
        property var history: []
        property int slots: 48
        property string foot: ""

        height: 96
        color: Theme.card
        border.width: 1
        border.color: Theme.line

        Caption {
            x: 18
            y: 16
            text: tile.label
        }

        Text {
            id: tileValue

            textFormat: Text.PlainText
            x: 18
            y: 34
            text: tile.value
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 22
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: tileValue.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.baseline: tileValue.baseline
            elide: Text.ElideRight
            text: tile.sub
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 11
        }

        Text {
            textFormat: Text.PlainText
            visible: tile.foot !== ""
            // both edges anchored, else a long name grows past the tile
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.right: parent.right
            horizontalAlignment: Text.AlignRight
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            elide: Text.ElideRight
            text: tile.foot
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
        }

        Canvas {
            id: spark

            visible: tile.foot === ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // same inset as the text, so a low value never sits on the border
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            anchors.bottomMargin: 12
            height: 26

            onWidthChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var h = tile.history
                if (h.length < 2)
                    return
                var step = width / (tile.slots - 1)
                var x0 = width - (h.length - 1) * step
                function yOf(v) {
                    return height - 2 - (height - 4) * Math.max(0, Math.min(1, v / 100))
                }
                ctx.fillStyle = String(Theme.accent)
                ctx.strokeStyle = String(Theme.accent)

                ctx.beginPath()
                ctx.moveTo(x0, height)
                for (var i = 0; i < h.length; i++)
                    ctx.lineTo(x0 + i * step, yOf(h[i]))
                ctx.lineTo(width, height)
                ctx.closePath()
                ctx.globalAlpha = 0.12
                ctx.fill()

                ctx.beginPath()
                ctx.moveTo(x0, yOf(h[0]))
                for (var j = 1; j < h.length; j++)
                    ctx.lineTo(x0 + j * step, yOf(h[j]))
                ctx.globalAlpha = 0.85
                ctx.lineWidth = 1.5
                ctx.stroke()
            }
        }

        onHistoryChanged: spark.requestPaint()

        Connections {
            target: Theme
            function onAccentChanged() { spark.requestPaint() }
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
            anchors.right: liveRow.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            title: "TASKS"
        }

        Row {
            id: liveRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Rectangle {
                id: liveDot

                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: page.paused ? Theme.inkMute : Theme.good

                SequentialAnimation on opacity {
                    running: !page.paused
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.3; duration: 750; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.3; to: 1; duration: 750; easing.type: Easing.InOutSine }
                }
            }

            Caption {
                anchors.verticalCenter: parent.verticalCenter
                text: page.paused ? "PAUSED" : "LIVE"
                color: page.paused ? Theme.inkSoft : Theme.inkMute
            }

            Chip {
                label: page.paused ? "RESUME" : "PAUSE"
                on: page.paused
                onPicked: {
                    page.paused = !page.paused
                    if (page.paused)
                        liveDot.opacity = 1
                }
            }
        }
    }

    // ---- CPU, memory, how many
    Row {
        id: tiles

        anchors.top: head.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 14

        readonly property real cell: (width - spacing * 2) / 3

        Tile {
            width: tiles.cell
            label: "CPU"
            value: page.cpu < 0 ? "…" : Math.round(page.cpu) + "%"
            sub: page.cores + (page.cores === 1 ? " core" : " cores")
            history: page.cpuHistory
            slots: page.historyLength
        }

        Tile {
            width: tiles.cell
            label: "MEMORY"
            value: page.memTotal ? page.bytes(page.memUsed) : "…"
            sub: page.memTotal ? "of " + page.bytes(page.memTotal) : ""
            history: page.memHistory
            slots: page.historyLength
        }

        Tile {
            width: tiles.cell
            label: "PROCESSES"
            value: page.total ? String(page.total) : "…"
            sub: page.total ? page.withWindows + " apps · " + page.threads + " threads" : ""
            foot: page.busiest ? "busiest  " + page.busiest.name + "  " + page.percent(page.busiest.cpu) : "all quiet"
        }
    }

    // ---- apps that stopped answering
    Rectangle {
        id: banner

        visible: page.trouble.length > 0
        anchors.top: tiles.bottom
        anchors.topMargin: visible ? 18 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 50 : 0
        color: Theme.tint(Theme.alert, 0.1)
        border.width: 1
        border.color: Theme.tint(Theme.alert, 0.55)

        Text {
            id: bannerGlyph

            textFormat: Text.PlainText
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0026)
            color: Theme.alert
            font.family: Theme.glyphs
            font.pixelSize: 16
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: bannerGlyph.right
            anchors.leftMargin: 12
            anchors.right: bannerButtons.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: {
                var t = page.trouble
                if (t.length === 0)
                    return ""
                var what = t[0].flag === "anr" ? " is not responding." : " is stuck."
                return t[0].name + what + (t.length > 1 ? "  (+" + (t.length - 1) + " more)" : "")
            }
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 12
        }

        Row {
            id: bannerButtons

            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: page.trouble.slice(0, 3)

                delegate: Rectangle {
                    required property var modelData

                    width: showText.implicitWidth + 24
                    height: 32
                    color: showMouse.containsMouse ? Theme.tint(Theme.alert, 0.24) : "transparent"
                    border.width: 1
                    border.color: Theme.tint(Theme.alert, 0.7)

                    Text {
                        id: showText

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: page.trouble.length > 1 ? "SHOW " + parent.modelData.name.toUpperCase().slice(0, 14) : "SHOW"
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        id: showMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.inspect(parent.modelData.pid)
                    }
                }
            }
        }
    }

    // ---- which, search, grouping
    Item {
        id: tools

        anchors.top: banner.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36

        Segmented {
            id: scopes

            anchors.verticalCenter: parent.verticalCenter
            current: page.scope
            options: [["apps", "APPS"], ["mine", "MINE"], ["all", "ALL"]]
            counts: page.total ? { apps: page.withWindows, mine: page.mineCount, all: page.total } : ({})
            onChose: key => page.scope = key
        }

        Rectangle {
            id: searchBox

            anchors.left: scopes.right
            anchors.leftMargin: 12
            anchors.right: groupChip.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 36
            color: Theme.tint(Theme.ink, 0.03)
            border.width: 1
            border.color: searchInput.activeFocus ? Theme.accent : Theme.line

            Text {
                id: lens

                textFormat: Text.PlainText
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0349)
                color: Theme.inkMute
                font.family: Theme.glyphs
                font.pixelSize: 13
            }

            TextInput {
                id: searchInput

                anchors.left: lens.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: Theme.ink
                selectByMouse: true
                font.family: Theme.mono
                font.pixelSize: 12
                onTextChanged: page.search = text
                // Esc clears the search; on an empty one it closes Settings
                Keys.onEscapePressed: event => {
                    if (text !== "")
                        text = ""
                    else
                        event.accepted = false
                }

                Text {
                    textFormat: Text.PlainText
                    visible: searchInput.text === "" && !searchInput.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    elide: Text.ElideRight
                    text: "Search name, command or PID"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
            }
        }

        Chip {
            id: groupChip

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "GROUP"
            on: page.grouped
            onPicked: page.grouped = !page.grouped
        }
    }

    // ---- column titles: click one to sort by it
    Item {
        id: columns

        readonly property int cpuWidth: 72
        readonly property int memWidth: 96
        readonly property int edge: 20

        anchors.top: tools.bottom
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: list.right
        height: 28

        Repeater {
            model: [["name", "NAME"], ["cpu", "CPU"], ["mem", "MEMORY"]]

            delegate: Item {
                id: colTitle

                required property var modelData
                readonly property bool on: page.sortBy === modelData[0]
                readonly property bool isName: modelData[0] === "name"

                x: isName ? 40 : modelData[0] === "cpu"
                    ? columns.width - columns.edge - columns.memWidth - 20 - columns.cpuWidth
                    : columns.width - columns.edge - columns.memWidth
                width: isName ? colText.implicitWidth + 16 : modelData[0] === "cpu" ? columns.cpuWidth : columns.memWidth
                height: parent.height

                Text {
                    id: colText

                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: colTitle.isName ? parent.left : undefined
                    anchors.right: colTitle.isName ? undefined : parent.right
                    text: (colTitle.on && !colTitle.isName ? "▾ " : "") + colTitle.modelData[1] + (colTitle.on && colTitle.isName ? " ▴" : "")
                    color: colTitle.on ? Theme.accent : colMouse.containsMouse ? Theme.ink : Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    font.bold: colTitle.on
                }

                MouseArea {
                    id: colMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.sortBy = colTitle.modelData[0]
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.line
        }
    }

    // ---- the list
    ListView {
        id: list

        anchors.top: columns.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: page.sideBySide && page.drawerOpen ? drawer.left : parent.right
        anchors.rightMargin: page.sideBySide && page.drawerOpen ? 20 : 0
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: rows
        reuseItems: true

        HoverHandler {
            id: listHover
        }

        delegate: Rectangle {
            id: line

            required property string key
            required property string kind
            required property int pid
            required property string name
            required property string proc
            required property string user
            required property real cpu
            required property real mem
            required property string state
            required property string window
            required property bool mine
            required property string flag
            required property int count
            required property int depth
            required property bool open

            readonly property bool isGroup: kind === "group"
            readonly property bool picked: !isGroup && page.selected === pid
            readonly property int indent: depth * 26

            width: list.width
            height: depth > 0 ? 46 : 56
            color: picked ? Theme.tint(Theme.accent, 0.12)
                : lineMouse.containsMouse ? Theme.tint(Theme.ink, 0.045)
                : depth > 0 ? Theme.tint(Theme.ink, 0.015) : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }

            // picked: an accent edge on the left
            Rectangle {
                visible: line.picked
                width: 2
                height: parent.height
                color: Theme.accent
            }

            // a thread line down the open group
            Rectangle {
                visible: line.depth > 0
                x: 21
                width: 1
                height: parent.height
                color: Theme.lineHot
            }

            Rectangle {
                anchors.bottom: parent.bottom
                x: 16
                width: parent.width - 32
                height: 1
                color: Theme.tint(Theme.ink, 0.05)
            }

            // a chevron on groups, a state dot on processes
            Text {
                textFormat: Text.PlainText
                visible: line.isGroup
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(line.open ? 0xF0140 : 0xF0142)
                color: lineMouse.containsMouse ? Theme.ink : Theme.inkSoft
                font.family: Theme.glyphs
                font.pixelSize: 16
            }

            Rectangle {
                visible: !line.isGroup
                x: 18 + line.indent
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: line.state === "R" ? Theme.accent
                    : line.state === "D" || line.state === "T" || line.state === "Z" ? Theme.alert
                    : Theme.lineHot
            }

            Text {
                id: lineName

                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 40 + line.indent
                anchors.right: tag.visible ? tag.left : cpuText.left
                anchors.rightMargin: 16
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: line.depth > 0 ? 0 : 1
                elide: Text.ElideRight
                text: line.isGroup ? line.name + "  ×" + line.count : line.name
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: line.depth > 0 ? 12 : 13
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: lineName.left
                anchors.right: lineName.right
                anchors.top: parent.verticalCenter
                anchors.topMargin: line.depth > 0 ? 3 : 5
                elide: Text.ElideRight
                text: line.isGroup
                    ? line.count + " processes" + (line.window !== "" ? "  ·  " + line.window : "")
                    : (line.window !== "" ? line.window + "  ·  " : "")
                      + (line.proc.toLowerCase() === line.name.toLowerCase() ? "" : line.proc + "  ·  ") + "PID " + line.pid
                      + (line.mine ? "" : "  ·  " + line.user)
                color: line.window !== "" && line.depth === 0 ? Theme.inkSoft : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 11
            }

            // NOT RESPONDING / STUCK / PAUSED / ENDED / BUSY
            Rectangle {
                id: tag

                readonly property bool bad: line.flag === "anr" || line.flag === "stuck"

                visible: line.flag !== ""
                anchors.right: cpuText.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: tagText.implicitWidth + 18
                height: 24
                color: bad ? Theme.tint(Theme.alert, 0.16) : Theme.tint(Theme.ink, 0.05)
                border.width: 1
                border.color: bad ? Theme.alert : Theme.lineHot

                Text {
                    id: tagText

                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: page.flagText(line.flag)
                    color: tag.bad ? Theme.alert : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }

            Text {
                id: cpuText

                textFormat: Text.PlainText
                anchors.right: memText.left
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: columns.cpuWidth
                horizontalAlignment: Text.AlignRight
                text: page.percent(line.cpu)
                color: line.cpu >= 50 ? Theme.alert : line.cpu >= 1 ? Theme.ink : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 12
            }

            Text {
                id: memText

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: columns.edge
                anchors.verticalCenter: parent.verticalCenter
                width: columns.memWidth
                horizontalAlignment: Text.AlignRight
                text: page.bytes(line.mem)
                color: line.mem >= 1073741824 ? Theme.ink : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 12
            }

            MouseArea {
                id: lineMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: line.isGroup ? page.toggleGroup(line.name) : page.pick(line.pid)
            }
        }

        Text {
            textFormat: Text.PlainText
            visible: rows.count === 0
            anchors.centerIn: parent
            text: page.cpu < 0 ? "Reading…" : page.search !== "" ? "Nothing matches “" + page.search + "”." : "Nothing here."
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 12
        }
    }

    ScrollHint {
        flick: list
    }

    // ---- narrow card: the drawer lies over the list; the rest dims
    Rectangle {
        id: dim

        visible: opacity > 0
        opacity: page.drawerOpen && !page.sideBySide ? 1 : 0
        anchors.top: columns.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: drawer.left
        color: Theme.tint(Theme.surface, 0.6)

        Behavior on opacity {
            NumberAnimation { duration: Theme.tMid }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.close()
        }
    }

    // ------------------------------------------------------------------
    // The drawer: the picked process, why it runs, and what you can do
    // ------------------------------------------------------------------
    Rectangle {
        id: drawer

        readonly property var facts: page.info && page.info.facts ? page.info.facts : null
        readonly property var guard: page.info && page.info.guard ? page.info.guard : null
        readonly property bool canEnd: facts !== null && page.selectedAlive && guard !== null && guard.level !== "none"

        anchors.top: columns.top
        anchors.bottom: parent.bottom
        width: page.sideBySide ? Math.min(460, Math.round(page.width * 0.42)) : Math.min(480, Math.round(page.width * 0.7))
        x: page.drawerOpen ? page.width - width : page.width - width + 28
        opacity: page.drawerOpen ? 1 : 0
        visible: opacity > 0
        color: Theme.surface
        border.width: 1
        border.color: Theme.tint(Theme.accent, 0.4)
        z: 5

        Behavior on x {
            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.tMid }
        }

        // clicks stay in the drawer
        MouseArea {
            anchors.fill: parent
        }

        // ---- name, close
        Item {
            id: drawerHead

            x: 22
            y: 20
            width: parent.width - 44
            height: drawerName.implicitHeight + 6 + drawerSub.implicitHeight

            Text {
                id: drawerName

                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: closeButton.left
                anchors.rightMargin: 12
                elide: Text.ElideRight
                text: drawer.facts ? drawer.facts.name : page.current ? page.current.name : ""
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 18
            }

            Text {
                id: drawerSub

                textFormat: Text.PlainText
                anchors.top: drawerName.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: closeButton.left
                anchors.rightMargin: 12
                elide: Text.ElideRight
                text: drawer.facts
                    ? "PID " + drawer.facts.pid + "  ·  " + drawer.facts.proc + (page.selectedAlive ? "" : "  ·  ended")
                    : "PID " + page.selected
                color: page.selectedAlive || !drawer.facts ? Theme.inkMute : Theme.alert
                font.family: Theme.mono
                font.pixelSize: 11
            }

            Rectangle {
                id: closeButton

                anchors.right: parent.right
                anchors.top: parent.top
                width: 32
                height: 32
                color: closeMouse.containsMouse ? Theme.tint(Theme.ink, 0.08) : "transparent"
                border.width: 1
                border.color: Theme.line

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "✕"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 12
                }

                MouseArea {
                    id: closeMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.close()
                }
            }
        }

        Rectangle {
            id: drawerRule

            anchors.top: drawerHead.bottom
            anchors.topMargin: 18
            x: 22
            width: parent.width - 44
            height: 1
            color: Theme.line
        }

        // ---- END / FORCE END / CONTINUE / STOP SERVICE / REMOVE PACKAGE
        Column {
            id: drawerFoot

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            x: 22
            width: parent.width - 44
            spacing: 12
            visible: drawer.facts !== null

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.line
            }

            Text {
                textFormat: Text.PlainText
                visible: text !== "" && page.pendingAct === ""
                width: parent.width
                wrapMode: Text.Wrap
                text: page.actionNote !== "" ? page.actionNote
                    : page.armed !== "" ? (page.armed === "force" ? "FORCE END stops it at once: unsaved work in it is lost. Click again to do it."
                                          : page.armed === "stop" ? "The service stops (it may start again later). Click again to do it."
                                          : "Click again to do it.")
                    : drawer.guard && drawer.guard.text !== "" ? drawer.guard.text
                    : page.info && page.info.other ? "It belongs to another user: ending it asks for your password."
                    : !page.selectedAlive && drawer.facts ? "It has ended."
                    : ""
                color: page.actionNote !== "" ? (page.actionOk ? Theme.ink : Theme.alert)
                    : page.armed !== "" || (drawer.guard && drawer.guard.level !== "") ? Theme.alert : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 11
                lineHeight: 1.2
            }

            PasswordRow {
                id: passwordAsk

                visible: page.pendingAct !== ""
                width: parent.width
                label: "Your password, to " + (page.pendingAct === "stop" ? "stop the service" : page.pendingAct === "cont" ? "let it go on" : "end it")
                action: page.pendingAct === "force" ? "FORCE END" : page.pendingAct === "stop" ? "STOP" : page.pendingAct === "cont" ? "CONTINUE" : "END"
                onAccepted: password => {
                    var kind = page.pendingAct
                    page.pendingAct = ""
                    page.run(kind, password)
                }
                onCanceled: {
                    page.pendingAct = ""
                    page.actionNote = "Cancelled. Nothing was changed."
                    page.actionOk = true
                }
            }

            Flow {
                visible: page.pendingAct === ""
                width: parent.width
                spacing: 8

                ActButton {
                    key: "cont"
                    host: page
                    label: "CONTINUE"
                    visible: drawer.canEnd && page.selectedFlag === "stopped"
                }

                ActButton {
                    key: "stop"
                    host: page
                    label: "STOP SERVICE"
                    visible: drawer.canEnd && page.info.unit !== null && page.info.unit !== undefined
                }

                ActButton {
                    key: "end"
                    host: page
                    label: "END"
                    visible: drawer.canEnd
                }

                ActButton {
                    key: "force"
                    host: page
                    label: "FORCE END"
                    danger: true
                    visible: drawer.canEnd
                }

                ActButton {
                    key: "remove"
                    host: page
                    label: "REMOVE PROGRAM  →"
                    visible: drawer.facts !== null && (!!page.info.flatpak || (page.info.package !== null && page.info.package !== undefined))
                }
            }
        }

        // ---- facts, why it runs, the program
        Flickable {
            id: drawerScroll

            anchors.top: drawerRule.bottom
            anchors.topMargin: 18
            anchors.bottom: drawerFoot.visible ? drawerFoot.top : parent.bottom
            anchors.bottomMargin: 14
            x: 22
            width: parent.width - 44
            contentHeight: drawerBody.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: drawerBody

                width: drawerScroll.width
                spacing: 22

                Text {
                    textFormat: Text.PlainText
                    visible: page.info === null || page.info.ok === false
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: page.info === null ? "Looking it up…" : page.info.message || "Could not look it up."
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 12
                }

                // why it is tagged
                Rectangle {
                    readonly property bool bad: page.selectedFlag === "anr" || page.selectedFlag === "stuck"

                    visible: page.selectedFlag !== ""
                    width: parent.width
                    height: flagNote.implicitHeight + 24
                    color: bad ? Theme.tint(Theme.alert, 0.1) : Theme.tint(Theme.ink, 0.04)
                    border.width: 1
                    border.color: bad ? Theme.tint(Theme.alert, 0.55) : Theme.line

                    Text {
                        id: flagNote

                        textFormat: Text.PlainText
                        x: 14
                        y: 12
                        width: parent.width - 28
                        wrapMode: Text.Wrap
                        text: page.flagText(page.selectedFlag) + " — " + page.flagHint(page.selectedFlag)
                        color: parent.bad ? Theme.alert : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 11
                        lineHeight: 1.2
                    }
                }

                // the numbers, two to a line
                Grid {
                    visible: drawer.facts !== null
                    width: parent.width
                    columns: 2
                    rowSpacing: 18
                    columnSpacing: 20

                    Repeater {
                        model: drawer.facts ? [
                            ["CPU", page.current ? page.percent(page.current.cpu) : "—"],
                            ["MEMORY", page.bytes(page.current ? page.current.mem : drawer.facts.memory)],
                            ["STATE", page.stateText(page.current ? page.current.state : drawer.facts.state)],
                            ["THREADS", String(page.current ? page.current.threads : drawer.facts.threads)],
                            ["STARTED", drawer.facts.started],
                            ["USER", drawer.facts.user]
                        ] : []

                        delegate: Column {
                            required property var modelData

                            width: (drawerBody.width - 20) / 2
                            spacing: 6

                            Caption {
                                text: parent.modelData[0]
                                font.pixelSize: 9
                            }

                            Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                elide: Text.ElideRight
                                text: parent.modelData[1]
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                // why it runs
                Column {
                    visible: page.info !== null && page.info.lines !== undefined && page.info.lines.length > 0
                    width: parent.width
                    spacing: 12

                    Caption {
                        text: "WHY IT RUNS"
                    }

                    Repeater {
                        model: page.info && page.info.lines ? page.info.lines : []

                        delegate: Item {
                            required property var modelData

                            width: drawerBody.width
                            height: Math.max(20, reasonText.implicitHeight)

                            Text {
                                id: reasonGlyph

                                textFormat: Text.PlainText
                                width: 24
                                text: page.kindGlyph(parent.modelData.kind)
                                color: parent.modelData.kind === "core" || parent.modelData.kind === "kernel" ? Theme.alert : Theme.accent
                                font.family: parent.modelData.kind === "yakushi" ? Theme.mono : Theme.glyphs
                                font.pixelSize: 14
                            }

                            Text {
                                id: reasonText

                                textFormat: Text.PlainText
                                anchors.left: reasonGlyph.right
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                wrapMode: Text.Wrap
                                text: parent.modelData.text
                                color: Theme.ink
                                font.family: Theme.mono
                                font.pixelSize: 12
                                lineHeight: 1.25
                            }
                        }
                    }
                }

                // the program itself
                Column {
                    visible: drawer.facts !== null
                    width: parent.width
                    spacing: 8

                    Caption {
                        text: "PROGRAM"
                    }

                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: drawer.facts ? (drawer.facts.script || drawer.facts.program || "—") : ""
                        color: Theme.inkSoft
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }

                    Caption {
                        topPadding: 8
                        text: "COMMAND"
                    }

                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: drawer.facts ? (drawer.facts.command || "—") : ""
                        color: Theme.inkSoft
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
