import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Appearance -> Top Bar
//
// Chooses which modules the island shows and in what order (drag a row by
// its grip), the clock format and the bar opacity. Every change is saved by
// scripts/yakushi-topbarctl.py and applied to the running bar at once.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: Paths.script("yakushi-topbarctl.py")

    property bool loaded: false
    property bool seconds: true
    property bool clock24: true
    property real barOpacity: 0.90
    property var modules: ({})
    property string visualizer: "hover"
    readonly property var defaultOrder: [
        "workspaces", "ram", "cpu", "cpuTemp", "gpuTemp",
        "date", "time", "media", "volume", "power"
    ]
    property string status: ""

    function glyph(code) {
        return String.fromCodePoint(code)
    }

    function infoFor(key) {
        for (var i = 0; i < moduleItems.length; i++)
            if (moduleItems[i].key === key)
                return moduleItems[i]
        return { key: key, label: key, icon: "" }
    }

    function fillOrder(list) {
        orderModel.clear()
        for (var i = 0; i < list.length; i++)
            orderModel.append({ key: list[i] })
    }

    function currentOrder() {
        var list = []
        for (var i = 0; i < orderModel.count; i++)
            list.push(orderModel.get(i).key)
        return list
    }

    // Dragging a row by its grip: the list reorders under the pointer (`y`
    // is the pointer's place in the list); the order is saved once, when the
    // button is let go.
    property string orderAtPress: ""

    function dragTo(from, y) {
        var to = Math.max(0, Math.min(orderModel.count - 1, Math.floor(y / orderList.rowHeight)))
        if (to !== from)
            orderModel.move(from, to, 1)
    }

    function dropped() {
        var now = currentOrder().join(",")
        if (now !== orderAtPress)
            send("order", now)
    }

    function resetOrder() {
        fillOrder(defaultOrder)
        send("order", "default")
    }

    ListModel {
        id: orderModel
    }

    readonly property var moduleItems: [
        { key: "workspaces", label: "Workspaces",   icon: glyph(0xF056E) },
        { key: "ram",        label: "RAM usage",    icon: glyph(0xF035B) },
        { key: "cpu",        label: "CPU usage",    icon: glyph(0xF0EE0) },
        { key: "cpuTemp",    label: "CPU temp",     icon: glyph(0xF050F) },
        { key: "gpuTemp",    label: "GPU temp",     icon: glyph(0xF08AE) },
        { key: "media",      label: "Now playing",  icon: glyph(0xF0387) },
        { key: "volume",     label: "Volume",       icon: glyph(0xF057E) },
        { key: "date",       label: "Date",         icon: glyph(0xF00ED) },
        { key: "time",       label: "Time",         icon: glyph(0xF0150) },
        { key: "power",      label: "Power",        icon: glyph(0xF0425) }
    ]

    // ------------------------------------------------------------------
    // Backend: one helper call at a time, queued so fast clicks never race.
    // ------------------------------------------------------------------
    property var queue: []

    function applyState(data) {
        if (typeof data.seconds === "boolean")
            seconds = data.seconds
        if (typeof data.clock24 === "boolean")
            clock24 = data.clock24
        if (typeof data.opacity === "number")
            barOpacity = data.opacity
        if (data.modules)
            modules = data.modules
        if (typeof data.visualizer === "string")
            visualizer = data.visualizer
        if (orderModel.count === 0)
            fillOrder(Array.isArray(data.order) ? data.order : defaultOrder)
        loaded = true
    }

    function send(key, value) {
        // Drop an older queued value for the same key (e.g. slider drags).
        queue = queue.filter(function(item) { return item[0] !== key })
        queue.push([key, value])
        pump()
    }

    function pump() {
        if (setProc.running || queue.length === 0)
            return

        var next = queue.shift()
        setProc.command = ["python3", helper, "set", next[0], next[1]]
        setProc.running = true
    }

    function setModule(key, on) {
        var next = {}
        for (var k in modules)
            next[k] = modules[k]
        next[key] = on
        modules = next
        send("module." + key, on ? "on" : "off")
    }

    Process {
        id: getProc

        running: true
        command: ["python3", page.helper, "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok)
                        page.applyState(data)
                    else
                        page.status = data.message || ""
                } catch (e) {
                    page.status = "Could not read top bar settings."
                }
            }
        }
    }

    Process {
        id: setProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.status = data.message || ""
                    // Opacity is the only value the user may still be
                    // dragging, so it is never pulled back from a reply.
                    if (!data.ok)
                        getProc.running = true
                } catch (e) {
                    page.status = "Could not save top bar settings."
                }
            }
        }

        onRunningChanged: {
            if (!running)
                page.pump()
        }
    }

    Timer {
        id: opacityDebounce
        interval: 150
        repeat: false
        onTriggered: page.send("opacity", page.barOpacity.toFixed(3))
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------
    ScrollHint {
        flick: flick
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: body.height + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body

            width: flick.width
            spacing: 16

            PageTitle {
                width: parent.width
                title: "TOP BAR"
            }

            Divider {}

            // ---------------- Modules ----------------
            SectionHead {
                text: "MODULES"
                hint: "left to right on the bar  ·  drag to reorder"
                action: "RESET ORDER"
                onActivated: page.resetOrder()
            }

            // Rows in island order (left to right). The grip moves a module.
            ListView {
                id: orderList

                readonly property int rowHeight: 34

                width: parent.width
                height: count * rowHeight
                interactive: false
                model: orderModel

                move: Transition {
                    NumberAnimation { properties: "y"; duration: Theme.tMid; easing.type: Easing.OutCubic }
                }

                moveDisplaced: Transition {
                    NumberAnimation { properties: "y"; duration: Theme.tMid; easing.type: Easing.OutCubic }
                }

                delegate: Item {
                    id: moduleRow

                    required property string key
                    required property int index
                    readonly property var info: page.infoFor(key)
                    readonly property bool held: grip.pressed

                    width: orderList.width
                    height: orderList.rowHeight
                    z: held ? 2 : 1

                    // the row in your hand: a light tint and an accent bar
                    Rectangle {
                        anchors.fill: parent
                        color: moduleRow.held ? Theme.tint(Theme.accent, 0.10)
                            : grip.containsMouse ? Theme.tint(Theme.ink, 0.04) : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Rectangle {
                            visible: moduleRow.held
                            width: 3
                            height: parent.height
                            color: Theme.accent
                        }
                    }

                    Text {
                        id: gripGlyph

                        textFormat: Text.PlainText
                        width: 30
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: String.fromCodePoint(0xF01DD)
                        color: moduleRow.held ? Theme.accent : grip.containsMouse ? Theme.ink : Theme.inkMute
                        font.family: Theme.glyphs
                        font.pixelSize: 16
                    }

                    ToggleRow {
                        anchors.left: gripGlyph.right
                        anchors.leftMargin: 6
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        icon: moduleRow.info.icon
                        label: moduleRow.info.label
                        checked: page.modules[moduleRow.key] !== false
                        available: page.loaded
                        onToggled: page.setModule(moduleRow.key, !checked)
                    }

                    MouseArea {
                        id: grip

                        width: gripGlyph.width
                        height: parent.height
                        hoverEnabled: true
                        preventStealing: true
                        enabled: page.loaded
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: page.orderAtPress = page.currentOrder().join(",")
                        onPositionChanged: mouse => {
                            if (pressed)
                                page.dragTo(moduleRow.index, mapToItem(orderList.contentItem, mouse.x, mouse.y).y)
                        }
                        onReleased: page.dropped()
                        onCanceled: page.dropped()
                    }
                }
            }

            // Now-playing visualizer mode
            Item {
                width: parent.width
                height: 30

                Text {
                    id: vizIcon

                    textFormat: Text.PlainText
                    x: 36
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF0EA2)
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 14
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: vizIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Music visualizer"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Segmented {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    enabled: page.loaded
                    options: [["hover", "ON HOVER"], ["always", "ALWAYS"], ["off", "OFF"]]
                    current: page.visualizer
                    onChose: key => {
                        page.visualizer = key
                        page.send("visualizer", key)
                    }
                }
            }

            Divider {}

            // ---------------- Clock ----------------
            SectionHead { text: "CLOCK" }

            Row {
                width: parent.width
                spacing: 28

                ToggleRow {
                    width: (body.width - 28) / 2
                    icon: page.glyph(0xF051B)
                    label: "Show seconds"
                    checked: page.seconds
                    available: page.loaded

                    onToggled: {
                        page.seconds = !page.seconds
                        page.send("seconds", page.seconds ? "on" : "off")
                    }
                }

                ToggleRow {
                    width: (body.width - 28) / 2
                    icon: page.glyph(0xF00F0)
                    label: "24-hour clock"
                    checked: page.clock24
                    available: page.loaded

                    onToggled: {
                        page.clock24 = !page.clock24
                        page.send("clock24", page.clock24 ? "on" : "off")
                    }
                }
            }

            Divider {}

            // ---------------- Glass ----------------
            SectionHead { text: "GLASS" }

            Slider {
                width: parent.width
                label: "Top bar opacity  " + Math.round(page.barOpacity * 100) + "%"
                icon: "◐"
                tint: Theme.accent
                value: (page.barOpacity - 0.40) / 0.60

                onSliding: function(v) {
                    page.barOpacity = 0.40 + v * 0.60
                    opacityDebounce.restart()
                }

                onSettled: function(v) {
                    page.barOpacity = 0.40 + v * 0.60
                    opacityDebounce.stop()
                    page.send("opacity", page.barOpacity.toFixed(3))
                }
            }

            Note {
                text: page.status !== ""
                    ? page.status
                    : "Super + Shift + W hides or shows the bar."
            }
        }
    }
}
