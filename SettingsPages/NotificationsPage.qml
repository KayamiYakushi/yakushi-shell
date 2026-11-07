import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Notifications
//
// Show notifications or not at all, how long a pop-up stays, and a test.
// Off never leaves an app waiting: the shell still answers every
// notification at once, it just does not show it. Every change is saved by
// scripts/yakushi-notifyctl.py and applied by the shell at once.
Item {
    id: page

    property var hostWindow: null

    readonly property string helper: Paths.script("yakushi-notifyctl.py")

    property bool loaded: false
    property bool enabled: true
    property int timeout: 5
    property string status: ""

    function apply(data) {
        if (typeof data.enabled === "boolean")
            enabled = data.enabled
        if (typeof data.timeout === "number")
            timeout = data.timeout
        loaded = true
    }

    // one helper call at a time; a newer value for the same key replaces a
    // queued one (slider drags)
    property var queue: []

    function send(args) {
        queue = queue.filter(function(item) { return item[1] !== args[1] })
        queue.push(args)
        pump()
    }

    function pump() {
        if (setProc.running || queue.length === 0)
            return
        setProc.command = ["python3", helper].concat(queue.shift())
        setProc.running = true
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
                    page.status = "Could not read the notification settings."
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
                    if (!data.ok)
                        getProc.running = true
                } catch (e) {
                    page.status = "Could not save the notification settings."
                }
            }
        }

        onRunningChanged: {
            if (!running)
                page.pump()
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
                title: "NOTIFICATIONS"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.line
            }

            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF009A)
                label: "Show notifications"
                checked: page.enabled
                available: page.loaded

                onToggled: {
                    page.enabled = !page.enabled
                    page.send(["set", "enabled", page.enabled ? "on" : "off"])
                }
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                text: page.enabled
                    ? "Pop-ups appear at the top right of the screen you are on. Critical ones (a low battery, for example) stay until you close them."
                    : "Off: nothing is shown, ever. Apps still get their answer at once, so none of them waits or freezes."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
                lineHeight: 1.2
            }

            Slider {
                width: parent.width
                opacity: page.enabled && page.loaded ? 1 : 0.35
                enabled: page.enabled && page.loaded
                label: "Pop-up time  " + page.timeout + " s"
                icon: String.fromCodePoint(0xF0954)
                tint: Theme.accent
                value: (page.timeout - 2) / 28

                onSliding: function(v) {
                    var next = 2 + Math.round(v * 28)
                    if (next !== page.timeout) {
                        page.timeout = next
                        page.send(["set", "timeout", String(next)])
                    }
                }

                onSettled: function(v) {
                    page.timeout = 2 + Math.round(v * 28)
                    page.send(["set", "timeout", String(page.timeout)])
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.line
            }

            // test
            Rectangle {
                id: testButton

                width: testLabel.implicitWidth + 32
                height: 30
                color: testMouse.containsMouse ? Theme.tint(Theme.accent, 0.12) : Theme.card
                border.width: 1
                border.color: testMouse.containsMouse ? Theme.accent : Theme.line

                Behavior on border.color {
                    ColorAnimation { duration: Theme.tFast }
                }

                Text {
                    id: testLabel

                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "SEND A TEST"
                    color: testMouse.containsMouse ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }

                MouseArea {
                    id: testMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.send(["test"])
                }
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
