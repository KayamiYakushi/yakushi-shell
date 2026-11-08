import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "lock"

// The lock screen (SUPER + Tab, auto lock, Suspend): its own process,
// started by `yakushi lock`, never by the shell.
//
// Why a process of its own: the top bar can crash, restart or be updated
// without touching the lock, and nothing of the lock stays in memory once
// you are back in.
//
// It uses the ext-session-lock protocol, so the compositor itself keeps the
// session locked: if this process dies, the screen stays locked (Hyprland
// shows its own fallback), `yakushi lock` starts it again, and with
// misc:allow_session_lock_restore the new one takes over. Only a password
// PAM accepts ends the lock.
//
// YAKUSHI_LOCK_PREVIEW=1 shows the same screen in an ordinary window on the
// focused monitor and locks nothing: for trying the look and your password
// safely (Esc or the right password closes it).
ShellRoot {
    id: root

    readonly property bool preview: Quickshell.env("YAKUSHI_LOCK_PREVIEW") === "1"
    property bool leaving: false
    property string wallpaper: ""         // the picture behind the lock, dimmed

    readonly property bool clock24: Config.topbar.clock24 === true

    // A lock must not reload itself halfway (e.g. while install.sh copies
    // new files): what is loaded stays until the process ends.
    Component.onCompleted: {
        Quickshell.watchFiles = false
        applyAccent()
    }

    // the accent from Settings (read only: the lock never saves anything)
    function applyAccent() {
        var a = Config.appearance.accent
        if (typeof a === "string" && /^#[0-9a-fA-F]{6}$/.test(a))
            Theme.accent = a
    }

    Connections {
        target: Config

        function onAppearanceChanged() {
            root.applyAccent()
        }
    }

    LockContext {
        id: lockContext

        onUnlocked: root.leave()
    }

    // fade out first, then hand the session back and quit
    function leave() {
        if (leaving)
            return
        leaving = true
        unlockTimer.restart()
    }

    Timer {
        id: unlockTimer
        interval: Theme.tMid
        onTriggered: {
            if (root.preview) {
                Qt.quit()
                return
            }
            sessionLock.locked = false
            quitTimer.restart()
        }
    }

    Timer {
        id: quitTimer
        interval: 150
        onTriggered: Qt.quit()
    }

    // ------------------------------------------------------------------
    // The wallpaper (yakushi-wallpaperctl.py remembers it)
    // ------------------------------------------------------------------
    Process {
        running: true
        command: ["python3", Paths.script("yakushi-wallpaperctl.py"), "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpaper = JSON.parse(text).current || ""
                } catch (e) {
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // The real lock
    // ------------------------------------------------------------------
    WlSessionLock {
        id: sessionLock

        locked: !root.preview

        // The compositor refused or ended the lock (another locker holds it):
        // nothing is ours to cover, so go.
        onLockedChanged: {
            if (!locked && !root.leaving && !root.preview)
                Qt.quit()
        }

        WlSessionLockSurface {
            id: lockSurface

            color: "black"

            LockSurface {
                anchors.fill: parent
                context: lockContext
                wallpaper: root.wallpaper
                clock24: root.clock24
                shown: !root.leaving
            }
        }
    }

    // ------------------------------------------------------------------
    // Preview: the same screen in a plain window, nothing locked
    // ------------------------------------------------------------------
    LazyLoader {
        active: root.preview

        PanelWindow {
            id: previewWindow

            function focusedScreen() {
                var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
                var list = Quickshell.screens
                for (var i = 0; i < list.length; i++)
                    if (list[i].name === name)
                        return list[i]
                return list.length > 0 ? list[0] : null
            }

            screen: focusedScreen()
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "black"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "yakushi-lock-preview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            LockSurface {
                anchors.fill: parent
                context: lockContext
                wallpaper: root.wallpaper
                clock24: root.clock24
                shown: !root.leaving
            }

            Shortcut {
                sequence: "Escape"
                onActivated: Qt.quit()
            }
        }
    }

    // ------------------------------------------------------------------
    // `yakushi suspend` asks this before sleeping: are all screens covered?
    // ------------------------------------------------------------------
    IpcHandler {
        target: "lock"

        function isLocked(): string {
            return sessionLock.secure ? "yes" : "no"
        }
    }
}
