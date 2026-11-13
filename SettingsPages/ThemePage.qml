import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Appearance -> Theme
//
// The accent colour (presets or any #rrggbb), how see-through the shell's
// panels are, and the launcher's opening speed and opacity
// (scripts/yakushi-launchctl.py). Accent and panel opacity live in Theme and
// are saved by ThemeState when Settings closes.
Item {
    id: page

    property var hostWindow: null

    property var presets: [
        { name: "MONO",    accent: "#ffffff" },
        { name: "RED",     accent: "#ff003c" },
        { name: "SAKURA",  accent: "#ff7a9d" },
        { name: "AMBER",   accent: "#ffb000" },
        { name: "MATCHA",  accent: "#9ccc65" },
        { name: "MINT",    accent: "#3ee6b5" },
        { name: "CYAN",    accent: "#00d4ff" },
        { name: "OCEAN",   accent: "#4d8dff" },
        { name: "VIOLET",  accent: "#9d7bff" },
        { name: "ORCHID",  accent: "#e070ff" }
    ]

    // ---- launcher animation (scripts/yakushi-launchctl.py)
    property bool launcherLoaded: false
    property int launcherAnim: 480
    function saveLauncherAnim() {
        if (launcherSet.running) {
            launcherSave.restart()          // try again once the last save is done
            return
        }
        launcherSet.command = ["python3", Paths.script("yakushi-launchctl.py"), "set", "animation", String(launcherAnim)]
        launcherSet.running = true
    }

    Process {
        id: launcherGet

        running: true
        command: ["python3", Paths.script("yakushi-launchctl.py"), "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok && typeof data.animationMs === "number")
                        page.launcherAnim = data.animationMs
                    if (data.ok && typeof data.opacity === "number") {
                        page.launcherOpacity = data.opacity
                        page.launcherOpacitySet = true
                    }
                } catch (e) {
                }
                page.launcherLoaded = true
            }
        }
    }

    Process {
        id: launcherSet
    }

    Timer {
        id: launcherSave
        interval: 150
        onTriggered: page.saveLauncherAnim()
    }

    // ---- launcher card opacity; until set it follows Panel opacity
    property bool launcherOpacitySet: false
    property real launcherOpacity: 0.8
    readonly property real launcherOpacityShown: launcherOpacitySet ? launcherOpacity : Theme.glass

    function saveLauncherOpacity() {
        if (launcherOpacityProc.running) {
            launcherOpacitySave.restart()
            return
        }
        launcherOpacityProc.command = ["python3", Paths.script("yakushi-launchctl.py"), "set", "opacity", launcherOpacity.toFixed(2)]
        launcherOpacityProc.running = true
    }

    Process {
        id: launcherOpacityProc
    }

    Timer {
        id: launcherOpacitySave
        interval: 150
        onTriggered: page.saveLauncherOpacity()
    }

    // ------------------------------------------------------------------
    // Accent
    // ------------------------------------------------------------------
    function hexOf(c) {
        function h(v) {
            var s = Math.round(v * 255).toString(16)
            return s.length < 2 ? "0" + s : s
        }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    function applyCustom(raw) {
        var value = raw.trim()
        if (value.charAt(0) !== "#")
            value = "#" + value
        if (/^#[0-9a-fA-F]{6}$/.test(value)) {
            Theme.accent = value.toLowerCase()
            return true
        }
        return false
    }

    ScrollHint {
        flick: flick
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
                title: "THEME"
            }

            Divider {}

            SectionHead { text: "ACCENT" }

            Grid {
                id: presetGrid

                width: parent.width
                columns: 5
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: page.presets

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool selected: Qt.colorEqual(Theme.accent, modelData.accent)

                        width: (presetGrid.width - 4 * presetGrid.columnSpacing) / 5
                        height: 40
                        color: Theme.card
                        border.width: 1
                        border.color: selected
                            ? modelData.accent
                            : (presetMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 12
                                height: 12
                                color: modelData.accent
                                border.width: 1
                                border.color: Theme.inkSoft
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: modelData.name
                                color: parent.parent.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: presetMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.accent = modelData.accent
                        }
                    }
                }
            }

            // Custom colour: any #rrggbb
            Item {
                width: parent.width
                height: 30

                Text {
                    id: customIcon

                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF03D8)
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 14
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: customIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Custom colour"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Rectangle {
                    id: hexField

                    property bool invalid: false

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 132
                    height: 26
                    color: Theme.groove
                    border.width: 1
                    border.color: invalid
                        ? Theme.alert
                        : (hexInput.activeFocus ? Theme.accent : Theme.line)

                    Rectangle {
                        id: swatch

                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        color: Theme.accent
                    }

                    TextInput {
                        id: hexInput

                        anchors.left: swatch.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.hexOf(Theme.accent)
                        maximumLength: 7
                        color: Theme.ink
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        selectByMouse: true

                        onTextEdited: hexField.invalid = false

                        onAccepted: {
                            hexField.invalid = !page.applyCustom(text)
                            if (!hexField.invalid)
                                focus = false
                        }

                        onActiveFocusChanged: {
                            if (!activeFocus) {
                                hexField.invalid = false
                                text = Qt.binding(function() { return page.hexOf(Theme.accent) })
                            }
                        }
                    }
                }
            }

            Divider {}

            SectionHead { text: "GLASS" }

            Slider {
                width: parent.width
                label: "Panel opacity  " + Math.round(Theme.glass * 100) + "%"
                icon: "◐"
                tint: Theme.accent
                value: (Theme.glass - 0.40) / 0.60

                onSliding: function(v) {
                    Theme.glass = 0.40 + (v * 0.60)
                }

                onSettled: function(v) {
                    Theme.glass = 0.40 + (v * 0.60)
                }
            }

            Divider {}

            // ---------------- Launcher ----------------
            SectionHead {
                text: "LAUNCHER"
                action: "TRY IT"
                // open the launcher to see the new speed and opacity
                onActivated: Quickshell.execDetached([Paths.shell + "/bin/yakushi", "launcher"])
            }

            Slider {
                width: parent.width
                opacity: page.launcherLoaded ? 1 : 0.35
                enabled: page.launcherLoaded
                label: "Opening animation  " + (page.launcherAnim > 0 ? page.launcherAnim + " ms" : "off")
                icon: String.fromCodePoint(0xF0954)
                tint: Theme.accent
                value: page.launcherAnim / 1000

                // in steps of 20 ms
                onSliding: function(v) {
                    var next = Math.round(v * 50) * 20
                    if (next !== page.launcherAnim) {
                        page.launcherAnim = next
                        launcherSave.restart()
                    }
                }

                onSettled: function(v) {
                    page.launcherAnim = Math.round(v * 50) * 20
                    launcherSave.stop()
                    page.saveLauncherAnim()
                }
            }

            Slider {
                width: parent.width
                opacity: page.launcherLoaded ? 1 : 0.35
                enabled: page.launcherLoaded
                label: "Launcher opacity  " + Math.round(page.launcherOpacityShown * 100) + "%"
                icon: "◐"
                tint: Theme.accent
                value: (page.launcherOpacityShown - 0.30) / 0.70

                // in steps of 1 %
                onSliding: function(v) {
                    var next = Math.round(30 + v * 70) / 100
                    if (next !== page.launcherOpacity || !page.launcherOpacitySet) {
                        page.launcherOpacity = next
                        page.launcherOpacitySet = true
                        launcherOpacitySave.restart()
                    }
                }

                onSettled: function(v) {
                    page.launcherOpacity = Math.round(30 + v * 70) / 100
                    page.launcherOpacitySet = true
                    launcherOpacitySave.stop()
                    page.saveLauncherOpacity()
                }
            }
        }
    }
}
