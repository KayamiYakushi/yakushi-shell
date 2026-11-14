import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick

// Is something watching the screen or listening to the microphone? For the
// two marks at the end of the bar (PrivacyDots.qml). Nothing polls: PipeWire
// reports its links, Hyprland says when a screen or window is being copied.
//
// Microphone: a program's stream that PipeWire has linked to a real input (a
// microphone, a headset). A stream that records what the speakers play (the
// bar's own visualizer, a mixer's level meter) hangs on an output instead
// and does not count.
//
// Screen: Hyprland's `screencast` events, which cover everything that copies
// the screen (OBS, a browser sharing it, a recorder). A screenshot is such a
// copy too, for an instant, so the mark waits a moment before it lights.
// Hyprland cannot be asked afterwards: a recording that was already running
// when the shell started is seen from its next start on.
Item {
    id: privacy

    visible: false

    // ---- microphone
    readonly property var micStreams: {
        var out = []
        var groups = Pipewire.linkGroups.values
        for (var i = 0; i < groups.length; i++) {
            var from = groups[i].source
            var to = groups[i].target
            if (!from || !to || from.isStream || from.isSink || !to.isStream)
                continue
            if ((from.type & PwNodeType.Audio) && out.indexOf(to) < 0)
                out.push(to)
        }
        return out
    }

    readonly property bool mic: micStreams.length > 0

    // who is listening, for the hover text
    readonly property string micApps: {
        var names = []
        for (var i = 0; i < micStreams.length; i++) {
            var node = micStreams[i]
            var name = (node.properties && node.properties["application.name"]) || node.description || node.name || ""
            if (name !== "" && names.indexOf(name) < 0)
                names.push(name)
        }
        return names.join(", ")
    }

    // a stream tells its program's name only while it is tracked
    PwObjectTracker {
        objects: privacy.micStreams
    }

    // ---- screen
    property var casts: []             // "monitor,DP-1", "window,..." being copied now
    property bool castPlain: false     // an older Hyprland only says on / off
    property bool namedEvents: false
    readonly property bool screenNow: namedEvents ? casts.length > 0 : castPlain
    property bool screen: false        // lit: it has lasted longer than a screenshot

    // the monitors being copied ("DP-1, HDMI-A-1"), or "window"; kept from
    // the last copy while a frame-by-frame recorder is between two frames
    property string screenWhat: ""
    onCastsChanged: if (casts.length > 0) screenWhat = castNames()

    function castNames() {
        var names = []
        for (var i = 0; i < casts.length; i++) {
            var parts = casts[i].split(",")
            var name = parts[0] === "monitor" && parts.length > 1 ? parts[1] : parts[0]
            if (name !== "" && names.indexOf(name) < 0)
                names.push(name)
        }
        return names.join(", ")
    }

    function castEvent(name, data) {
        var cut = data.indexOf(",")
        if (cut < 0)
            return
        var on = data.substring(0, cut) === "1"
        var what = data.substring(cut + 1)
        if (name === "screencast") {
            castPlain = on
            return
        }
        namedEvents = true
        var next = casts.filter(function(entry) { return entry !== what })
        if (on)
            next.push(what)
        casts = next
    }

    // Copying "now", or a moment ago: some recorders ask frame by frame, so
    // Hyprland says on, off, on, off for as long as they run.
    property bool held: false

    onScreenNowChanged: {
        if (!screenNow) {
            release.restart()
            return
        }
        release.stop()
        if (!held) {
            held = true
            light.restart()
        }
    }

    Timer {
        id: release
        interval: 400
        onTriggered: {
            light.stop()
            privacy.held = false
            privacy.screen = false
        }
    }

    // a screenshot is let go of before this runs out
    Timer {
        id: light
        interval: 700
        onTriggered: privacy.screen = privacy.held
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "screencast" || event.name === "screencastv2")
                privacy.castEvent(event.name, event.data)
        }
    }
}
