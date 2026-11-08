import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Screenshots
//
// Every screenshot goes to the clipboard. Writing it to a file as well is
// off until you turn it on here, so no folder fills up on its own. Saved by
// scripts/yakushi-screenshot.py; the next screenshot follows the switch.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: Paths.script("yakushi-screenshot.py")

    property bool loaded: false
    property bool save: false
    property string folder: ""
    property string status: ""

    function apply(data) {
        if (typeof data.save === "boolean")
            save = data.save
        if (typeof data.folder === "string")
            folder = data.folder
        loaded = true
    }

    function shortPath(path) {
        var home = Paths.home
        return home !== "" && path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path
    }

    Process {
        id: getProc

        running: true
        command: ["python3", page.helper, "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok)
                        page.apply(data)
                    else
                        page.status = data.message || ""
                } catch (e) {
                    page.status = "Could not read the screenshot settings."
                }
            }
        }
    }

    Process {
        id: setProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.status = data.message || ""
                    if (data.ok)
                        page.apply(data)
                    else
                        getProc.running = true
                } catch (e) {
                    page.status = "Could not save the screenshot settings."
                }
            }
        }
    }

    component KeyRow: Item {
        property string keys: ""
        property string what: ""

        width: parent ? parent.width : 0
        height: 24

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 180
            text: parent.keys
            color: Theme.accent
            font.family: Theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 180
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.what
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: body.height + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body

            width: flick.width
            spacing: 16

            PageTitle {
                width: parent.width
                title: "SCREENSHOTS"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.line
            }

            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF024B)
                label: "Also save to a folder"
                checked: page.save
                available: page.loaded && !setProc.running

                onToggled: {
                    page.save = !page.save
                    setProc.command = ["python3", page.helper, "set", "save", page.save ? "on" : "off"]
                    setProc.running = true
                }
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                text: page.save
                    ? "Every screenshot is copied to the clipboard and kept as a PNG in " + page.shortPath(page.folder) + "."
                    : "Screenshots go to the clipboard only: paste them where you need them. Nothing is written to disk."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
                lineHeight: 1.2
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.line
            }

            Column {
                width: parent.width
                spacing: 2

                KeyRow { keys: "SUPER + SHIFT + S"; what: "Area (drag; Esc cancels)" }
                KeyRow { keys: "SUPER + CTRL + S"; what: "Focused window" }
                KeyRow { keys: "SUPER + DELETE"; what: "Whole screen (the one you are on)" }
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                text: "Change the keys in Settings -> Keybinds."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: page.status !== ""
                wrapMode: Text.Wrap
                text: page.status
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }
    }
}
