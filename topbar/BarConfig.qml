import QtQuick
import "../"

// Top bar settings: the "topbar" section of the config (Config.topbar,
// written by Settings -> Top Bar), checked and filled in with defaults.
// The accent colour follows Config.appearance. Both apply the moment the
// config file changes (inotify); nothing polls and nothing needs a ping.
Item {
    id: cfg

    visible: false

    property bool seconds: true
    property bool clock24: true
    property real barOpacity: 0.90
    property string visualizer: "hover"

    readonly property var defaultOrder: [
        "workspaces", "ram", "cpu", "cpuTemp", "gpuTemp",
        "date", "time", "media", "volume", "power"
    ]
    property var order: defaultOrder
    property var modules: ({
        workspaces: true,
        ram: true,
        cpu: true,
        cpuTemp: true,
        gpuTemp: true,
        media: true,
        volume: true,
        date: true,
        time: true,
        power: true
    })

    function reload() {
        Config.reload()
    }

    function apply(data) {
        if (typeof data.seconds === "boolean")
            seconds = data.seconds

        if (typeof data.clock24 === "boolean")
            clock24 = data.clock24

        if (typeof data.opacity === "number")
            barOpacity = Math.max(0.40, Math.min(1.0, data.opacity))

        if (data.visualizer === "hover" || data.visualizer === "always" || data.visualizer === "off")
            visualizer = data.visualizer

        if (Array.isArray(data.order)) {
            var seen = {}
            var list = []

            data.order.concat(defaultOrder).forEach(function(key) {
                if (defaultOrder.indexOf(key) >= 0 && !seen[key]) {
                    seen[key] = true
                    list.push(key)
                }
            })

            if (list.join() !== order.join())
                order = list
        }

        if (data.modules && typeof data.modules === "object") {
            var next = {}

            for (var key in modules)
                next[key] = typeof data.modules[key] === "boolean"
                    ? data.modules[key]
                    : modules[key]

            modules = next
        }
    }

    // the shell's own cards (launcher, notifications) follow Settings ->
    // Appearance too: accent and panel opacity
    function applyAppearance(data) {
        if (typeof data.accent === "string" && /^#[0-9a-fA-F]{6}$/.test(data.accent))
            Theme.accent = data.accent
        if (typeof data.panelOpacity === "number")
            Theme.glass = Math.max(0.40, Math.min(1.0, data.panelOpacity))
    }

    Component.onCompleted: {
        apply(Config.topbar)
        applyAppearance(Config.appearance)
    }

    Connections {
        target: Config

        function onTopbarChanged() {
            cfg.apply(Config.topbar)
        }

        function onAppearanceChanged() {
            cfg.applyAppearance(Config.appearance)
        }
    }
}
