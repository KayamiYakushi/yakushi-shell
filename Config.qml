pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The user's settings, read from ~/.config/yakushi/config.json.
//
// One watched file for the whole shell: every part reads its section from
// here (Config.topbar, Config.appearance, Config.terminal) instead of
// opening files of its own. The file is only ever written by the Python
// helpers in scripts/ (see yakushi_config.py), atomically and under a lock;
// QML never writes it. Changes arrive through inotify, so nothing polls.
Singleton {
    id: config

    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") || "") + "/.config") + "/yakushi"
    readonly property string path: dir + "/config.json"
    readonly property string profilePicture: dir + "/profile-picture"

    // true once the file has been read at least once
    property bool loaded: false

    property var topbar: ({})
    property var appearance: ({})
    property var terminal: ({})

    // Read the file again now (e.g. after a helper saved it).
    function reload() {
        file.reload()
    }

    function section(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value) ? value : ({})
    }

    function parse(raw) {
        var data

        try {
            data = JSON.parse(raw)
        } catch (e) {
            // Saves are atomic, so this is a broken file, not half a write;
            // look once more in case it is fixed, then leave it.
            if (retries < 1) {
                retries += 1
                retry.restart()
            }
            return
        }
        retries = 0

        if (data === null || typeof data !== "object")
            return

        // Only a section that really changed notifies its readers.
        var next = section(data.topbar)
        if (JSON.stringify(next) !== JSON.stringify(topbar))
            topbar = next
        next = section(data.appearance)
        if (JSON.stringify(next) !== JSON.stringify(appearance))
            appearance = next
        next = section(data.terminal)
        if (JSON.stringify(next) !== JSON.stringify(terminal))
            terminal = next
        loaded = true
    }

    property int retries: 0

    Timer {
        id: retry
        interval: 300
        onTriggered: file.reload()
    }

    FileView {
        id: file

        path: config.path
        watchChanges: true
        printErrors: false

        onFileChanged: {
            config.retries = 0
            reload()
        }
        onLoaded: config.parse(text())
    }
}
