import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Default Apps -> Clipboard history (under Screenshots)
//
// Off: nothing you copy is recorded and the old history is deleted.
// Saved by scripts/yakushi-launchctl.py ("launcher.clipboard"), which also
// starts or stops the recorders at once.
Column {
    id: section

    spacing: 16

    readonly property string helper: Paths.script("yakushi-launchctl.py")

    property bool loaded: false
    property bool on: true
    property string note: ""

    Process {
        id: getProc

        running: true
        command: ["python3", section.helper, "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok && typeof data.clipboard === "boolean")
                        section.on = data.clipboard
                } catch (e) {
                }
                section.loaded = true
            }
        }
    }

    Process {
        id: setProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    section.note = data.message || ""
                    if (typeof data.clipboard === "boolean")
                        section.on = data.clipboard
                } catch (e) {
                    section.note = "Could not change clipboard history."
                }
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        text: "CLIPBOARD"
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 11
        font.letterSpacing: 2
    }

    ToggleRow {
        width: parent.width
        icon: String.fromCodePoint(0xF0147)
        label: "Clipboard history"
        checked: section.on
        available: section.loaded && !setProc.running

        onToggled: {
            section.on = !section.on
            setProc.command = ["python3", section.helper, "clipboard", section.on ? "on" : "off"]
            setProc.running = true
        }
    }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: section.note !== "" ? section.note
            : section.on ? "Keeps what you copy, passwords and screenshots too (SUPER + SHIFT + V). Off: nothing is kept and the old history is deleted."
            : "Off: nothing you copy is kept."
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 10
        lineHeight: 1.2
    }
}
