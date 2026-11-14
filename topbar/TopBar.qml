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
// Modules are laid out in the order chosen in Settings -> Top Bar; after
// them two marks light up while the screen is recorded or the microphone
// is heard (PrivacyDots.qml).
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
    property var privacy: null     // PrivacyState: is the screen watched, the microphone heard

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

    onMediaOpenChanged: if (!mediaOpen) closeDelay.stop()

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
    implicitHeight: barHeight + cardHeight
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
        return true
    }

    readonly property var visibleKeys: {
        var list = []
        for (var i = 0; i < config.order.length; i++)
            if (shows(config.order[i]))
                list.push(config.order[i])
        return list
    }

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
            valueColor: Theme.inkSoft
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
            onClicked: win.run([Paths.shell + "/bin/yakushi", "settings", "network"])
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
                    model: win.visibleKeys

                    delegate: Item {
                        id: slot

                        required property string modelData
                        required property int index

                        readonly property string prevKey: index > 0 ? win.visibleKeys[index - 1] : ""
                        // A faint dot between module groups, a plain gap inside one.
                        readonly property bool separated: index > 0
                            && win.categories[prevKey] !== win.categories[modelData]
                        readonly property int lead: index === 0 ? 0 : (separated ? 30 : 12)

                        width: lead + (loader.item ? loader.item.implicitWidth : 0)
                        height: win.barHeight

                        Rectangle {
                            visible: slot.separated
                            x: slot.lead / 2 - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 3
                            color: Theme.tint(Theme.ink, 0.22)
                        }

                        Loader {
                            id: loader

                            readonly property string prevKey: slot.prevKey

                            x: slot.lead
                            height: win.barHeight
                            sourceComponent: win.componentFor[slot.modelData]
                        }

                        // Where the song / power button sit, so their cards can
                        // hang right below them.
                        Binding {
                            when: slot.modelData === "media" || slot.modelData === "power"
                            target: win
                            property: slot.modelData === "power" ? "powerCenterX" : "mediaCenterX"
                            value: island.x + win.ear + content.x + slot.x + slot.lead + loader.width / 2
                        }
                    }
                }

                // Always last and not one of the modules: it cannot be
                // switched off or moved, and it takes no room while dark.
                PrivacyDots {
                    privacy: win.privacy
                    barHeight: win.barHeight
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
}
