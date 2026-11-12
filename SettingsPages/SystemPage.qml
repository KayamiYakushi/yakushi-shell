import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../"

// Settings -> System: the machine as a council of three. GPU, CPU and
// memory are three cut blocks, each linked to the other two, with the
// machine's name in the pocket between them. A block fills up with its own
// load (in coarse cells, ragged at the top), votes calm (凪) or rough (荒),
// and the decision stands under the name. Your picture and the facts
// (system, kernel, uptime, user, disk) take the two top corners.
//
// The guard (Settings -> Security) reports here too: beside the heading it
// says CLEAR or how many alerts there are, and while there are any they are
// listed in a strip under the heading and the name says ALERT. This page
// only reads what the guard last saved (one small file, watched, no
// polling); if that is more than ten minutes old, one guard check is run.
//
// Facts come from scripts/yakushi-sysinfo.py and yakushi-gpuinfo.py (once,
// when the page opens). Load and memory are read from /proc and sysfs every
// 2 seconds, only while this page is open, right in the tick: every new
// number lands in one frame.
Item {
    id: page

    property var hostWindow: null

    readonly property string home: Paths.home
    readonly property string scripts: Paths.scripts + "/"

    // ---- facts
    property var facts: ({ host: "...", os: "...", kernel: "...", user: "...", cpu: "...", storage: "..." })
    property real diskUse: -1
    property string gpuName: "..."
    property string uptime: "..."
    property string memory: "..."
    property real memUse: -1
    property real cpuUse: -1
    property real gpuUse: -1
    property string vram: ""

    // ---- picture (Config.profilePicture, chosen with the in-card picker)
    property int pictureRev: 0
    readonly property url picture: "file://" + Config.profilePicture
        + (pictureRev > 0 ? "?v=" + pictureRev : "")

    function pickPicture() {
        if (!hostWindow)
            return
        hostWindow.openImagePicker(home, Paths.pictures, function(path) {
            savePicture.command = ["python3", page.scripts + "yakushi-profile-image.py", path]
            savePicture.running = true
        })
    }

    Process {
        id: savePicture
        onExited: function(code) { if (code === 0) page.pictureRev += 1 }
    }

    // ---- one-off facts
    Process {
        command: ["python3", page.scripts + "yakushi-sysinfo.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.facts = JSON.parse(text)
                    page.diskUse = page.facts.storageFraction
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: diskCheck
        command: ["python3", page.scripts + "yakushi-sysinfo.py", "disk"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    page.facts = Object.assign({}, page.facts, d)
                    page.diskUse = d.storageFraction
                } catch (e) {
                }
            }
        }
    }

    // GPU: exact model and where its load / VRAM can be read
    property string gpuBusyFile: ""
    property string vramUsedFile: ""
    property string vramTotalFile: ""
    property bool nvidia: false

    Process {
        command: ["python3", page.scripts + "yakushi-gpuinfo.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var g = JSON.parse(text)
                    page.gpuName = g.name || "Unknown GPU"
                    page.gpuBusyFile = g.busy || ""
                    page.vramUsedFile = g.vramUsed || ""
                    page.vramTotalFile = g.vramTotal || ""
                    page.nvidia = g.nvidia === true
                    page.tick()
                } catch (e) {
                    page.gpuName = "Unknown GPU"
                }
            }
        }
    }

    // ---- live numbers
    function gb(bytes) {
        return (bytes / 1073741824).toFixed(1)
    }

    // The files below are tiny kernel files, read right in the tick (no
    // thread hop), so one tick is one frame.
    property real lastIdle: -1
    property real lastAll: -1

    FileView {
        id: stat
        path: "/proc/stat"
        printErrors: false
        blockLoading: true
        onLoaded: {
            // first line: "cpu  user nice system idle iowait irq softirq steal ..."
            var t = text()
            var f = t.slice(0, t.indexOf("\n")).trim().split(/\s+/)
            if (f.length < 9)
                return
            var all = 0
            for (var i = 1; i < 9; i++)
                all += Number(f[i])
            var idle = Number(f[4]) + Number(f[5])
            if (isNaN(all))
                return
            // two reads right after each other say nothing: wait for a
            // stretch worth measuring
            if (page.lastAll >= 0 && all - page.lastAll < 20)
                return
            if (page.lastAll >= 0)
                page.cpuUse = Math.min(1, Math.max(0, 1 - (idle - page.lastIdle) / (all - page.lastAll)))
            page.lastIdle = idle
            page.lastAll = all
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        blockLoading: true
        onLoaded: {
            var t = text()
            var total = /MemTotal:\s+(\d+)/.exec(t)
            var avail = /MemAvailable:\s+(\d+)/.exec(t)
            if (!total)
                return
            var all = Number(total[1])
            var used = all - (avail ? Number(avail[1]) : 0)
            page.memory = page.gb(used * 1024) + " / " + page.gb(all * 1024) + " GB"
            page.memUse = used / all
        }
    }

    // Read once: from then on the uptime is counted from the clock.
    property real bootedAt: 0

    FileView {
        path: "/proc/uptime"
        printErrors: false
        blockLoading: true
        onLoaded: {
            var s = parseFloat(text())
            if (isNaN(s))
                return
            page.bootedAt = Date.now() / 1000 - s
            page.showUptime()
        }
    }

    function showUptime() {
        if (bootedAt <= 0)
            return
        var s = Math.floor(Date.now() / 1000 - bootedAt)
        var d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60
        uptime = (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"
    }

    FileView {
        id: gpuBusy
        path: page.gpuBusyFile
        printErrors: false
        blockLoading: true
        onLoaded: {
            var v = parseInt(text())
            if (!isNaN(v))
                page.gpuUse = Math.min(1, Math.max(0, v / 100))
        }
    }

    property real vramTotal: 0

    FileView {
        path: page.vramTotalFile
        printErrors: false
        blockLoading: true
        onLoaded: page.vramTotal = Number(text().trim()) || 0
    }

    FileView {
        id: vramUsed
        path: page.vramUsedFile
        printErrors: false
        blockLoading: true
        onLoaded: {
            var used = Number(text().trim())
            if (page.vramTotal > 0 && !isNaN(used))
                page.vram = "VRAM  " + page.gb(used) + " / " + page.gb(page.vramTotal) + " GB"
        }
    }

    Process {
        id: smi
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = text.split("\n")[0].split(",").map(function(x) { return Number(x) })
                if (v.length === 3 && !isNaN(v[0])) {
                    page.gpuUse = Math.min(1, v[0] / 100)
                    page.vram = "VRAM  " + (v[1] / 1024).toFixed(1) + " / " + (v[2] / 1024).toFixed(1) + " GB"
                }
            }
        }
    }

    function tick() {
        stat.reload()
        meminfo.reload()
        showUptime()
        if (gpuBusyFile !== "")
            gpuBusy.reload()
        if (vramUsedFile !== "")
            vramUsed.reload()
        if (nvidia && !smi.running)
            smi.running = true
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: page.tick()
    }

    Timer {
        // the disk changes slowly
        interval: 60000
        running: true
        repeat: true
        onTriggered: diskCheck.running = true
    }

    function percent(f) {
        return f >= 0 ? Math.round(f * 100) + "%" : ""
    }

    readonly property color onAccent: 0.299 * Theme.accent.r + 0.587 * Theme.accent.g + 0.114 * Theme.accent.b > 0.55
        ? "#0a0a0a" : "#f5f5f5"

    // ---- the guard's news
    // What deserves a look, most serious first, from the state the guard
    // keeps (scripts/yakushi-securityctl.py): failed logins (any from the
    // network, or three and more here: one or two typos are just typos),
    // SSH logins, changes to what starts or listens, system files that
    // differ from their package, and known security holes that have a fix.
    // At most three lines: the rest is counted in the last one.
    property var alerts: []
    property int alertCount: 0
    // not a danger, but waiting for you in Security (a closed port, one
    // or two wrong passwords)
    property int reviewCount: 0
    property bool guardRead: false          // the saved state has been read
    property bool guardAsked: false         // one check per visit, at most
    readonly property bool threat: alertCount > 0

    function count(n, one, many) {
        return n + " " + (n === 1 ? one : many)
    }

    function readGuard(raw) {
        var d
        try {
            d = JSON.parse(raw)
        } catch (e) {
            return
        }
        if (d === null || typeof d !== "object")
            return
        function list(v) {
            return Array.isArray(v) ? v : []
        }
        var ev = d.events !== null && typeof d.events === "object" ? d.events : {}
        var lines = []
        var failed = list(ev.failed)
        var remote = failed.filter(function(f) { return f && f.remote === true }).length
        if (remote > 0)
            lines.push(count(remote, "failed SSH login attempt", "failed SSH login attempts") + " from the network")
        else if (failed.length >= 3)
            lines.push(failed.length + " failed password attempts on this computer")
        var ssh = list(ev.ssh).length
        if (ssh > 0)
            lines.push(count(ssh, "SSH login", "SSH logins") + " from the network")
        // a port that closed is no danger (it still waits in Security to
        // be taken as yours)
        var changes = list(d.changes).filter(function(c) {
            return c && !(c.kind === "gone" && String(c.key).indexOf("port:") === 0)
        })
        if (changes.length === 1 && typeof changes[0].text === "string")
            lines.push(changes[0].text)
        else if (changes.length > 0)
            lines.push(changes.length + " changes to what starts or listens on this computer")
        var red = d.scan !== null && typeof d.scan === "object" ? Number(d.scan.redCount) || 0 : 0
        if (red > 0)
            lines.push(count(red, "system file differs from its package", "system files differ from their package"))
        var suid = list(d.scan !== null && typeof d.scan === "object" ? d.scan.suid : null).length
        if (suid > 0)
            lines.push(count(suid, "program", "programs") + " with root rights from no package")
        // the shield: a protection that is off (the firewall, an SSH server
        // that is on) is an alert, a weaker setting is something to review
        var weak = list(d.shield).filter(function(w) { return w && typeof w.text === "string" })
        var soft = 0
        for (var i = 0; i < weak.length; i++) {
            if (weak[i].alert === true)
                lines.push(weak[i].text)
            else
                soft += 1
        }
        var holes = list(d.updates !== null && typeof d.updates === "object" ? d.updates.holes : null)
            .filter(function(h) { return h && h.fix }).length
        if (holes > 0)
            lines.push(count(holes, "package with a known security hole has", "packages with a known security hole have") + " a fix")
        reviewCount = list(d.changes).length - changes.length + soft
            + (remote === 0 && failed.length < 3 ? failed.length : 0)
        alertCount = lines.length
        alerts = lines.length > 3 ? lines.slice(0, 2).concat("and " + (lines.length - 2) + " more") : lines
        guardRead = true

        // an old report: look again, once
        if (Date.now() / 1000 - (Number(d.guardTime) || 0) > 600)
            checkGuard()
    }

    function checkGuard() {
        if (guardAsked)
            return
        guardAsked = true
        guardProc.running = true
    }

    FileView {
        id: guardFile

        path: Paths.stateHome + "/yakushi/security.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.readGuard(text())
        onLoadFailed: page.checkGuard()          // never checked yet
    }

    Process {
        id: guardProc

        command: ["python3", page.scripts + "yakushi-securityctl.py", "guard"]
        onExited: guardFile.reload()
    }

    function openSecurity() {
        if (hostWindow)
            hostWindow.go("Security")
    }

    // ---- the vote (Nagi 凪, the sea when the wind has dropped)
    // GPU, CPU and memory each vote on the readings above: rough (荒) over
    // 90 % busy / full, calm (凪) otherwise; one that cannot be read does
    // not vote. Two rough votes make a stormy sea (時化); anything less is
    // 凪. Nothing extra is read for it.
    readonly property real roughFrom: 0.9
    readonly property int roughVotes: (gpuUse > roughFrom ? 1 : 0) + (cpuUse > roughFrom ? 1 : 0)
        + (memUse > roughFrom ? 1 : 0)
    readonly property bool decided: cpuUse >= 0 && memUse >= 0
    readonly property bool calm: roughVotes < 2

    // ---- a block filling up
    // The block is a grid of cells about `cell` px wide; `lit` of them are
    // on, from the bottom up. Each column runs a little ahead of or behind
    // its neighbours (always the same way), so the top of the fill is
    // ragged, and the whole of it is still one outline: a skyline. That
    // outline is then cut along the block's own cut corners.
    readonly property int cell: 24
    readonly property var lead: [0.62, 0.10, 0.85, 0.33, 0.00, 0.71, 0.45, 0.95, 0.21,
                                 0.56, 0.05, 0.80, 0.38, 0.67, 0.15, 0.90, 0.27]

    // the part of polygon `pts` where a*x + b*y <= d
    function keep(pts, a, b, d) {
        var out = []
        for (var i = 0; i < pts.length; i++) {
            var p = pts[i], q = pts[(i + 1) % pts.length]
            var sp = a * p.x + b * p.y - d, sq = a * q.x + b * q.y - d
            if (sp <= 0)
                out.push(p)
            if ((sp < 0 && sq > 0) || (sp > 0 && sq < 0)) {
                var t = sp / (sp - sq)
                out.push(Qt.point(p.x + t * (q.x - p.x), p.y + t * (q.y - p.y)))
            }
        }
        return out
    }

    // outline of the fill of a w x h block with `lit` cells of cols x rows
    // on; `side` and `cut` as in Voice
    function fillOutline(w, h, cols, rows, lit, side, cut) {
        if (lit <= 0 || w <= 0 || h <= 0)
            return []
        var top = Math.min(rows, Math.ceil(lit / cols) + 2), keys = []
        for (var c = 0; c < cols; c++)
            for (var r = 0; r < top; r++)
                keys.push(Math.round((r + lead[(c + side + 1) % lead.length] * 1.7) * 1000) * 64 + c)
        keys.sort(function(x, y) { return x - y })
        var high = []
        for (c = 0; c < cols; c++)
            high.push(0)
        for (var k = 0; k < lit && k < keys.length; k++)
            high[keys[k] % 64] += 1

        var cw = w / cols, rh = h / rows, pts = [Qt.point(0, h)]
        for (c = 0; c < cols; c++) {
            if (c === 0 || high[c] !== high[c - 1])
                pts.push(Qt.point(c * cw, h - high[c] * rh))
            if (c === cols - 1 || high[c] !== high[c + 1])
                pts.push(Qt.point((c + 1) * cw, h - high[c] * rh))
        }
        pts.push(Qt.point(w, h))

        if (side < 0)
            return keep(pts, 1, -1, w - cut)                   // top-right corner
        if (side > 0)
            return keep(pts, -1, -1, -cut)                     // top-left corner
        return keep(keep(pts, -1, 1, h - cut), 1, 1, w + h - cut)   // both bottom corners
    }

    // One of the three: what it is, its reading, and its vote. The block
    // itself fills with the reading and carries its model in the middle;
    // the rest keeps to the block's outer side (`side`: -1 left, 0 the top
    // one, 1 right), and the cut corners face the other two.
    component Voice: Item {
        id: voice

        property string name: ""
        property string value: ""
        property string extra: ""
        property real load: -1
        property int side: 0
        property real cut: 0
        property int figure: 26            // size of the percentage
        property int title: 16             // size of the model

        readonly property bool voted: load >= 0
        readonly property bool rough: load > page.roughFrom
        readonly property color tone: rough ? Theme.alert : Theme.accent
        readonly property int pad: 20
        readonly property int align: side < 0 ? Text.AlignLeft : side > 0 ? Text.AlignRight : Text.AlignHCenter

        readonly property int cols: Math.max(4, Math.min(60, Math.round(width / page.cell)))
        readonly property int rows: Math.max(4, Math.round(height / page.cell))
        // a whole number: the outline is worked out again only when a
        // cell goes on or off
        readonly property int lit: voted ? Math.round(Math.min(1, load) * cols * rows) : 0

        Shape {
            anchors.fill: parent
            visible: voice.lit > 0
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.tint(voice.tone, 0.24)
                strokeColor: "transparent"
                strokeWidth: 0

                PathPolyline {
                    path: page.fillOutline(voice.width, voice.height, voice.cols, voice.rows,
                                           voice.lit, voice.side, voice.cut)
                }
            }
        }

        CutBox {
            anchors.fill: parent
            fill: Theme.tint(Theme.ink, 0.03)
            stroke: voice.rough ? Theme.tint(Theme.alert, 0.7) : Theme.tint(Theme.ink, 0.14)
            cut: voice.cut
            cutTopLeft: voice.side > 0
            cutTopRight: voice.side < 0
            cutBottomLeft: voice.side === 0
            cutBottomRight: voice.side === 0
        }

        // 凪 CPU (mirrored on the right block)
        Row {
            x: voice.side < 0 ? voice.pad
             : voice.side > 0 ? parent.width - width - voice.pad : (parent.width - width) / 2
            y: 16
            spacing: 10
            layoutDirection: voice.side > 0 ? Qt.RightToLeft : Qt.LeftToRight

            Text {
                id: vote

                textFormat: Text.PlainText
                text: !voice.voted ? "・" : voice.rough ? "荒" : "凪"
                color: voice.voted ? voice.tone : Theme.inkMute
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 16
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: vote.verticalCenter
                text: voice.name
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 3
            }
        }

        Text {
            textFormat: Text.PlainText
            x: voice.pad
            y: 40
            width: parent.width - 2 * voice.pad
            horizontalAlignment: voice.align
            visible: voice.voted
            text: page.percent(voice.load)
            color: voice.rough ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: voice.figure
            font.bold: true
        }

        // the model (and VRAM) in the middle of the block, or right under
        // the percentage when the block is too short for that
        Column {
            x: voice.pad
            y: Math.round(Math.min(parent.height - height - voice.pad,
                                   Math.max((parent.height - height) / 2, 44 + voice.figure * 1.25)))
            width: parent.width - 2 * voice.pad
            spacing: 6

            Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: voice.value
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: voice.title
                font.weight: Font.Medium
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: voice.extra !== ""
                text: voice.extra
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 11
            }
        }
    }

    // A link between two of the three: lit once both have voted, in alert
    // when either is rough.
    component Link: Rectangle {
        property Voice a
        property Voice b

        antialiasing: rotation !== 0
        color: !a.voted || !b.voted ? Theme.tint(Theme.ink, 0.14)
             : a.rough || b.rough ? Theme.alert : Theme.tint(Theme.accent, 0.6)
    }

    Column {
        anchors.fill: parent
        spacing: 18

        // SYSTEM //────────── 守 GUARD CLEAR
        Item {
            width: parent.width
            height: heading.implicitHeight

            PageTitle {
                id: heading

                width: parent.width - guardTag.width - 16
                title: "SYSTEM"
            }

            Row {
                id: guardTag

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    id: guardGlyph

                    textFormat: Text.PlainText
                    text: "守"
                    color: page.threat ? Theme.alert : page.guardRead ? Theme.accent : Theme.inkMute
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 13
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: guardGlyph.verticalCenter
                    text: "GUARD"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 2
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: guardGlyph.verticalCenter
                    text: !page.guardRead ? "CHECKING"
                        : page.threat ? page.count(page.alertCount, "ALERT", "ALERTS")
                        : page.reviewCount > 0 ? page.reviewCount + " TO REVIEW" : "CLEAR"
                    color: page.threat ? Theme.alert : !page.guardRead ? Theme.inkMute
                         : page.reviewCount > 0 ? Theme.accent : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 2
                }
            }

            MouseArea {
                anchors.fill: guardTag
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: page.openSecurity()
            }
        }

        // The guard's alerts, only while there are any (the council makes
        // room). A click opens Settings -> Security.
        Item {
            id: alarm

            visible: page.threat
            width: parent.width
            height: alarmLines.height + 20

            CutBox {
                anchors.fill: parent
                fill: Theme.tint(Theme.alert, alarmMouse.containsMouse ? 0.14 : 0.08)
                stroke: Theme.tint(Theme.alert, 0.7)
                cut: Theme.cutSmall
                cutTopLeft: false
                cutBottomRight: false
            }

            Text {
                textFormat: Text.PlainText
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "警"
                color: Theme.alert
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 18
            }

            Column {
                id: alarmLines

                x: 50
                y: 10
                width: parent.width - x - openHint.width - 32
                spacing: 4

                Repeater {
                    model: page.alerts

                    Text {
                        required property string modelData

                        textFormat: Text.PlainText
                        width: alarmLines.width
                        text: modelData
                        elide: Text.ElideRight
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 13
                    }
                }
            }

            Text {
                id: openHint

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "SECURITY ──"
                color: alarmMouse.containsMouse ? Theme.ink : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 2
            }

            MouseArea {
                id: alarmMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.openSecurity()
            }
        }

        // The council. The GPU block hangs between the two corners and
        // reaches down between the CPU and memory blocks; where two blocks
        // face each other their edges run parallel, one `gutter` apart, and
        // a link crosses it. The three links stand around the pocket under
        // the GPU block, and the name sits in that pocket. It all grows
        // with the card: taller blocks, a bigger picture.
        Item {
            id: council

            readonly property real room: parent.height - y             // what the page has left
            readonly property int gutter: 24                           // between any two neighbours
            readonly property real channel: gutter * Math.SQRT2        // the same, measured along x
            readonly property int topWidth: Math.max(200, Math.min(250, width - 340))
            readonly property int topCut: 46
            readonly property int sideWidth: Math.floor((width - gutter) / 2)
            readonly property real sideCut: channel + (topWidth - gutter) / 2
            readonly property real topX: (width - topWidth) / 2
            readonly property real cornerWidth: topX - gutter
            // the picture gives way first when the page gets short
            readonly property int cornerHeight: Math.floor(Math.max(
                Math.max(110, Math.min(146, room - gutter - sideCut - 40)),
                Math.min(200, cornerWidth - 3, 146 + 0.4 * (room - 320))))
            readonly property int rowY: cornerHeight + gutter          // top of the CPU and memory blocks
            readonly property int sideHeight: Math.floor(Math.max(sideCut + 40, Math.min(330, room - rowY)))
            readonly property int figure: Math.max(26, Math.min(56, Math.round(sideHeight * 0.18)))
            readonly property int title: Math.max(13, Math.min(16, Math.round(sideHeight * 0.052)))
            // the pocket: as wide as this under the GPU block, 2 px
            // narrower with every px down
            readonly property real pocket: topWidth - 2 * topCut + 2 * channel
            readonly property int linkWidth: 5

            width: parent.width
            height: rowY + sideHeight

            // ---- top left: your picture
            Rectangle {
                id: frame

                x: 3                    // room for the corner ticks: the page clips at x = 0
                width: council.cornerHeight
                height: council.cornerHeight
                color: Theme.tint(Theme.ink, 0.03)
                border.width: 1
                border.color: frameMouse.containsMouse ? Theme.accent : Theme.tint(Theme.ink, 0.18)
                clip: true

                Image {
                    id: shot

                    anchors.fill: parent
                    anchors.margins: 5
                    source: page.picture
                    sourceSize.width: 280
                    sourceSize.height: 280
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                Text {
                    id: plus

                    textFormat: Text.PlainText
                    visible: shot.status !== Image.Ready
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 28
                    text: "+"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 26
                }

                Text {
                    textFormat: Text.PlainText
                    visible: plus.visible
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: plus.bottom
                    anchors.topMargin: 6
                    text: "ADD IMAGE"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 3
                }

                Rectangle {
                    visible: shot.status === Image.Ready && frameMouse.containsMouse
                    x: 5
                    y: parent.height - height - 5
                    width: parent.width - 10
                    height: 24
                    color: Theme.accent

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "CHANGE ──"
                        color: page.onAccent
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 3
                    }
                }

                MouseArea {
                    id: frameMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.pickPicture()
                }
            }

            // corner ticks on the picture
            Rectangle { x: frame.x - 3; y: frame.y - 3; width: 10; height: 2; color: Theme.accent }
            Rectangle { x: frame.x - 3; y: frame.y - 3; width: 2; height: 10; color: Theme.accent }
            Rectangle { x: frame.x + frame.width - 7; y: frame.y + frame.height + 1; width: 10; height: 2; color: Theme.accent }
            Rectangle { x: frame.x + frame.width + 1; y: frame.y + frame.height - 7; width: 2; height: 10; color: Theme.accent }

            // ---- top right: the facts
            Item {
                id: factList

                x: council.width - width
                width: council.cornerWidth
                height: council.cornerHeight

                // 薬師 (Yakushi), large and faint, behind them
                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "薬\n師"
                    lineHeight: 0.92
                    color: Theme.tint(Theme.ink, 0.07)
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 62
                    font.bold: true
                }

                Repeater {
                    model: [
                        { k: "SYSTEM", v: page.facts.os },
                        { k: "KERNEL", v: page.facts.kernel },
                        { k: "UPTIME", v: page.uptime },
                        { k: "USER", v: page.facts.user },
                        { k: "STORAGE", v: page.facts.storage }
                    ]

                    delegate: Item {
                        id: fact

                        required property var modelData
                        required property int index

                        y: Math.round(index * factList.height / 5)
                        width: factList.width
                        height: factList.height / 5

                        Text {
                            textFormat: Text.PlainText
                            text: fact.modelData.k
                            color: Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 2
                        }

                        Text {
                            textFormat: Text.PlainText
                            y: 12
                            width: parent.width
                            text: fact.modelData.v
                            elide: Text.ElideRight
                            color: fact.index === 4 && page.diskUse > page.roughFrom ? Theme.alert : Theme.ink
                            font.family: Theme.mono
                            font.pixelSize: 13
                        }
                    }
                }
            }

            // ---- the three
            Voice {
                id: gpu

                x: council.topX
                width: council.topWidth
                height: council.rowY + council.topCut
                side: 0
                cut: council.topCut
                figure: council.figure
                title: council.title
                name: "GPU"
                value: page.gpuName
                extra: page.vram
                load: page.gpuUse
            }

            Voice {
                id: cpu

                y: council.rowY
                width: council.sideWidth
                height: council.sideHeight
                side: -1
                cut: council.sideCut
                figure: council.figure
                title: council.title
                name: "CPU"
                value: page.facts.cpu
                load: page.cpuUse
            }

            Voice {
                id: ram

                x: council.width - width
                y: council.rowY
                width: council.sideWidth
                height: council.sideHeight
                side: 1
                cut: council.sideCut
                figure: council.figure
                title: council.title
                name: "MEMORY"
                value: page.memory
                load: page.memUse
            }

            // ---- their links, each one gutter long: GPU to CPU and GPU to
            // memory across the two slanted channels, CPU to memory under
            // the pocket
            Link {
                a: gpu
                b: cpu
                width: council.gutter
                height: council.linkWidth
                x: council.topX + council.topCut / 2 - council.channel / 4 - width / 2
                y: council.rowY + council.topCut / 2 + council.channel / 4 - height / 2
                rotation: -45
            }

            Link {
                a: gpu
                b: ram
                width: council.gutter
                height: council.linkWidth
                x: council.width - (council.topX + council.topCut / 2 - council.channel / 4) - width / 2
                y: council.rowY + council.topCut / 2 + council.channel / 4 - height / 2
                rotation: 45
            }

            Link {
                a: cpu
                b: ram
                x: cpu.width
                y: Math.round(council.rowY + council.sideCut + 10)
                width: ram.x - x
                height: council.linkWidth
            }

            // ---- the name, right under the GPU block, and the decision
            // (a guard alert comes before the load)
            Column {
                id: hub

                x: Math.round((council.width - width) / 2)
                y: gpu.height + 10
                width: council.pocket - 100          // what the pocket has left where the name ends
                spacing: 2

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: String(page.facts.host).toUpperCase()
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 24
                    font.bold: true
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 9
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 5

                    Text {
                        id: verdict

                        textFormat: Text.PlainText
                        text: !page.decided ? "・" : page.threat ? "警" : page.calm ? "凪" : "時化"
                        color: !page.decided ? Theme.inkMute
                             : page.calm && !page.threat ? Theme.accent : Theme.alert
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 14
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: verdict.verticalCenter
                        visible: page.decided
                        text: page.threat ? "ALERT" : page.calm ? "CALM" : "ROUGH"
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 2
                    }
                }
            }
        }
    }

}
