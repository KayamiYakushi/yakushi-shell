import QtQuick
import Quickshell
import Quickshell.Io

// Persists the Settings look (panel opacity + accent colour).
//
// Settings is a short-lived process, so these values would reset to their
// defaults every time it was reopened. This takes them from Config once at
// start-up and saves them (debounced) whenever they change. Nothing runs in
// the background: one tiny helper call per change burst, none while idle.
Item {
    id: state

    visible: false

    property bool applying: false
    property bool dirty: false

    readonly property string helper: Paths.script("yakushi-uistatectl.py")

    function hexOf(c) {
        function h(v) {
            var s = Math.round(v * 255).toString(16)
            return s.length < 2 ? "0" + s : s
        }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    function apply(data) {
        applying = true

        if (typeof data.panelOpacity === "number")
            Theme.glass = Math.max(0.40, Math.min(1.0, data.panelOpacity))

        if (typeof data.accent === "string" && /^#[0-9a-fA-F]{6}$/.test(data.accent)) {
            // A saved "Blaze" accent (#ff5a1f) from an earlier build is plain Red again.
            Theme.accent = data.accent.toLowerCase() === "#ff5a1f" ? "#ff003c" : data.accent
        }

        applying = false
    }

    function schedule() {
        if (applying)
            return

        dirty = true
        saveDebounce.restart()
    }

    // Save right now (used when Settings closes, before the process exits).
    function flush() {
        saveDebounce.stop()

        if (!dirty || saveProc.running)
            return

        dirty = false
        saveProc.command = ["python3", helper, "set", Theme.glass.toFixed(3), hexOf(Theme.accent)]
        saveProc.running = true
    }

    // Load once only: later saves must not pull a slider back mid-drag.
    property bool started: false

    function start() {
        if (started || !Config.loaded)
            return
        started = true
        apply(Config.appearance)
    }

    Component.onCompleted: start()

    Connections {
        target: Config

        function onLoadedChanged() {
            state.start()
        }
    }

    Connections {
        target: Theme

        function onGlassChanged() {
            state.schedule()
        }

        function onAccentChanged() {
            state.schedule()
        }

    }

    Timer {
        id: saveDebounce
        interval: 250
        repeat: false
        onTriggered: state.flush()
    }

    Process {
        id: saveProc

        // A change that arrived while the previous save was running.
        onRunningChanged: {
            if (!running && state.dirty)
                state.flush()
        }
    }
}
