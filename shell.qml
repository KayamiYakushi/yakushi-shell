import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick
import "topbar"
import "notifications"
import "launcher"

// Yakushi Shell: the one entry point for the top bar, Settings, the volume
// pill, notifications, the launcher and auto lock. (The lock screen itself
// is its own process: lock.qml, started by `yakushi lock`.)
//
// The bar and the notification server are always loaded. The volume pill
// and the notification pop-ups are loaded only while they are on screen.
// Settings runs as a child process of the shell (settings.qml), so it costs
// nothing once closed.
//
// Everything is driven over IPC, e.g.
//   qs -p <this dir> ipc call settings toggle
//   qs -p <this dir> ipc call volumeOsd reveal
//   qs -p <this dir> ipc call topbar toggle
// bin/yakushi starts the shell and wraps these calls for keybinds
// (yakushi settings, yakushi volume up, yakushi bar toggle, ...).
ShellRoot {
    id: root

    // No live reload: an update (pacman replaces files one by one) must not
    // load half-new files. `yakushi restart` loads a new version.
    Component.onCompleted: Quickshell.watchFiles = false

    // ------------------------------------------------------------------
    // Top bar
    // ------------------------------------------------------------------
    BarConfig {
        id: barConfig
    }

    SystemStats {
        id: barStats
        config: barConfig
        clock: barClock
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

        // not "show": qs reads `ipc call <target> show` as its own `ipc show`
        function reveal(): void {
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
    readonly property string settingsQml: Paths.shell + "/settings.qml"

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

        function reveal(): void {
            volumeOsd.active = true
            volumeOsd.item.poke()
            volumeOsdUnload.restart()
        }
    }

    // ------------------------------------------------------------------
    // Launcher (SUPER + Space) and clipboard history (SUPER + SHIFT + V): loaded on
    // open, freed once it has closed
    // ------------------------------------------------------------------
    LazyLoader {
        id: launcher

        Launcher {
            onDismissed: launcher.active = false
        }
    }

    // the same key again closes it; the other key switches it over
    function openLauncher(mode: string): void {
        launcher.active = true
        var card = launcher.item
        if (card.showing && card.mode === mode)
            card.hide()
        else
            card.open(mode)
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.openLauncher("apps")
        }

        function clipboard(): void {
            root.openLauncher("clipboard")
        }

        function hide(): void {
            if (launcher.item)
                launcher.item.hide()
        }
    }

    // ------------------------------------------------------------------
    // Notifications (org.freedesktop.Notifications)
    //
    // The server always runs, so an app sending a notification is answered
    // at once and never waits on a missing daemon. Turned off in Settings
    // (config "notifications.enabled"), a notification is simply not kept:
    // the app is told it closed and nothing is shown. Until the config has
    // been read, nothing is shown either.
    // ------------------------------------------------------------------
    readonly property bool notificationsOn: Config.loaded && Config.notifications.enabled !== false
    readonly property int notificationTimeout: {
        var t = Config.notifications.timeout
        return typeof t === "number" ? Math.max(2, Math.min(30, Math.round(t))) : 5
    }
    readonly property int maxPopups: 4

    NotificationServer {
        id: notifications

        keepOnReload: false
        persistenceSupported: false
        bodySupported: true
        bodyMarkupSupported: false        // plain text only: nothing in a
        bodyHyperlinksSupported: false    // notification is interpreted
        bodyImagesSupported: false
        actionsSupported: true
        imageSupported: true

        onNotification: function(notification) {
            if (!root.notificationsOn)
                return                      // not tracked: closed at once, never shown

            notification.tracked = true

            // keep the stack short: the oldest go first (the list may or
            // may not hold the new one yet, so it is left out and counted)
            var others = notifications.trackedNotifications.values.filter(function(other) {
                return other !== notification
            })
            for (var i = 0; i < others.length - (root.maxPopups - 1); i++)
                others[i].expire()
        }
    }

    // turned off: clear what is on screen
    onNotificationsOnChanged: {
        if (notificationsOn)
            return
        var shown = notifications.trackedNotifications.values.slice()
        for (var i = 0; i < shown.length; i++)
            shown[i].dismiss()
    }

    LazyLoader {
        active: notifications.trackedNotifications.values.length > 0

        NotificationPopups {
            server: notifications
            timeout: root.notificationTimeout
        }
    }

    // ------------------------------------------------------------------
    // Auto lock: after so many idle minutes (Settings -> Security; config
    // "lock.idleMinutes", 0 = off, 10 when never set). The compositor tells
    // us when you are idle, so nothing polls; a playing video (an idle
    // inhibitor) keeps the screen open. The lock runs as its own process.
    // ------------------------------------------------------------------
    readonly property int lockMinutes: {
        if (!Config.loaded)
            return 0
        var m = Config.lock.idleMinutes
        return typeof m === "number" ? Math.max(0, Math.min(240, Math.round(m))) : 10
    }

    IdleMonitor {
        enabled: root.lockMinutes > 0
        timeout: root.lockMinutes * 60
        respectInhibitors: true

        onIsIdleChanged: {
            if (isIdle)
                Quickshell.execDetached([Paths.shell + "/bin/yakushi", "lock"])
        }
    }

    // Lock before sleep: the lid, a `systemctl suspend` typed anywhere or
    // hibernate all wake up locked. A small guard (scripts/
    // yakushi-sleepguard.sh) holds a logind delay inhibitor and locks when
    // logind announces the sleep; it waits on D-Bus, nothing polls. It
    // lives and ends with the shell.
    Process {
        running: true
        command: [Paths.shell + "/bin/yakushi", "sleep-guard"]
    }
}
