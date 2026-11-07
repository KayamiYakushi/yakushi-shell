import Quickshell
import Quickshell.Io
import QtQuick
import "topbar"

// Yakushi Shell: the one entry point for the top bar, Settings and the
// volume pill.
//
// The bar is always loaded. The volume pill is loaded only while it is on
// screen. Settings runs as a child process of the shell (settings.qml), so
// it costs nothing once closed.
//
// Everything is driven over IPC, e.g.
//   qs -p <this dir> ipc call settings toggle
//   qs -p <this dir> ipc call volumeOsd show
//   qs -p <this dir> ipc call topbar toggle
// scripts/yakushi-shell.sh starts the shell; the other scripts are thin
// wrappers around these calls for keybinds.
ShellRoot {
    id: root

    // ------------------------------------------------------------------
    // Top bar
    // ------------------------------------------------------------------
    BarConfig {
        id: barConfig
    }

    SystemStats {
        id: barStats
        config: barConfig
    }

    MediaState {
        id: barMedia
        config: barConfig
    }

    // Bumped by the power shortcut (IPC); the bar on the focused monitor
    // opens its power menu.
    QtObject {
        id: barPower
        property int requests: 0
    }

    SystemClock {
        id: barClock

        // Tick once a second only when seconds are actually shown.
        precision: barConfig.seconds && barConfig.modules.time
            ? SystemClock.Seconds
            : SystemClock.Minutes
    }

    LazyLoader {
        id: bar

        active: true

        Variants {
            model: Quickshell.screens

            TopBar {
                required property var modelData

                screen: modelData
                config: barConfig
                stats: barStats
                clock: barClock
                media: barMedia
                power: barPower
            }
        }
    }

    IpcHandler {
        target: "topbar"

        // Read the config again by hand (it is watched, so this is only
        // needed after editing config.json in an editor that confuses
        // inotify).
        function reload(): void {
            barConfig.reload()
        }

        function power(): void {
            barPower.requests += 1
        }

        function show(): void {
            bar.active = true
        }

        function hide(): void {
            bar.active = false
        }

        function toggle(): void {
            bar.active = !bar.active
        }
    }

    // ------------------------------------------------------------------
    // Settings (SUPER + I): its own short-lived child process (settings.qml).
    // Loading it in here would keep ~60 MB after it closes; as a child it
    // hands every byte back when it quits.
    // ------------------------------------------------------------------
    readonly property string settingsQml: Quickshell.shellDir + "/settings.qml"

    Process {
        id: settings

        command: ["qs", "-n", "-p", root.settingsQml]
    }

    function settingsCall(fn: string, page: string): void {
        if (settings.running) {
            var args = ["qs", "-p", root.settingsQml, "ipc", "call", "settings", fn]
            if (fn === "open")
                args.push(page)
            Quickshell.execDetached(args)
        } else if (fn !== "hide") {
            settings.environment = { "YAKUSHI_SETTINGS_PAGE": page }
            settings.running = true
        }
    }

    IpcHandler {
        target: "settings"

        function open(page: string): void {
            root.settingsCall("open", page)
        }

        function hide(): void {
            root.settingsCall("hide", "")
        }

        function toggle(): void {
            root.settingsCall("toggle", "")
        }
    }

    // ------------------------------------------------------------------
    // Volume pill: loaded on a volume key, freed shortly after the last one
    // ------------------------------------------------------------------
    LazyLoader {
        id: volumeOsd

        VolumeOsd {}
    }

    Timer {
        id: volumeOsdUnload
        interval: 1550
        onTriggered: volumeOsd.active = false
    }

    IpcHandler {
        target: "volumeOsd"

        function show(): void {
            volumeOsd.active = true
            volumeOsd.item.poke()
            volumeOsdUnload.restart()
        }
    }
}
