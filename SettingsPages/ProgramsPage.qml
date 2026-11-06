import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Programs: remove a program without leaving anything behind.
//
// The page asks scripts/yakushi-removectl.py for the whole catalog once
// (every pacman package, every Flatpak app, what the Yakushi trash holds) and
// then searches, sorts and counts it itself: typing starts no program.
//
// Views: "search" (pick one, or tick several), "plan" (everything removing
// them would do; nothing changed yet) and "removed" (earlier removals, with
// UNDO). Removing: one password prompt (none for Flatpak apps installed for
// your user only), pacman -Rns / flatpak uninstall, your files moved to the
// Yakushi trash. Tasks -> REMOVE PACKAGE opens this page on that program's
// plan (SettingsWindow.openPrograms).
Item {
    id: panel

    property var hostWindow: null

    readonly property string helper: Quickshell.shellDir + "/scripts/yakushi-removectl.py"

    // ---- the catalog
    property var items: []
    property var byId: ({})
    property bool loaded: false
    property var counts: ({})
    property var sizes: ({})
    property var trashInfo: ({ count: 0, size: 0 })

    // ---- what you look at
    property string view: "search"       // search | plan | removed
    property string query: ""
    property string scope: "apps"        // apps | mine | unused | all
    property string order: "name"        // name | size | newest
    property var shown: []
    property real shownSize: 0

    // ---- ticked programs (several go in one plan)
    property var picked: ({})
    property int pickedCount: 0
    property real pickedSize: 0

    // ---- the plan, the trash
    property var plan: null
    property var target: []
    property bool cascade: false
    property var unticked: ({})          // files you unticked: path -> true
    property var history: []
    property string note: ""
    property bool noteOk: true
    property string armed: ""            // "remove", "empty:<id>" or "emptyall" waiting for a second click
    property bool done: false            // the plan was carried out
    property string doneId: ""

    // your password is asked right here, in the footer (no dialog behind
    // Settings); it goes to sudo through a pipe and is not kept
    property string pending: ""          // "remove" or "undo:<id>" waiting for the password
    property string secret: ""           // only between "OK" and the helper starting

    readonly property bool working: planJob.running || doJob.running || trashJob.running

    // ---- a request from Tasks (REMOVE PACKAGE)
    onHostWindowChanged: takeRequest()

    function takeRequest() {
        if (!hostWindow || !hostWindow.pendingRemove)
            return
        var names = hostWindow.pendingRemove
        hostWindow.pendingRemove = null
        openPlan(names)
    }

    Component.onCompleted: {
        loadCatalog()
        trashJob.command = ["python3", helper, "removed"]
        trashJob.running = true
    }

    // ------------------------------------------------------------------
    // The catalog, and what is shown of it
    // ------------------------------------------------------------------
    function loadCatalog() {
        if (catalogJob.running)
            return
        catalogJob.running = true
    }

    function label(it) {
        return it.title !== "" ? it.title : it.name
    }

    function inScope(it, sc) {
        return sc === "apps" ? it.app : sc === "mine" ? it.explicit : sc === "unused" ? it.unused : true
    }

    function takeCatalog(d) {
        var list = d.items || []
        var map = {}
        var c = { apps: 0, mine: 0, unused: 0, all: 0 }
        var z = { apps: 0, mine: 0, unused: 0, all: 0 }
        for (var i = 0; i < list.length; i++) {
            var it = list[i]
            it.label = label(it)
            it.hay = (it.label + " " + it.name + " " + it.desc).toLowerCase()
            map[it.id] = it
            for (var k in c) {
                if (inScope(it, k)) {
                    c[k]++
                    z[k] += it.size
                }
            }
        }
        items = list
        byId = map
        counts = c
        sizes = z
        trashInfo = d.trash || trashInfo
        loaded = true
        // ticks on programs that are gone are dropped
        var keep = {}
        for (var id in picked)
            if (map[id] !== undefined && map[id].protected === "")
                keep[id] = true
        setPicked(keep)
        refilter()
    }

    function refilter() {
        var q = query.trim().toLowerCase()
        var out = []
        var total = 0
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (!inScope(it, scope) || (q !== "" && it.hay.indexOf(q) < 0))
                continue
            out.push(it)
            total += it.size
        }
        var by = order
        out.sort(function(a, b) {
            if (by === "size")
                return b.size - a.size
            if (by === "newest")
                return b.installed - a.installed
            if (q !== "") {        // names that start with what you typed first
                var pa = a.label.toLowerCase().indexOf(q) === 0 || a.name.indexOf(q) === 0
                var pb = b.label.toLowerCase().indexOf(q) === 0 || b.name.indexOf(q) === 0
                if (pa !== pb)
                    return pa ? -1 : 1
            }
            var x = a.label.toLowerCase(), y = b.label.toLowerCase()
            return x < y ? -1 : x > y ? 1 : 0
        })
        shown = out
        shownSize = total
    }

    onScopeChanged: refilter()
    onOrderChanged: refilter()
    onQueryChanged: refilter()

    // ---- ticks
    function setPicked(map) {
        var n = 0, z = 0
        for (var id in map) {
            n++
            z += byId[id] ? byId[id].size : 0
        }
        picked = map
        pickedCount = n
        pickedSize = z
    }

    function togglePick(it) {
        if (it.protected !== "")
            return
        var copy = Object.assign({}, picked)
        if (copy[it.id])
            delete copy[it.id]
        else
            copy[it.id] = true
        setPicked(copy)
    }

    function pickAllShown() {
        var copy = Object.assign({}, picked)
        for (var i = 0; i < shown.length; i++)
            if (shown[i].protected === "")
                copy[shown[i].id] = true
        setPicked(copy)
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------
    function openSearch() {
        pending = ""
        view = "search"
        note = ""
        armed = ""
    }

    function openFirst() {
        for (var i = 0; i < shown.length; i++)
            if (shown[i].protected === "") {
                openPlan([shown[i].id])
                return
            }
    }

    function openPlan(names) {
        pending = ""
        view = "plan"
        target = names
        cascade = false
        unticked = {}
        done = false
        doneId = ""
        armed = ""
        note = ""
        plan = null
        runPlan()
    }

    function openRemoved() {
        pending = ""
        view = "removed"
        note = ""
        armed = ""
        if (!trashJob.running) {
            trashJob.command = ["python3", helper, "removed"]
            trashJob.running = true
        }
    }

    // ---- helper calls
    function runPlan() {
        plan = null
        planJob.command = ["python3", helper, "plan", JSON.stringify({ target: target, cascade: cascade })]
        planJob.running = true
    }

    function chosenFiles() {
        if (!plan || !plan.files)
            return []
        return plan.files.filter(function(f) { return panel.ticked(f) }).map(function(f) { return f.path })
    }

    function ticked(f) {
        var u = unticked[f.path]
        return u === undefined ? f.checked : !u
    }

    function toggle(f) {
        var copy = Object.assign({}, unticked)
        copy[f.path] = ticked(f)
        unticked = copy
    }

    function doRemove() {
        if (!plan || !plan.canRemove || working || done)
            return
        if (armed !== "remove") {
            armed = "remove"
            disarm.restart()
            return
        }
        armed = ""
        note = ""
        if (plan.needsRoot === false)
            startRemove("")
        else
            askPassword("remove")
    }

    function startRemove(pw) {
        note = "Removing…"
        noteOk = true
        secret = pw
        doJob.stdinEnabled = pw !== ""
        doJob.command = ["python3", helper].concat(pw !== "" ? ["--password-stdin"] : [])
            .concat(["remove", JSON.stringify({ target: target, cascade: cascade, files: chosenFiles() })])
        doJob.running = true
    }

    function undo(entry) {
        if (working)
            return
        note = ""
        if (entry.needsRoot === false)
            startUndo(entry.id, "")
        else
            askPassword("undo:" + entry.id)
    }

    function startUndo(id, pw) {
        note = "Putting it back… (reinstalling needs the internet)"
        noteOk = true
        secret = pw
        trashJob.stdinEnabled = pw !== ""
        trashJob.command = ["python3", helper].concat(pw !== "" ? ["--password-stdin"] : []).concat(["undo", id])
        trashJob.running = true
    }

    function empty(id) {
        if (working)
            return
        if (armed !== "empty:" + id) {
            armed = "empty:" + id
            disarm.restart()
            return
        }
        armed = ""
        trashJob.command = ["python3", helper, "empty", id]
        trashJob.running = true
    }

    function emptyAll() {
        if (working || history.length === 0)
            return
        if (armed !== "emptyall") {
            armed = "emptyall"
            disarm.restart()
            return
        }
        armed = ""
        trashJob.command = ["python3", helper, "empty-all"]
        trashJob.running = true
    }

    function askPassword(what) {
        pending = what
        passwordRow.error = ""
        Qt.callLater(passwordRow.open)
    }

    function withPassword(pw) {
        var what = pending
        pending = ""
        if (what === "remove")
            startRemove(pw)
        else if (what.indexOf("undo:") === 0)
            startUndo(what.slice(5), pw)
    }

    function giveSecret(job) {
        job.write(secret + "\n")
        secret = ""
        job.stdinEnabled = false          // closes its stdin
    }

    function wrongPassword(what) {
        askPassword(what)
        passwordRow.error = "Wrong password. Try again."
        note = ""
    }

    function say(text, ok) {
        note = text
        noteOk = ok
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: panel.armed = ""
    }

    function parse(text) {
        try {
            return JSON.parse(text)
        } catch (e) {
            return { ok: false, message: "No answer from the helper." }
        }
    }

    Process {
        id: catalogJob
        command: ["python3", panel.helper, "catalog"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.ok === false)
                    panel.say(d.message, false)
                else
                    panel.takeCatalog(d)
            }
        }
    }

    Process {
        id: planJob
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.ok === false) {
                    panel.say(d.message, false)
                    panel.plan = { failed: true }
                } else {
                    panel.plan = d
                }
            }
        }
    }

    Process {
        id: doJob

        onStarted: if (stdinEnabled) panel.giveSecret(doJob)
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.wrongPassword) {
                    panel.wrongPassword("remove")
                    return
                }
                panel.say(d.message || "", d.ok !== false)
                if (d.ok !== false) {
                    panel.done = true
                    panel.doneId = d.id || ""
                    panel.setPicked({})
                    panel.loadCatalog()
                    trashJob.command = ["python3", panel.helper, "removed"]     // the count on top
                    Qt.callLater(function() { if (!trashJob.running) trashJob.running = true })
                }
            }
        }
    }

    Process {
        id: trashJob

        onStarted: if (stdinEnabled) panel.giveSecret(trashJob)
        stdout: StdioCollector {
            onStreamFinished: {
                var d = panel.parse(text)
                if (d.removed !== undefined) {
                    panel.history = d.removed
                    var kept = 0
                    for (var i = 0; i < d.removed.length; i++)
                        kept += d.removed[i].keptSize || 0
                    panel.trashInfo = { count: d.removed.length, size: kept }
                    return
                }
                if (d.wrongPassword) {
                    panel.wrongPassword("undo:" + trashJob.command[trashJob.command.length - 1])
                    return
                }
                panel.say(d.message || "", d.ok !== false)
                if (d.ok !== false)
                    panel.loadCatalog()           // undo put programs back
                if (panel.view !== "removed" && d.ok !== false) {
                    panel.done = false            // undone from the result view
                    panel.doneId = ""
                    panel.plan = null
                    panel.view = "removed"
                }
                trashJob.command = ["python3", panel.helper, "removed"]
                Qt.callLater(function() { trashJob.running = true })
            }
        }
    }

    // ------------------------------------------------------------------
    // Words
    // ------------------------------------------------------------------
    function bytes(n) {
        if (!n)
            return "0 KB"
        if (n >= 1073741824)
            return (n / 1073741824).toFixed(1) + " GB"
        if (n >= 1048576)
            return Math.round(n / 1048576) + " MB"
        return Math.max(1, Math.round(n / 1024)) + " KB"
    }

    function age(t) {
        if (!t)
            return ""
        var days = Math.floor((Date.now() / 1000 - t) / 86400)
        return days <= 0 ? "today" : days === 1 ? "yesterday" : days < 14 ? days + " days ago"
            : days < 60 ? Math.round(days / 7) + " weeks ago" : days < 730 ? Math.round(days / 30) + " months ago"
            : Math.round(days / 365) + " years ago"
    }

    readonly property real filesSize: {
        var t = 0
        if (plan && plan.files)
            for (var i = 0; i < plan.files.length; i++)
                if (ticked(plan.files[i]))
                    t += plan.files[i].size
        return t
    }

    // the biggest one shown: the size bars are measured against it
    readonly property real biggest: {
        var m = 1
        for (var i = 0; i < Math.min(shown.length, 400); i++)
            m = Math.max(m, shown[i].size || 0)
        return m
    }

    // "Discord ×12, Zen ×6" from the processes that close
    function runningText(list) {
        var n = {}, order = []
        for (var i = 0; i < list.length; i++) {
            if (n[list[i].name] === undefined) {
                n[list[i].name] = 0
                order.push(list[i].name)
            }
            n[list[i].name]++
        }
        return order.map(function(k) { return n[k] > 1 ? k + " ×" + n[k] : k }).join(", ")
    }

    // ------------------------------------------------------------------
    // Small parts (kept free of outer ids)
    // ------------------------------------------------------------------
    component Caption: Text {
        textFormat: Text.PlainText
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    component Plain: Text {
        textFormat: Text.PlainText
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 12
        lineHeight: 1.25
    }

    component Pill: Rectangle {
        id: pill

        property string label: ""
        property bool danger: false
        property bool hot: false
        property bool on: true

        signal clicked()

        width: pillText.implicitWidth + 30
        height: 36
        opacity: on ? 1 : 0.4
        color: hot ? Theme.tint(Theme.alert, 0.3)
            : danger ? (pillMouse.containsMouse ? Theme.tint(Theme.alert, 0.18) : "transparent")
            : Theme.tint(Theme.accent, pillMouse.containsMouse ? 0.24 : 0.1)
        border.width: 1
        border.color: danger || hot ? Theme.alert : Theme.tint(Theme.accent, 0.6)

        Text {
            id: pillText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: pill.label
            color: pill.danger || pill.hot ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        MouseArea {
            id: pillMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: pill.on
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    // a titled block of the plan
    component Section: Column {
        property string title: ""

        width: parent ? parent.width : 0
        spacing: 10

        Caption {
            text: parent.title
        }
    }

    // the app's own icon; a letter (apps) or a package mark when it has none
    component AppIcon: Item {
        id: icon

        property var item: null
        property int size: 32

        readonly property string source: {
            if (!item || !item.icon)
                return ""
            if (item.icon.charAt(0) === "/")
                return "file://" + item.icon
            return Quickshell.iconPath(item.icon, true)
        }

        width: size
        height: size

        Rectangle {
            anchors.fill: parent
            visible: picture.status !== Image.Ready
            color: Theme.tint(Theme.ink, 0.05)
            border.width: 1
            border.color: Theme.line

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: icon.item && icon.item.app ? (icon.item.label || "?").charAt(0).toUpperCase() : String.fromCodePoint(0xF03D7)
                color: Theme.inkMute
                font.family: icon.item && icon.item.app ? Theme.mono : Theme.glyphs
                font.pixelSize: Math.round(icon.size * 0.45)
                font.bold: icon.item && icon.item.app
            }
        }

        Image {
            id: picture

            anchors.fill: parent
            source: icon.source
            sourceSize: Qt.size(icon.size * 2, icon.size * 2)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            visible: status === Image.Ready
        }
    }

    // a square to tick
    component Tick: Rectangle {
        property bool on: false

        width: 16
        height: 16
        color: on ? Theme.accent : "transparent"
        border.width: 1
        border.color: on ? Theme.accent : Theme.lineHot

        Text {
            textFormat: Text.PlainText
            visible: parent.on
            anchors.centerIn: parent
            text: "✓"
            color: Theme.surface
            font.family: Theme.mono
            font.pixelSize: 11
            font.bold: true
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
            anchors.right: views.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            title: "PROGRAMS"
        }

        Segmented {
            id: views

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            current: panel.view
            options: [["search", "INSTALLED"], ["removed", "REMOVED BEFORE"]]
            counts: panel.history.length ? { removed: panel.history.length } : ({})
            onChose: key => key === "search" ? panel.openSearch() : panel.openRemoved()
        }
    }

    // ---- footer: what happened / the big button / what is ticked
    Item {
        id: foot

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 68

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.line
            clip: true

            // while something runs, a block moves along the line
            Rectangle {
                id: sweep

                visible: doJob.running || trashJob.stdinEnabled || (trashJob.running && panel.note !== "")
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

            visible: panel.pending !== ""
            z: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: panel.pending === "remove" ? "Your password, to remove " + (panel.plan && panel.plan.titles ? panel.plan.titles.join(", ") : "it")
                : "Your password, to put it back"
            action: panel.pending === "remove" ? "REMOVE" : "UNDO"
            onAccepted: password => panel.withPassword(password)
            onCanceled: {
                panel.pending = ""
                panel.note = "Cancelled. Nothing was changed."
                panel.noteOk = true
            }
        }

        readonly property bool showTicks: panel.view === "search" && panel.pickedCount > 0 && panel.note === ""

        Text {
            textFormat: Text.PlainText
            visible: panel.pending === ""
            anchors.left: parent.left
            anchors.right: footButtons.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: foot.showTicks
                ? panel.pickedCount + (panel.pickedCount === 1 ? " program ticked" : " programs ticked") + "  ·  " + panel.bytes(panel.pickedSize)
                : panel.note !== "" ? panel.note
                : panel.armed === "remove" ? (panel.plan && panel.plan.needsRoot === false
                                              ? "Click REMOVE again to remove it." : "Click REMOVE again; then your password is asked here.")
                : panel.armed === "emptyall" ? "Click again: everything in the Yakushi trash is deleted for good."
                : panel.view === "plan" && panel.plan && panel.plan.canRemove
                    ? "Frees about " + panel.bytes((panel.plan.freed || 0) + panel.filesSize)
                      + ". Your files go to the Yakushi trash: UNDO can bring everything back."
                : panel.view === "search" ? "Click a program to see what removing it would do, or tick several. Nothing changes yet."
                : panel.view === "removed" ? "UNDO reinstalls the programs and puts your files and services back."
                : ""
            color: foot.showTicks ? Theme.ink
                : panel.note !== "" ? (panel.noteOk ? Theme.ink : Theme.alert)
                : panel.armed !== "" ? Theme.alert : Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            lineHeight: 1.2
        }

        Row {
            id: footButtons

            visible: panel.pending === ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Pill {
                visible: panel.view === "search" && panel.pickedCount > 0
                label: "CLEAR"
                onClicked: {
                    panel.setPicked({})
                    panel.note = ""
                }
            }

            Pill {
                visible: panel.view === "search" && panel.pickedCount > 0
                label: "REVIEW REMOVAL  →"
                onClicked: panel.openPlan(Object.keys(panel.picked))
            }

            Pill {
                visible: panel.view === "plan" && panel.done && panel.doneId !== ""
                label: "UNDO"
                on: !panel.working
                onClicked: panel.undo({ id: panel.doneId, needsRoot: panel.plan ? panel.plan.needsRoot : true })
            }

            Pill {
                visible: panel.view === "plan" && !panel.done
                label: panel.armed === "remove" ? "CLICK AGAIN" : doJob.running ? "REMOVING…" : "REMOVE"
                danger: true
                hot: panel.armed === "remove"
                on: panel.plan !== null && panel.plan.canRemove === true && !panel.working
                onClicked: panel.doRemove()
            }
        }
    }

    // ==================================================================
    // search: pick one, or tick several
    // ==================================================================
    Item {
        id: searchView

        visible: panel.view === "search"
        anchors.top: head.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: foot.top
        anchors.bottomMargin: 6

        // which: the four groups, with how many and how much space
        Row {
            id: scopes

            width: parent.width
            spacing: 10

            readonly property real cell: (width - spacing * 3) / 4

            Repeater {
                model: [["apps", "APPS"], ["mine", "YOU INSTALLED"], ["unused", "UNUSED"], ["all", "EVERYTHING"]]

                delegate: Rectangle {
                    id: scopeTile

                    required property var modelData
                    readonly property string key: modelData[0]
                    readonly property bool on: panel.scope === key

                    width: scopes.cell
                    height: 66
                    color: on ? Theme.tint(Theme.accent, 0.1) : tileMouse.containsMouse ? Theme.tint(Theme.ink, 0.04) : Theme.card
                    border.width: 1
                    border.color: on ? Theme.tint(Theme.accent, 0.55) : Theme.line

                    Behavior on color {
                        ColorAnimation { duration: Theme.tFast }
                    }

                    Rectangle {
                        visible: scopeTile.on
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 2
                        color: Theme.accent
                    }

                    Caption {
                        x: 14
                        y: 12
                        width: parent.width - 28
                        elide: Text.ElideRight
                        text: scopeTile.modelData[1]
                        font.pixelSize: 9
                        color: scopeTile.on ? Theme.ink : Theme.inkMute
                    }

                    Text {
                        id: tileCount

                        textFormat: Text.PlainText
                        x: 14
                        y: 30
                        text: panel.loaded ? String(panel.counts[scopeTile.key] || 0) : "…"
                        color: scopeTile.key === "unused" && (panel.counts.unused || 0) > 0 ? Theme.alert : Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 18
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: tileCount.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.baseline: tileCount.baseline
                        elide: Text.ElideRight
                        text: panel.loaded ? panel.bytes(panel.sizes[scopeTile.key] || 0) : ""
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: tileMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.scope = scopeTile.key
                    }
                }
            }
        }

        // search, order
        Item {
            id: searchTools

            anchors.top: scopes.bottom
            anchors.topMargin: 16
            width: parent.width
            height: 36

            Rectangle {
                anchors.left: parent.left
                anchors.right: orderSwitch.left
                anchors.rightMargin: 12
                height: 36
                color: Theme.tint(Theme.ink, 0.03)
                border.width: 1
                border.color: searchBox.activeFocus ? Theme.accent : Theme.line

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
                    id: searchBox

                    anchors.left: lens.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    selectByMouse: true
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    Keys.onReturnPressed: panel.openFirst()
                    Keys.onEnterPressed: panel.openFirst()
                    // Esc clears the search; on an empty one it closes Settings
                    Keys.onEscapePressed: event => {
                        if (text !== "")
                            text = ""
                        else
                            event.accepted = false
                    }
                    onTextChanged: panel.query = text

                    Text {
                        textFormat: Text.PlainText
                        visible: searchBox.text === "" && !searchBox.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        elide: Text.ElideRight
                        text: "Search by name or description"
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }
                }
            }

            Segmented {
                id: orderSwitch

                anchors.right: parent.right
                current: panel.order
                options: [["name", "A–Z"], ["size", "LARGEST"], ["newest", "NEWEST"]]
                onChose: key => panel.order = key
            }
        }

        // how many, how much; tick all; the size column
        Item {
            id: listHead

            anchors.top: searchTools.bottom
            anchors.topMargin: 16
            width: parent.width
            height: 30

            Caption {
                id: shownText

                x: 2
                anchors.verticalCenter: parent.verticalCenter
                text: panel.loaded ? panel.shown.length + (panel.shown.length === 1 ? " PROGRAM" : " PROGRAMS")
                                     + "  ·  " + panel.bytes(panel.shownSize) : "READING…"
            }

            Text {
                textFormat: Text.PlainText
                visible: panel.scope === "unused" && panel.shown.some(function(p) { return p.protected === "" })
                anchors.left: shownText.right
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "TICK ALL"
                color: tickAllMouse.containsMouse ? Theme.ink : Theme.accent
                font.family: Theme.mono
                font.pixelSize: 10
                font.letterSpacing: 2

                MouseArea {
                    id: tickAllMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.pickAllShown()
                }
            }

            Caption {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: panel.order === "newest" ? "INSTALLED" : "SIZE"
                color: panel.order !== "name" ? Theme.accent : Theme.inkMute
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.line
            }
        }

        ListView {
            id: pkgList

            anchors.top: listHead.bottom
            anchors.topMargin: 2
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: panel.shown
            reuseItems: true
            cacheBuffer: 320

            delegate: Rectangle {
                id: pkgRow

                required property var modelData
                readonly property bool locked: modelData.protected !== ""
                readonly property bool on: panel.picked[modelData.id] === true

                width: pkgList.width
                height: 64
                color: on ? Theme.tint(Theme.accent, 0.08)
                    : pkgMouse.containsMouse && !locked ? Theme.tint(Theme.ink, 0.045) : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.tFast }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    x: 16
                    width: parent.width - 32
                    height: 1
                    color: Theme.tint(Theme.ink, 0.05)
                }

                // the row opens the plan; the tick on the left only ticks
                MouseArea {
                    id: pkgMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !pkgRow.locked
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.openPlan([pkgRow.modelData.id])
                }

                Item {
                    id: tickArea

                    width: 44
                    height: parent.height

                    Tick {
                        visible: !pkgRow.locked
                        anchors.centerIn: parent
                        on: pkgRow.on
                        border.color: pkgRow.on ? Theme.accent : tickMouse.containsMouse ? Theme.ink : Theme.lineHot
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: pkgRow.locked
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF033E)
                        color: Theme.inkMute
                        font.family: Theme.glyphs
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: tickMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !pkgRow.locked
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.togglePick(pkgRow.modelData)
                    }
                }

                AppIcon {
                    id: rowIcon

                    x: 44
                    anchors.verticalCenter: parent.verticalCenter
                    size: 32
                    item: pkgRow.modelData
                    opacity: pkgRow.locked ? 0.55 : 1
                }

                Text {
                    id: pkgName

                    textFormat: Text.PlainText
                    anchors.left: rowIcon.right
                    anchors.leftMargin: 14
                    anchors.right: pkgTag.visible ? pkgTag.left : pkgSize.left
                    anchors.rightMargin: 14
                    anchors.bottom: parent.verticalCenter
                    anchors.bottomMargin: 1
                    elide: Text.ElideRight
                    text: pkgRow.modelData.label
                    color: pkgRow.locked ? Theme.inkSoft : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 13
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: pkgName.left
                    anchors.right: pkgSize.left
                    anchors.rightMargin: 14
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 5
                    elide: Text.ElideRight
                    text: {
                        var m = pkgRow.modelData
                        if (pkgRow.locked)
                            return "Protected: " + m.protected
                        var bits = []
                        if (m.title !== "" && m.kind === "pkg")
                            bits.push(m.name)
                        if (m.desc)
                            bits.push(m.desc)
                        if (m.neededCount > 0)
                            bits.push("needed by " + m.neededBy.join(", ") + (m.neededCount > 3 ? " +" + (m.neededCount - 3) : ""))
                        return bits.join("  ·  ")
                    }
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                // only what is worth a mark: FLATPAK, UNUSED, PROTECTED
                Rectangle {
                    id: pkgTag

                    readonly property string kind: pkgRow.locked ? "protected" : pkgRow.modelData.kind === "flatpak" ? "flatpak"
                        : pkgRow.modelData.unused ? "unused" : ""
                    readonly property color tone: kind === "unused" ? Theme.alert : kind === "flatpak" ? Theme.accent : Theme.inkMute

                    visible: kind !== ""
                    anchors.right: pkgSize.left
                    anchors.rightMargin: 18
                    anchors.bottom: parent.verticalCenter
                    anchors.bottomMargin: -2
                    width: pkgTagText.implicitWidth + 16
                    height: 20
                    color: Theme.tint(tone, 0.08)
                    border.width: 1
                    border.color: Theme.tint(tone, 0.45)

                    Text {
                        id: pkgTagText

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: pkgTag.kind.toUpperCase()
                        color: pkgTag.tone
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                }

                // size (or when it came), with a bar against the biggest one
                Item {
                    id: pkgSize

                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    height: 34

                    Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: panel.order === "newest" ? panel.age(pkgRow.modelData.installed) : panel.bytes(pkgRow.modelData.size)
                        color: panel.order !== "newest" && pkgRow.modelData.size >= 104857600 ? Theme.ink : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 12
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: panel.order !== "size"
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: panel.order === "newest" ? panel.bytes(pkgRow.modelData.size) : panel.age(pkgRow.modelData.installed)
                        color: Theme.inkMute
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }

                    Rectangle {
                        visible: panel.order === "size"
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: parent.width
                        height: 3
                        color: Theme.groove

                        Rectangle {
                            anchors.right: parent.right
                            width: Math.max(2, parent.width * (pkgRow.modelData.size || 0) / panel.biggest)
                            height: parent.height
                            color: Theme.tint(Theme.accent, 0.7)
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: pkgList.count === 0
                anchors.centerIn: parent
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: !panel.loaded ? "Reading what is installed…"
                    : panel.query !== "" ? "No program matches “" + panel.query + "”."
                    : panel.scope === "unused" ? "Nothing unused: clean." : "Nothing here."
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 12
            }
        }

        ScrollHint {
            flick: pkgList
        }
    }

    // ==================================================================
    // plan: everything removing it would do
    // ==================================================================
    Item {
        id: planView

        visible: panel.view === "plan"
        anchors.top: head.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: foot.top
        anchors.bottomMargin: 6

        Flickable {
            id: body

            anchors.fill: parent
            contentHeight: column.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: column

                width: body.width
                spacing: 24

                // back, and what this is about
                Rectangle {
                    id: hero

                    width: parent.width
                    height: 98
                    color: Theme.card
                    border.width: 1
                    border.color: panel.done ? Theme.tint(Theme.good, 0.5) : Theme.line

                    Rectangle {
                        width: 3
                        height: parent.height
                        color: panel.done ? Theme.good : Theme.accent
                    }

                    Row {
                        id: heroIcons

                        x: 22
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: -10

                        Repeater {
                            model: panel.target.slice(0, 4)

                            delegate: Rectangle {
                                required property var modelData

                                width: 48
                                height: 48
                                color: Theme.card
                                border.width: 2
                                border.color: Theme.card

                                AppIcon {
                                    anchors.centerIn: parent
                                    size: 44
                                    item: panel.byId[parent.modelData] || ({ app: true, label: String(parent.modelData).replace("flatpak:", ""), icon: "" })
                                }
                            }
                        }
                    }

                    Column {
                        anchors.left: heroIcons.right
                        anchors.leftMargin: 18
                        anchors.right: backButton.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            elide: Text.ElideRight
                            text: (panel.done ? "Removed " : "Remove ")
                                + (panel.plan && panel.plan.titles && panel.plan.titles.length
                                   ? panel.plan.titles.join(", ")
                                   : panel.target.map(function(t) { return panel.byId[t] ? panel.byId[t].label : t }).join(", "))
                            color: Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 16
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: {
                                var p = panel.plan
                                if (p === null)
                                    return "Working out what removing it would do… nothing is changed."
                                if (p.failed)
                                    return "This could not be planned: " + panel.note
                                if (!p.remove || p.remove.length === 0)
                                    return p.blocked && Object.keys(p.blocked).length ? "Other programs need it: see below." : ""
                                var n = p.remove.length
                                var files = panel.chosenFiles().length
                                var bits = [n + (n === 1 ? " item goes" : " items go")]
                                if (p.running && p.running.length)
                                    bits.push(p.running.length + (p.running.length === 1 ? " process closes" : " processes close"))
                                if (p.units && p.units.system.length + p.units.user.length)
                                    bits.push((p.units.system.length + p.units.user.length) + " service(s) off")
                                if (files)
                                    bits.push(files + (files === 1 ? " folder" : " folders") + " to the trash")
                                bits.push("about " + panel.bytes((p.freed || 0) + panel.filesSize) + " freed")
                                return bits.join("  ·  ")
                            }
                            color: panel.plan && panel.plan.failed ? Theme.alert : Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 11
                            lineHeight: 1.2
                        }
                    }

                    Pill {
                        id: backButton

                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        label: "←  BACK"
                        onClicked: panel.openSearch()
                    }
                }

                // other programs need it
                Section {
                    visible: panel.plan !== null && panel.plan.blocked !== undefined
                             && Object.keys(panel.plan.blocked).length > 0
                    title: "OTHER PROGRAMS NEED IT"

                    Repeater {
                        model: panel.plan && panel.plan.blocked ? Object.keys(panel.plan.blocked) : []

                        delegate: Plain {
                            required property var modelData
                            text: modelData + " is needed by " + panel.plan.blocked[modelData].join(", ") + "."
                        }
                    }

                    Plain {
                        text: "Removing it alone would break them. Remove them too, or keep it."
                        color: Theme.inkSoft
                    }

                    Row {
                        spacing: 8
                        topPadding: 4

                        Pill {
                            label: "REMOVE THEM TOO"
                            danger: true
                            on: !panel.working
                            onClicked: {
                                panel.cascade = true
                                panel.runPlan()
                            }
                        }

                        Pill {
                            label: "KEEP IT"
                            onClicked: panel.openSearch()
                        }
                    }
                }

                // protected: never here
                Rectangle {
                    visible: panel.plan !== null && panel.plan.protected !== undefined
                             && panel.plan.protected.length > 0
                    width: parent.width
                    height: protectedText.implicitHeight + 32
                    color: Theme.tint(Theme.alert, 0.08)
                    border.width: 1
                    border.color: Theme.tint(Theme.alert, 0.5)

                    Plain {
                        id: protectedText

                        x: 18
                        y: 16
                        width: parent.width - 36
                        color: Theme.alert
                        text: panel.plan && panel.plan.protected
                            ? "This cannot be removed here: " + panel.plan.protected.map(function(g) { return g.name + " (" + g.reason + ")" }).join(", ") + "."
                            : ""
                    }
                }

                // what goes
                Section {
                    visible: panel.plan !== null && panel.plan.remove !== undefined && panel.plan.remove.length > 0
                    title: panel.done ? "REMOVED" : "WHAT GOES"

                    Column {
                        width: parent.width

                        Repeater {
                            model: panel.plan && panel.plan.remove ? panel.plan.remove : []

                            delegate: Item {
                                id: goRow

                                required property var modelData

                                width: column.width
                                height: 50

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: Theme.tint(Theme.ink, 0.05)
                                }

                                AppIcon {
                                    id: goIcon

                                    x: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 24
                                    item: panel.byId[goRow.modelData.id || goRow.modelData.name] || ({ app: false, label: goRow.modelData.name, icon: "" })
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.left: goIcon.right
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: goWhy.left
                                    anchors.rightMargin: 14
                                    elide: Text.ElideRight
                                    text: goRow.modelData.name + (goRow.modelData.desc ? "  —  " + goRow.modelData.desc : "")
                                    color: Theme.ink
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                }

                                Text {
                                    id: goWhy

                                    textFormat: Text.PlainText
                                    anchors.right: goSize.left
                                    anchors.rightMargin: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, column.width * 0.36)
                                    elide: Text.ElideRight
                                    text: goRow.modelData.why
                                    color: goRow.modelData.why.indexOf("you chose it") === 0 ? Theme.accent : Theme.inkMute
                                    font.family: Theme.mono
                                    font.pixelSize: 11
                                }

                                Text {
                                    id: goSize

                                    textFormat: Text.PlainText
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 76
                                    horizontalAlignment: Text.AlignRight
                                    text: panel.bytes(goRow.modelData.size)
                                    color: Theme.inkSoft
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                // Yakushi features that stop working / cannot be undone
                Column {
                    visible: (panel.plan !== null && panel.plan.soft !== undefined && panel.plan.soft.length > 0)
                             || notInRepos.visible
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: panel.plan && panel.plan.soft ? panel.plan.soft : []

                        delegate: Plain {
                            required property var modelData
                            color: Theme.alert
                            text: "Yakushi uses " + modelData.name + " for " + modelData.reason + ": that stops working."
                        }
                    }

                    Plain {
                        id: notInRepos

                        visible: panel.plan !== null && panel.plan.notInRepos !== undefined
                                 && panel.plan.notInRepos.length > 0 && !panel.done
                        color: Theme.alert
                        text: panel.plan && panel.plan.notInRepos
                            ? "Not in the official repositories: " + panel.plan.notInRepos.join(", ")
                              + ". UNDO can put your files back, but cannot reinstall " + (panel.plan.notInRepos.length === 1 ? "it." : "them.")
                            : ""
                    }
                }

                // running, services, config
                Section {
                    visible: panel.plan !== null && panel.plan.running !== undefined
                             && (panel.plan.running.length > 0 || panel.plan.units.system.length > 0
                                 || panel.plan.units.user.length > 0 || panel.plan.mentions.length > 0)
                    title: "ALSO"

                    Plain {
                        visible: panel.plan !== null && panel.plan.running !== undefined && panel.plan.running.length > 0
                        text: panel.plan && panel.plan.running ? "Closed: " + panel.runningText(panel.plan.running) + "." : ""
                    }

                    Plain {
                        visible: panel.plan !== null && panel.plan.units !== undefined
                                 && panel.plan.units.system.length + panel.plan.units.user.length > 0
                        text: panel.plan && panel.plan.units
                            ? "Turned off: " + panel.plan.units.system.concat(panel.plan.units.user).join(", ") + "."
                            : ""
                    }

                    Repeater {
                        model: panel.plan && panel.plan.mentions ? panel.plan.mentions : []

                        delegate: Plain {
                            required property var modelData
                            color: Theme.inkSoft
                            text: modelData
                        }
                    }
                }

                // your files
                Section {
                    visible: panel.plan !== null && panel.plan.files !== undefined && panel.plan.files.length > 0
                    title: panel.done ? "YOUR FILES" : "YOUR FILES  ·  ticked ones go to the Yakushi trash"

                    Column {
                        width: parent.width

                        Repeater {
                            model: panel.plan && panel.plan.files ? panel.plan.files : []

                            delegate: Rectangle {
                                id: fileRow

                                required property var modelData
                                readonly property bool on: panel.ticked(modelData)

                                width: column.width
                                height: fileRow.modelData.note ? 56 : 46
                                color: fileMouse.containsMouse && !panel.done ? Theme.tint(Theme.ink, 0.045) : "transparent"

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: Theme.tint(Theme.ink, 0.05)
                                }

                                Tick {
                                    id: box

                                    x: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    on: fileRow.on
                                }

                                Text {
                                    id: filePath

                                    textFormat: Text.PlainText
                                    anchors.left: box.right
                                    anchors.leftMargin: 14
                                    anchors.right: fileSize.left
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: fileRow.modelData.note ? undefined : parent.verticalCenter
                                    anchors.bottom: fileRow.modelData.note ? parent.verticalCenter : undefined
                                    elide: Text.ElideMiddle
                                    text: fileRow.modelData.path
                                    color: fileRow.on ? Theme.ink : Theme.inkSoft
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    visible: fileRow.modelData.note !== ""
                                    anchors.left: filePath.left
                                    anchors.right: filePath.right
                                    anchors.top: parent.verticalCenter
                                    anchors.topMargin: 4
                                    elide: Text.ElideRight
                                    text: fileRow.modelData.note + (fileRow.modelData.checked ? "" : "  ·  left in place unless you tick it")
                                    color: fileRow.modelData.checked ? Theme.inkMute : Theme.tint(Theme.accent, 0.85)
                                    font.family: Theme.mono
                                    font.pixelSize: 11
                                }

                                Text {
                                    id: fileSize

                                    textFormat: Text.PlainText
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (fileRow.modelData.partial ? "≥ " : "") + panel.bytes(fileRow.modelData.size)
                                    color: Theme.inkSoft
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: fileMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !panel.done && !panel.working
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.toggle(fileRow.modelData)
                                }
                            }
                        }
                    }
                }

                Plain {
                    visible: panel.plan !== null && panel.plan.files !== undefined
                             && panel.plan.files.length === 0 && panel.plan.canRemove === true
                    color: Theme.inkSoft
                    text: "No files of it were found in your home folder."
                }
            }
        }

        ScrollHint {
            flick: body
        }
    }

    // ==================================================================
    // removed before: the Yakushi trash, with UNDO
    // ==================================================================
    Item {
        id: removedView

        visible: panel.view === "removed"
        anchors.top: head.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: foot.top
        anchors.bottomMargin: 6

        Item {
            id: trashHead

            width: parent.width
            height: 36

            Caption {
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                text: panel.history.length + (panel.history.length === 1 ? " REMOVAL" : " REMOVALS")
                    + "  ·  " + panel.bytes(panel.trashInfo.size) + " OF YOUR FILES KEPT"
            }

            Pill {
                visible: panel.history.length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: panel.armed === "emptyall" ? "CLICK AGAIN" : "EMPTY THE TRASH"
                danger: true
                hot: panel.armed === "emptyall"
                on: !panel.working
                onClicked: panel.emptyAll()
            }
        }

        Rectangle {
            id: trashRule

            anchors.top: trashHead.bottom
            anchors.topMargin: 14
            width: parent.width
            height: 1
            color: Theme.line
        }

        ListView {
            id: oldList

            anchors.top: trashRule.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: panel.history

            delegate: Item {
                id: oldRow

                required property var modelData

                width: oldList.width
                height: 72

                Rectangle {
                    anchors.bottom: parent.bottom
                    x: 16
                    width: parent.width - 32
                    height: 1
                    color: Theme.tint(Theme.ink, 0.05)
                }

                Text {
                    id: oldName

                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.bottom: parent.verticalCenter
                    anchors.bottomMargin: 1
                    anchors.right: oldButtons.left
                    anchors.rightMargin: 14
                    elide: Text.ElideRight
                    text: (oldRow.modelData.titles || []).join(", ")
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 13
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: oldName.left
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 5
                    anchors.right: oldButtons.left
                    anchors.rightMargin: 14
                    elide: Text.ElideRight
                    text: new Date(oldRow.modelData.time * 1000).toLocaleString(Qt.locale(), "d MMM yyyy, HH:mm")
                        + "  ·  " + oldRow.modelData.files.length + (oldRow.modelData.files.length === 1 ? " folder kept" : " folders kept")
                        + " (" + panel.bytes(oldRow.modelData.keptSize) + ")"
                        + "  ·  " + panel.bytes(oldRow.modelData.freed) + " freed"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 11
                }

                Row {
                    id: oldButtons

                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Pill {
                        label: "UNDO"
                        on: !panel.working
                        onClicked: panel.undo(oldRow.modelData)
                    }

                    Pill {
                        label: panel.armed === "empty:" + oldRow.modelData.id ? "CLICK AGAIN" : "DELETE FOR GOOD"
                        danger: true
                        hot: panel.armed === "empty:" + oldRow.modelData.id
                        on: !panel.working
                        onClicked: panel.empty(oldRow.modelData.id)
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: oldList.count === 0
                anchors.centerIn: parent
                text: trashJob.running ? "Looking…" : "Nothing in the Yakushi trash."
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 12
            }
        }

        ScrollHint {
            flick: oldList
        }
    }
}
