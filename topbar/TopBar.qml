import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Shapes
import "../"

// The island: a notch hanging from the top edge of the screen, joined to
// the edge by 45-degree shoulders, with cut lower corners (Theme.cut).
// Modules are laid out in the order chosen in Settings -> Top Bar; the
// last two dots between them turn red while the screen is recorded and
// green while the microphone is heard.
//
// On the island itself: double-click a module and keep the button down to
// move it (let go to drop it); right-click one for its own small settings
// card (and to put other modules on or take it off); hover the date for
// the month.
// Everything is event-driven (Hyprland IPC, MPRIS, PipeWire, UPower,
// NetworkManager, the system clock); only SystemStats ticks, every 2 seconds (on the clock's tick when
// seconds are shown).
PanelWindow {
    id: win

    required property var config
    required property var stats
    required property var clock
    required property var media
    required property var power    // shared: { requests } bumped by the shortcut
    property var battery: null     // BatteryState, on a computer with a battery
    property var network: null     // NetworkState, while its module is on
    property var privacy: null     // PrivacyState (screen watched, microphone heard), while it is on
    property var tray: null        // TrayState, while the tray module is on

    readonly property var mods: config.modules
    readonly property int barHeight: 32
    readonly property int ear: 10
    readonly property int padX: 18

    // Now-playing card that hangs below the song (see MediaCard.qml).
    // Only this part expands; the island itself keeps its size.
    readonly property int cardHeight: 148
    readonly property int cardWidth: 360
    readonly property int cardEar: 12
    property bool mediaHot: false      // pointer on the song in the bar row
    property bool mediaOpen: false
    property real mediaCenterX: width / 2

    onMediaHotChanged: {
        if (mediaHot) {
            closeDelay.stop()
            openDelay.restart()
        } else {
            openDelay.stop()
            if (mediaOpen)
                closeDelay.restart()
        }
    }

    // A short delay so passing over the song does not pop the card open.
    Timer {
        id: openDelay
        interval: 140
        onTriggered: if (win.mediaHot && win.media.trackText !== "" && !win.powerOpen) win.mediaOpen = true
    }

    // Closes once the pointer has left both the song and the card.
    Timer {
        id: closeDelay
        interval: 260
        onTriggered: if (!win.mediaHot && !mediaDrop.hovered) win.mediaOpen = false
    }

    onMediaOpenChanged: {
        if (!mediaOpen) {
            closeDelay.stop()
        } else {
            calOpen = false
            editOpen = false
            trayOpen = false
        }
    }

    // -------------------------
    // The month under the date (hover it)
    // -------------------------
    readonly property int calHeight: 214
    property bool dateHot: false
    property bool calOpen: false
    property real dateCenterX: width / 2

    onDateHotChanged: {
        if (dateHot) {
            calClose.stop()
            calDelay.restart()
        } else {
            calDelay.stop()
            if (calOpen)
                calClose.restart()
        }
    }

    onCalOpenChanged: {
        if (calOpen) {
            mediaOpen = false
            editOpen = false
            trayOpen = false
        } else {
            calClose.stop()
        }
    }

    Timer {
        id: calDelay
        interval: 220
        onTriggered: if (win.dateHot && !win.powerOpen && win.dragKey === "") win.calOpen = true
    }

    Timer {
        id: calClose
        interval: 300
        onTriggered: if (!win.dateHot && !calDrop.hovered) win.calOpen = false
    }

    // -------------------------
    // A module's own settings (right-click it)
    // -------------------------
    property bool editOpen: false
    property string editKey: ""          // "" = the island itself
    property bool editTouched: false     // pointer has been inside the card
    property real editCenterX: width / 2

    function toggleEdit(key) {
        if (editOpen && editKey === key) {
            editOpen = false
            return
        }
        editKey = key
        editTouched = false
        mediaOpen = false
        powerOpen = false
        calOpen = false
        trayOpen = false
        editOpen = true
        editIdle.restart()
    }

    onEditOpenChanged: if (!editOpen) { editLeave.stop(); editIdle.stop() }

    // Left alone it closes by itself; once used, leaving it closes it.
    Timer {
        id: editIdle
        interval: 8000
        onTriggered: if (!editDrop.hovered) win.editOpen = false
    }

    Timer {
        id: editLeave
        interval: 500
        onTriggered: if (!editDrop.hovered && !islandHover.hovered) win.editOpen = false
    }

    function editPointerChanged() {
        if (!editOpen)
            return
        if (editDrop.hovered) {
            editTouched = true
            editLeave.stop()
            editIdle.stop()
        } else if (editTouched && !islandHover.hovered) {
            editLeave.restart()
        }
    }

    function saveSetting(name, value) {
        run(["python3", Paths.script("yakushi-topbarctl.py"), "set", name, value])
    }

    // the whole order (shown and hidden modules), applied at once and saved
    function saveOrder(full) {
        config.order = full
        saveSetting("order", full.join(","))
    }

    function setModule(key, on) {
        var next = {}
        for (var k in config.modules)
            next[k] = config.modules[k]
        next[key] = on
        config.modules = next
        saveSetting("module." + key, on ? "on" : "off")
    }

    // a module put on the bar goes right after the one whose card it is
    function addModule(key) {
        var full = config.order.filter(function(k) { return k !== key })
        var at = editKey !== "" ? full.indexOf(editKey) + 1 : full.length
        full.splice(at > 0 ? at : full.length, 0, key)
        saveOrder(full)
        setModule(key, true)
        editKey = key
    }

    function removeModule() {
        var key = editKey
        editOpen = false
        if (key !== "")
            setModule(key, false)
    }

    // -------------------------
    // A tray program's menu (right-click its icon)
    // -------------------------
    property bool trayOpen: false
    property var trayItem: null          // the SystemTrayItem whose menu is open
    property bool trayTouched: false     // pointer has been inside the card
    property real trayCenterX: width / 2

    function toggleTrayMenu(item, centerX) {
        if (trayOpen && trayItem === item) {
            trayOpen = false
            return
        }
        trayItem = item
        trayCenterX = centerX
        trayTouched = false
        mediaOpen = false
        powerOpen = false
        calOpen = false
        editOpen = false
        trayOpen = true
        trayIdle.restart()
    }

    onTrayOpenChanged: if (!trayOpen) { trayLeave.stop(); trayIdle.stop() }

    // the program went away with its menu open
    onTrayItemChanged: if (trayItem === null) trayOpen = false

    Timer {
        id: trayIdle
        interval: 8000
        onTriggered: if (!trayDrop.hovered) win.trayOpen = false
    }

    Timer {
        id: trayLeave
        interval: 450
        onTriggered: if (!trayDrop.hovered && !islandHover.hovered) win.trayOpen = false
    }

    function trayPointerChanged() {
        if (!trayOpen)
            return
        if (trayDrop.hovered) {
            trayTouched = true
            trayLeave.stop()
            trayIdle.stop()
        } else if (trayTouched && !islandHover.hovered) {
            trayLeave.restart()
        }
    }

    // -------------------------
    // Moving a module: double-click it, keep the button down, drag
    // -------------------------
    // The module itself still gets both clicks (the island never delays a
    // click), so a switch flipped by the first one is flipped back by the
    // second.
    property string tapKey: ""
    property real tapAt: 0
    property real tapX: 0
    property string dragKey: ""
    property int dragFrom: -1
    property real dragStartX: 0
    property real dragDx: 0

    function gesturePress(key, index, x) {
        var now = Date.now()
        if (key === tapKey && now - tapAt < 400 && Math.abs(x - tapX) < 12) {
            tapKey = ""
            netClick.stop()
            mediaOpen = false
            powerOpen = false
            calOpen = false
            editOpen = false
            trayOpen = false
            dragFrom = index
            dragStartX = x
            dragDx = 0
            dragKey = key
        } else {
            tapKey = key
            tapAt = now
            tapX = x
        }
    }

    function gestureMove(key, x) {
        if (dragKey !== key)
            return
        var me = slots.itemAt(dragFrom)
        if (!me)
            return
        // not past either end of the row
        dragDx = Math.max(-me.x, Math.min(content.width - me.x - me.width, x - dragStartX))
    }

    // where the module being moved would land, among the others
    readonly property int dragTo: {
        if (dragKey === "")
            return -1
        var me = slots.itemAt(dragFrom)
        if (!me)
            return dragFrom
        var centre = me.x + me.lead + me.moduleWidth / 2 + dragDx
        var to = 0
        for (var i = 0; i < slots.count; i++) {
            var other = slots.itemAt(i)
            if (i !== dragFrom && other && other.x + other.lead + other.moduleWidth / 2 < centre)
                to++
        }
        return to
    }

    // how far the module at `i` steps aside for the one being moved
    function shiftOf(i) {
        if (dragKey === "" || i === dragFrom || dragTo < 0)
            return 0
        var me = slots.itemAt(dragFrom)
        var w = me ? me.width : 0
        if (dragFrom < dragTo && i > dragFrom && i <= dragTo)
            return -w
        if (dragTo < dragFrom && i >= dragTo && i < dragFrom)
            return w
        return 0
    }

    function gestureRelease() {
        if (dragKey === "")
            return
        var key = dragKey
        var from = dragFrom
        var to = dragTo
        if (to >= 0 && to !== from) {
            var shown = visibleKeys.slice()
            shown.splice(from, 1)
            shown.splice(to, 0, key)
            // the hidden modules keep their places in the whole order
            var full = config.order.slice()
            var j = 0
            for (var i = 0; i < full.length; i++)
                if (visibleKeys.indexOf(full[i]) >= 0)
                    full[i] = shown[j++]
            saveOrder(full)
        }
        dragKey = ""
        dragFrom = -1
        dragDx = 0
    }

    // Network opens Settings on a click: a moment later, so a double-click
    // that moves it does not open Settings too.
    Timer {
        id: netClick
        interval: 260
        onTriggered: win.run([Paths.shell + "/bin/yakushi", "settings", "network"])
    }

    Connections {
        target: win.media
        function onTrackTextChanged() {
            if (win.media.trackText === "")
                win.mediaOpen = false
        }
    }

    anchors {
        top: true
        left: true
        right: true
    }

    // The surface is tall enough for the open card, but only the bar row
    // reserves space and only the island itself takes input.
    implicitHeight: barHeight + 300
    exclusiveZone: barHeight
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "yakushi-topbar"
    // Keyboard only while the power menu is open (arrows / Enter / Esc).
    WlrLayershell.keyboardFocus: powerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Only the island (and the open card) take input; the rest of the
    // surface is click-through.
    mask: Region {
        item: island

        Region {
            item: mediaDrop.visible ? mediaDrop : null
        }

        Region {
            item: powerDrop.visible ? powerDrop : null
        }

        Region {
            item: calDrop.visible ? calDrop : null
        }

        Region {
            item: editDrop.visible ? editDrop : null
        }

        Region {
            item: trayDrop.visible ? trayDrop : null
        }
    }

    // -------------------------
    // Power menu state
    // -------------------------
    property bool powerOpen: false
    property bool powerHot: false        // pointer on the power button
    property bool powerTouched: false    // pointer has been inside the menu
    property real powerCenterX: width / 2

    onPowerOpenChanged: {
        powerTouched = false
        if (powerOpen) {
            mediaOpen = false
            calOpen = false
            editOpen = false
            trayOpen = false
            powerIdle.restart()
        } else {
            powerIdle.stop()
            powerLeave.stop()
        }
    }

    // Leaving the button and the menu closes it (once it has been used
    // with the mouse); left alone after the shortcut, it closes by itself.
    Timer {
        id: powerLeave
        interval: 450
        onTriggered: if (!win.powerHot && !powerDrop.hovered) win.powerOpen = false
    }

    Timer {
        id: powerIdle
        interval: 10000
        onTriggered: if (!powerDrop.hovered && !win.powerHot) win.powerOpen = false
    }

    function powerPointerChanged() {
        if (!powerOpen)
            return
        if (powerHot || powerDrop.hovered) {
            powerTouched = true
            powerLeave.stop()
            powerIdle.stop()
        } else if (powerTouched) {
            powerLeave.restart()
        } else {
            powerIdle.restart()
        }
    }

    onPowerHotChanged: powerPointerChanged()

    // SUPER + ` (via IPC) opens the menu on the focused monitor.
    Connections {
        target: win.power
        function onRequestsChanged() {
            var focused = Hyprland.focusedMonitor
            if (!focused || !win.screen || focused.name === win.screen.name)
                win.powerOpen = !win.powerOpen
        }
    }

    function pad(value, width) {
        var s = String(value)
        while (s.length < width)
            s = " " + s
        return s
    }

    // Fire-and-forget launcher. Every call gets its own short-lived Process
    // that is started detached (fully independent of the bar), so one launch
    // can never block or cancel another. Older Quickshell builds without
    // startDetached() fall back to `setsid -f`, which returns at once.
    Component {
        id: launcherComponent

        Process {
            onExited: destroy()
        }
    }

    function run(args) {
        var proc = launcherComponent.createObject(win)
        if (!proc)
            return

        if (typeof proc.startDetached === "function") {
            proc.command = args
            proc.startDetached()
            proc.destroy()
        } else {
            proc.command = ["setsid", "-f"].concat(args)
            proc.running = true
        }
    }

    function focusWorkspace(id) {
        // Hyprland's Lua config dispatches through `hyprctl eval`; older
        // builds fall back to the classic dispatcher.
        run([
            "sh", "-c",
            "out=$(hyprctl eval \"hl.dispatch(hl.dsp.focus({ workspace = $1 }))\" 2>&1); "
                + "case \"$out\" in *rror*|*nknown*|*nvalid*) hyprctl dispatch workspace \"$1\" ;; esac",
            "yakushi-ws",
            String(id)
        ])
    }


    // -------------------------
    // Which modules are on screen, in order
    // -------------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink !== null && sink.audio !== null

    PwObjectTracker {
        objects: [win.sink]
    }

    readonly property var categories: ({
        workspaces: "ws",
        ram: "sys", cpu: "sys", cpuTemp: "sys", gpuTemp: "sys",
        date: "clock", time: "clock",
        media: "media",
        tray: "tray",
        volume: "ctl", network: "ctl", battery: "ctl", power: "ctl"
    })

    function shows(key) {
        if (mods[key] === false)
            return false
        if (key === "cpuTemp")
            return stats.cpuTemp >= 0
        if (key === "gpuTemp")
            return stats.gpuTemp >= 0
        if (key === "media")
            return media.trackText !== ""
        if (key === "volume")
            return sinkReady
        if (key === "battery")
            return battery !== null && battery.present
        if (key === "network")
            return network !== null && network.shown
        if (key === "tray")
            return tray !== null && tray.count > 0
        return true
    }

    readonly property var visibleKeys: {
        var list = []
        for (var i = 0; i < config.order.length; i++)
            if (shows(config.order[i]))
                list.push(config.order[i])
        return list
    }

    // The faint dots between module groups double as the privacy marks: the
    // last two light up, red while the screen is recorded or shared, green
    // while a program listens to the microphone (PrivacyState.qml). A bar
    // with fewer than two of them gets marks of its own at its end instead
    // (PrivacyDots.qml), so the warning is not lost by rearranging the bar.
    readonly property var separators: {
        var list = []
        for (var i = 1; i < visibleKeys.length; i++)
            if (categories[visibleKeys[i - 1]] !== categories[visibleKeys[i]])
                list.push(i)
        return list
    }
    readonly property bool ownMarks: separators.length < 2
    readonly property int screenSep: ownMarks ? -1 : separators[separators.length - 2]
    readonly property int micSep: ownMarks ? -1 : separators[separators.length - 1]
    readonly property bool screenLit: privacy !== null && privacy.screen
    readonly property bool micLit: privacy !== null && privacy.mic

    // -------------------------
    // Module components
    // -------------------------
    Component {
        id: cWorkspaces

        Workspaces {
            screen: win.screen
            barHeight: win.barHeight
            onActivate: function(id) { win.focusWorkspace(id) }
        }
    }

    Component {
        id: cRam

        BarModule {
            label: "RAM"
            value: hovered
                ? win.stats.ramUsedGb.toFixed(1) + " / " + win.stats.ramTotalGb.toFixed(1) + " GB"
                : win.pad(win.stats.ramUsedGb.toFixed(1), 4) + " GB"
        }
    }

    Component {
        id: cCpu

        BarModule {
            label: "CPU"
            value: win.pad(Math.round(win.stats.cpuPercent), 2) + "%"
        }
    }

    Component {
        id: cCpuTemp

        BarModule {
            // Right after CPU usage the label would repeat itself.
            label: parent && parent.prevKey === "cpu" ? "" : "CPU"
            value: win.stats.cpuTemp + "°C"
        }
    }

    Component {
        id: cGpuTemp

        BarModule {
            label: "GPU"
            value: win.stats.gpuTemp + "°C"
        }
    }

    Component {
        id: cDate

        BarModule {
            value: win.clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd d MMM")
            valueColor: win.calOpen ? Theme.ink : Theme.inkSoft
            onHoveredChanged: win.dateHot = hovered
            Component.onDestruction: win.dateHot = false
        }
    }

    Component {
        id: cTime

        BarModule {
            bold: true
            value: {
                var d = win.clock.date
                var h = d.getHours()
                var suffix = ""

                if (!win.config.clock24) {
                    suffix = h < 12 ? " AM" : " PM"
                    h = h % 12 === 0 ? 12 : h % 12
                }

                var text = (h < 10 ? "0" : "") + h + ":"
                    + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()

                if (win.config.seconds)
                    text += ":" + (d.getSeconds() < 10 ? "0" : "") + d.getSeconds()

                return text + suffix
            }
        }
    }

    Component {
        id: cMedia

        MediaModule {
            media: win.media
            barHeight: win.barHeight
            active: win.mediaOpen
            onHoveredChanged: win.mediaHot = hovered
            Component.onDestruction: win.mediaHot = false
        }
    }

    Component {
        id: cVolume

        VolumeModule {
            barHeight: win.barHeight
            onOpenMixer: win.run(["pavucontrol"])
        }
    }

    // Wi-Fi and its strength (the network's name on hover), or OFFLINE.
    // On a cable there is nothing to say and the module is not shown.
    Component {
        id: cNetwork

        BarModule {
            interactive: true
            icon: win.network ? win.network.glyph : ""
            value: !win.network ? ""
                : win.network.offline ? "OFFLINE"
                : hovered ? win.network.name : ""
            valueColor: win.network && win.network.offline ? Theme.alert : Theme.ink
            maxValueWidth: 160
            onClicked: button => { if (button === Qt.LeftButton) netClick.restart() }
        }
    }

    // The charge; red when it runs low, the time left on hover.
    Component {
        id: cBattery

        BarModule {
            icon: win.battery ? win.battery.glyph : ""
            value: !win.battery ? ""
                : win.battery.percent + "%" + (hovered && win.battery.timeText !== "" ? "  ·  " + win.battery.timeText : "")
            valueColor: win.battery && win.battery.low ? Theme.alert : Theme.ink
        }
    }

    Component {
        id: cPower

        BarModule {
            interactive: true
            icon: String.fromCodePoint(0xF0425)
            highlighted: win.powerOpen

            onHoveredChanged: win.powerHot = hovered
            Component.onDestruction: win.powerHot = false
            onClicked: win.powerOpen = !win.powerOpen
        }
    }

    // The tray's icons; right-click one for that program's menu, drag one
    // to move it among the others (the order is kept by program id).
    Component {
        id: cTray

        TrayModule {
            tray: win.tray
            barHeight: win.barHeight
            order: win.config.trayOrder
            moduleMoving: win.dragKey !== ""
            openItem: win.trayOpen ? win.trayItem : null
            onMenuRequested: (item, centerX) => win.toggleTrayMenu(item, centerX)
            onDragStarted: win.trayOpen = false
            onReordered: ids => {
                win.config.trayOrder = ids
                win.saveSetting("trayOrder", JSON.stringify(ids))
            }
        }
    }

    readonly property var componentFor: ({
        workspaces: cWorkspaces,
        ram: cRam,
        cpu: cCpu,
        cpuTemp: cCpuTemp,
        gpuTemp: cGpuTemp,
        date: cDate,
        time: cTime,
        media: cMedia,
        volume: cVolume,
        network: cNetwork,
        tray: cTray,
        battery: cBattery,
        power: cPower
    })

    // -------------------------
    // Island
    // -------------------------
    Item {
        id: island

        property real bodyWidth: Math.max(content.implicitWidth + 2 * win.padX, 96)
        readonly property int cornerRadius: Theme.cut     // the cut lower corners

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: bodyWidth + 2 * win.ear
        height: win.barHeight

        Behavior on bodyWidth {
            NumberAnimation { duration: Theme.tMid + 40; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: islandHover

            onHoveredChanged: {
                win.editPointerChanged()
                win.trayPointerChanged()
            }
        }

        // right-click an empty part: put modules on the bar
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: win.toggleEdit("")
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Qt.rgba(0.02, 0.02, 0.02, win.config.barOpacity)
                strokeColor: "transparent"
                strokeWidth: 0

                startX: 0
                startY: 0

                PathLine { x: island.width; y: 0 }
                PathLine { x: island.width - win.ear; y: win.ear }
                PathLine { x: island.width - win.ear; y: island.height - island.cornerRadius }
                PathLine { x: island.width - win.ear - island.cornerRadius; y: island.height }
                PathLine { x: win.ear + island.cornerRadius; y: island.height }
                PathLine { x: win.ear; y: island.height - island.cornerRadius }
                PathLine { x: win.ear; y: win.ear }
                PathLine { x: 0; y: 0 }
            }
        }

        Item {
            id: rowClip

            anchors.fill: parent
            anchors.leftMargin: win.ear
            anchors.rightMargin: win.ear
            clip: true

            Row {
                id: content

                anchors.centerIn: parent
                height: win.barHeight

                Repeater {
                    id: slots

                    model: win.visibleKeys

                    delegate: Item {
                        id: slot

                        required property string modelData
                        required property int index

                        readonly property real moduleWidth: loader.item ? loader.item.implicitWidth : 0
                        readonly property bool lifted: win.dragKey === modelData
                        readonly property real centerX: island.x + win.ear + content.x + slot.x + slot.lead + loader.width / 2

                        z: lifted ? 5 : 0
                        // the others step back a little while one is moved
                        opacity: win.dragKey === "" || lifted ? 1 : 0.55

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.tFast }
                        }

                        transform: Translate {
                            x: slot.lifted ? win.dragDx : win.shiftOf(slot.index)

                            Behavior on x {
                                enabled: !slot.lifted
                                NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
                            }
                        }

                        readonly property string prevKey: index > 0 ? win.visibleKeys[index - 1] : ""
                        // A faint dot between module groups, a plain gap inside one.
                        readonly property bool separated: index > 0
                            && win.categories[prevKey] !== win.categories[modelData]
                        readonly property int lead: index === 0 ? 0 : (separated ? 30 : 12)

                        width: lead + (loader.item ? loader.item.implicitWidth : 0)
                        height: win.barHeight

                        // lit: this dot is one of the two privacy marks, and on
                        readonly property bool lit: (win.screenLit && index === win.screenSep)
                            || (win.micLit && index === win.micSep)

                        Rectangle {
                            visible: slot.separated
                            x: slot.lead / 2 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: slot.lit ? 4 : 3
                            height: width
                            color: !slot.lit ? Theme.tint(Theme.ink, 0.22)
                                : slot.index === win.screenSep ? Theme.alert : Theme.good

                            Behavior on color {
                                ColorAnimation { duration: Theme.tSlow }
                            }
                        }

                        Loader {
                            id: loader

                            readonly property string prevKey: slot.prevKey

                            x: slot.lead
                            height: win.barHeight
                            sourceComponent: win.componentFor[slot.modelData]
                        }

                        // the module being moved: an accent mark under it
                        SlantBar {
                            visible: slot.lifted
                            x: slot.lead
                            y: win.barHeight - 5
                            width: loader.width
                            height: 3
                            value: 1
                        }

                        // Double-click and hold: move it. It only watches the
                        // pointer (a passive grab), so the module's own clicks,
                        // hover and slider are untouched. Right-click: its card.
                        Item {
                            x: slot.lead
                            z: 2
                            width: loader.width
                            height: win.barHeight

                            PointHandler {
                                acceptedButtons: Qt.LeftButton

                                onActiveChanged: {
                                    if (active)
                                        win.gesturePress(slot.modelData, slot.index, point.scenePosition.x)
                                    else
                                        win.gestureRelease()
                                }
                                onPointChanged: if (active) win.gestureMove(slot.modelData, point.scenePosition.x)
                            }

                            // (the tray's icons keep right-click for their
                            // own menus; the tray is taken off in Settings)
                            MouseArea {
                                anchors.fill: parent
                                anchors.leftMargin: -5
                                anchors.rightMargin: -5
                                enabled: slot.modelData !== "tray"
                                acceptedButtons: Qt.RightButton
                                onClicked: win.toggleEdit(slot.modelData)
                            }
                        }

                        // Where the song / power button / date sit, and the
                        // module whose card is open, so their cards can hang
                        // right below them.
                        Binding {
                            when: slot.modelData === "media" || slot.modelData === "power"
                            target: win
                            property: slot.modelData === "power" ? "powerCenterX" : "mediaCenterX"
                            value: slot.centerX
                        }

                        Binding {
                            when: slot.modelData === "date"
                            target: win
                            property: "dateCenterX"
                            value: slot.centerX
                        }

                        Binding {
                            when: slot.modelData === win.editKey
                            target: win
                            property: "editCenterX"
                            value: slot.centerX
                        }
                    }
                }

                // Only on a bar too bare to have two dots between its groups;
                // by file, so the usual bar never even compiles it.
                Loader {
                    active: win.ownMarks && win.privacy !== null
                    height: win.barHeight
                    source: "PrivacyDots.qml"

                    onLoaded: {
                        item.barHeight = win.barHeight
                        item.privacy = Qt.binding(function() { return win.privacy })
                    }
                }
            }
        }
    }

    // -------------------------
    // Cards hanging below the island
    // -------------------------
    DropCard {
        id: mediaDrop

        island: island
        islandEar: win.ear
        islandCorner: island.cornerRadius
        fillOpacity: win.config.barOpacity
        open: win.mediaOpen
        anchorX: win.mediaCenterX

        onHoveredChanged: {
            if (hovered)
                closeDelay.stop()
            else if (win.mediaOpen && !win.mediaHot)
                closeDelay.restart()
        }
        cardWidth: win.cardWidth
        cardHeight: win.cardHeight

        MediaCard {
            x: 20
            y: 14
            width: parent.width - 40
            height: win.cardHeight - 30
            media: win.media
            open: win.mediaOpen
        }
    }

    DropCard {
        id: powerDrop

        island: island
        islandEar: win.ear
        islandCorner: island.cornerRadius
        fillOpacity: win.config.barOpacity
        open: win.powerOpen
        anchorX: win.powerCenterX
        cardWidth: 380
        cardHeight: 132
        minWidth: 340

        onHoveredChanged: win.powerPointerChanged()

        PowerCard {
            x: 18
            y: 14
            width: parent.width - 36
            height: 102
            open: win.powerOpen
            onCloseRequested: win.powerOpen = false
            onActivity: if (!win.powerTouched) powerIdle.restart()
            onRun: function(args) { win.run(args) }
        }
    }

    DropCard {
        id: calDrop

        island: island
        islandEar: win.ear
        islandCorner: island.cornerRadius
        fillOpacity: win.config.barOpacity
        open: win.calOpen
        anchorX: win.dateCenterX
        cardWidth: 290
        cardHeight: win.calHeight
        minWidth: 290

        onHoveredChanged: {
            if (hovered)
                calClose.stop()
            else if (win.calOpen && !win.dateHot)
                calClose.restart()
        }

        CalendarCard {
            x: 20
            y: 16
            width: parent.width - 40
            today: win.clock.date
            open: win.calOpen
        }
    }

    DropCard {
        id: editDrop

        island: island
        islandEar: win.ear
        islandCorner: island.cornerRadius
        fillOpacity: win.config.barOpacity
        open: win.editOpen
        anchorX: win.editKey === "" ? island.x + island.width / 2 : win.editCenterX
        cardWidth: 330
        cardHeight: moduleCard.wantedHeight + 32
        minWidth: 330

        onHoveredChanged: win.editPointerChanged()

        ModuleCard {
            id: moduleCard

            x: 20
            y: 16
            width: parent.width - 40
            config: win.config
            key: win.editKey

            onSetValue: (name, value) => win.saveSetting(name, value)
            onAddModule: key => win.addModule(key)
            onRemoveModule: win.removeModule()
            onRun: args => {
                win.editOpen = false
                win.run(args)
            }
        }
    }

    DropCard {
        id: trayDrop

        island: island
        islandEar: win.ear
        islandCorner: island.cornerRadius
        fillOpacity: win.config.barOpacity
        open: win.trayOpen
        anchorX: win.trayCenterX
        cardWidth: 280
        cardHeight: trayMenu.wantedHeight + 30
        minWidth: 280

        onHoveredChanged: win.trayPointerChanged()

        TrayMenu {
            id: trayMenu

            x: 20
            y: 14
            width: parent.width - 40
            // kept while the card folds away, so it does not empty first;
            // let go once it is gone, so the program's menu is closed too
            item: trayDrop.visible ? win.trayItem : null
            onDone: win.trayOpen = false
        }
    }
}
