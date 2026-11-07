pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Every place the shell reads or writes, worked out in one spot (the QML twin
// of scripts/yakushi_paths.py).
//
// Nothing here is a fixed path: user folders come from the XDG Base Directory
// variables (with the spec's defaults) and from user-dirs.dirs, so they are
// right in any language; the shell's own files are found from where it runs.
Singleton {
    id: paths

    readonly property string home: Quickshell.env("HOME") || ""

    // $variable if it is an absolute path (the spec ignores relative ones),
    // else ~/<fallback>.
    function xdg(variable, fallback) {
        var value = Quickshell.env(variable) || ""
        return value.charAt(0) === "/" ? value : home + "/" + fallback
    }

    readonly property string configHome: xdg("XDG_CONFIG_HOME", ".config")
    readonly property string dataHome: xdg("XDG_DATA_HOME", ".local/share")
    readonly property string stateHome: xdg("XDG_STATE_HOME", ".local/state")
    readonly property string cacheHome: xdg("XDG_CACHE_HOME", ".cache")

    // The shell itself, and its helpers.
    readonly property string shell: Quickshell.shellDir
    readonly property string scripts: shell + "/scripts"

    function script(name) {
        return scripts + "/" + name
    }

    // Yakushi's settings folder.
    readonly property string config: configHome + "/yakushi"

    // XDG user folders (in whatever language they were set up).
    property string documents: userDir("DOCUMENTS")
    property string downloads: userDir("DOWNLOAD")
    property string pictures: userDir("PICTURES")

    property var userDirs: ({})

    function userDir(name) {
        var key = "XDG_" + name + "_DIR"
        var fromEnv = Quickshell.env(key) || ""
        if (fromEnv.charAt(0) === "/")
            return fromEnv
        var fromFile = userDirs[key]
        return fromFile && fromFile.charAt(0) === "/" ? fromFile : home
    }

    FileView {
        path: paths.configHome + "/user-dirs.dirs"
        printErrors: false
        onLoaded: {
            var found = {}
            text().split("\n").forEach(function(line) {
                var m = line.trim().match(/^(XDG_[A-Z]+_DIR)="?([^"]*)"?$/)
                if (m)
                    found[m[1]] = m[2].replace(/^\$HOME(?=\/|$)/, paths.home)
            })
            paths.userDirs = found
        }
    }
}
