import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Appearance -> Windows
//
// Gaps, corners, shadow and border of the windows Hyprland draws. Every
// change is saved by scripts/yakushi-windowctl.py and applied at once.
Item {
    id: page

    property var hostWindow: null
    readonly property string homeDir: Paths.home

    // ------------------------------------------------------------------
    // Windows: gaps and corners (yakushi-windowctl.py)
    // ------------------------------------------------------------------
    property bool windowLoaded: false
    property int gapsOut: 3
    property int gapsIn: 3
    property int rounding: 8
    property int lastRadius: 8
    property bool shadow: true
    property int shadowSize: 8
    property bool border: false
    property int borderSize: 2
    property string borderColor: "accent"
    property string windowStatus: ""
    property var windowQueue: []

    function windowHelperPath() {
        return Paths.script("yakushi-windowctl.py")
    }

    function loadWindow() {
        windowGet.command = ["python3", windowHelperPath(), "get"]
        windowGet.running = true
    }

    function sendWindow(key, value) {
        windowQueue = windowQueue.filter(function(item) { return item[0] !== key })
        windowQueue.push([key, String(value)])
        pumpWindow()
    }

    function pumpWindow() {
        if (windowSet.running || windowQueue.length === 0 || homeDir === "")
            return
        var next = windowQueue.shift()
        windowSet.command = ["python3", windowHelperPath(), "set", next[0], next[1]]
        windowSet.running = true
    }

    function setRounding(value) {
        rounding = value
        if (value > 0)
            lastRadius = value
        sendWindow("rounding", value)
    }

    Process {
        id: windowGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok) {
                        page.gapsOut = data.gaps_out
                        page.gapsIn = data.gaps_in
                        page.rounding = data.rounding
                        if (data.rounding > 0)
                            page.lastRadius = data.rounding
                        page.shadow = data.shadow === true
                        page.shadowSize = data.shadow_size || 8
                        page.border = data.border === true
                        page.borderSize = data.border_size || 2
                        page.borderColor = data.border_color || "accent"
                        page.windowLoaded = true
                    } else {
                        page.windowStatus = data.message
                    }
                } catch (e) {
                    page.windowStatus = "Could not read window settings."
                }
            }
        }
    }

    Process {
        id: windowSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.windowStatus = data.ok ? "" : data.message
                } catch (e) {
                    page.windowStatus = "Could not save window settings."
                }
            }
        }

        onRunningChanged: if (!running) page.pumpWindow()
    }

    Component.onCompleted: loadWindow()

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
                title: "WINDOWS"
            }

            Divider {}

            // ---------------- Gaps ----------------
            SectionHead { text: "GAPS" }

            Row {
                width: parent.width
                spacing: 28

                Slider {
                    width: (body.width - parent.spacing) / 2
                    opacity: page.windowLoaded ? 1 : 0.35
                    label: "Screen edge gap  " + page.gapsOut + "px"
                    icon: String.fromCodePoint(0xF00CE)
                    tint: Theme.accent
                    value: page.gapsOut / 30

                    onSliding: function(v) {
                        var next = Math.round(v * 30)
                        if (next !== page.gapsOut) {
                            page.gapsOut = next
                            page.sendWindow("gaps_out", next)
                        }
                    }

                    onSettled: function(v) {
                        page.gapsOut = Math.round(v * 30)
                        page.sendWindow("gaps_out", page.gapsOut)
                    }
                }

                Slider {
                    width: (body.width - parent.spacing) / 2
                    opacity: page.windowLoaded ? 1 : 0.35
                    label: "Gap between windows  " + page.gapsIn + "px"
                    icon: String.fromCodePoint(0xF00D2)
                    tint: Theme.accent
                    value: page.gapsIn / 20

                    onSliding: function(v) {
                        var next = Math.round(v * 20)
                        if (next !== page.gapsIn) {
                            page.gapsIn = next
                            page.sendWindow("gaps_in", next)
                        }
                    }

                    onSettled: function(v) {
                        page.gapsIn = Math.round(v * 20)
                        page.sendWindow("gaps_in", page.gapsIn)
                    }
                }
            }

            Divider {}

            // ---------------- Corners ----------------
            SectionHead { text: "CORNERS" }

            // Corners: cut (Hyprland rounding with rounding_power 1, set in
            // hyprland.lua) or sharp
            Row {
                width: parent.width
                spacing: 12
                opacity: page.windowLoaded ? 1 : 0.35

                Repeater {
                    model: [
                        { key: "rounded", name: "CUT" },
                        { key: "sharp", name: "SHARP" }
                    ]

                    delegate: Rectangle {
                        id: cornerCard

                        required property var modelData
                        readonly property bool selected: modelData.key === "sharp"
                            ? page.rounding === 0
                            : page.rounding > 0

                        width: (body.width - 12) / 2
                        height: 48
                        color: Theme.card
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (cornerMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 12

                            // Tiny window showing the corner style
                            CutBox {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 18
                                cut: cornerCard.modelData.key === "sharp" ? 0 : 5
                                strokeWidth: 1.5
                                stroke: cornerCard.selected ? Theme.accent : Theme.inkSoft
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                text: cornerCard.modelData.name
                                color: cornerCard.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.letterSpacing: 2
                            }
                        }

                        MouseArea {
                            id: cornerMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: page.windowLoaded
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (cornerCard.selected)
                                    return
                                page.setRounding(cornerCard.modelData.key === "sharp" ? 0 : page.lastRadius)
                            }
                        }
                    }
                }
            }

            Slider {
                width: parent.width
                visible: page.rounding > 0
                label: "Corner cut  " + page.rounding + "px"
                icon: String.fromCodePoint(0xF0607)
                tint: Theme.accent
                value: (page.rounding - 1) / 19

                onSliding: function(v) {
                    var next = 1 + Math.round(v * 19)
                    if (next !== page.rounding)
                        page.setRounding(next)
                }

                onSettled: function(v) {
                    page.setRounding(1 + Math.round(v * 19))
                }
            }

            Divider {}

            // ---------------- Shadow ----------------
            SectionHead {
                text: "SHADOW"
                hint: "costs a little GPU time; off is the lightest"
            }

            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF0637)
                label: "Window shadow"
                checked: page.shadow
                available: page.windowLoaded

                onToggled: {
                    page.shadow = !page.shadow
                    page.sendWindow("shadow", page.shadow ? "on" : "off")
                }
            }

            Slider {
                width: parent.width
                visible: page.shadow
                label: "Shadow size  " + page.shadowSize + "px"
                icon: String.fromCodePoint(0xF1854)
                tint: Theme.accent
                value: (page.shadowSize - 2) / 38

                onSliding: function(v) {
                    var next = 2 + Math.round(v * 38)
                    if (next !== page.shadowSize) {
                        page.shadowSize = next
                        page.sendWindow("shadow_size", next)
                    }
                }

                onSettled: function(v) {
                    page.shadowSize = 2 + Math.round(v * 38)
                    page.sendWindow("shadow_size", page.shadowSize)
                }
            }

            Divider {}

            // ---------------- Border ----------------
            SectionHead { text: "BORDER" }

            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF00C9)
                label: "Window border"
                checked: page.border
                available: page.windowLoaded

                onToggled: {
                    page.border = !page.border
                    page.sendWindow("border", page.border ? "on" : "off")
                }
            }

            Slider {
                width: parent.width
                visible: page.border
                label: "Border width  " + page.borderSize + "px"
                icon: String.fromCodePoint(0xF08A1)
                tint: Theme.accent
                value: (page.borderSize - 1) / 5

                onSliding: function(v) {
                    var next = 1 + Math.round(v * 5)
                    if (next !== page.borderSize) {
                        page.borderSize = next
                        page.sendWindow("border_size", next)
                    }
                }

                onSettled: function(v) {
                    page.borderSize = 1 + Math.round(v * 5)
                    page.sendWindow("border_size", page.borderSize)
                }
            }

            // Border colour: follow the accent, or any #rrggbb
            Item {
                width: parent.width
                height: 30
                visible: page.border

                Text {
                    id: borderColourIcon

                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF0266)
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 14
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: borderColourIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Border colour"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        readonly property bool selected: page.borderColor === "accent"

                        width: accentLabel.implicitWidth + 34
                        height: 26
                        color: selected ? Theme.tint(Theme.accent, 0.16) : "transparent"
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (accentMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Row {
                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10
                                height: 10
                                color: Theme.accent
                            }

                            Text {
                                id: accentLabel

                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                text: "ACCENT"
                                color: parent.parent.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                            }
                        }

                        MouseArea {
                            id: accentMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                page.borderColor = "accent"
                                page.sendWindow("border_color", "accent")
                            }
                        }
                    }

                    Rectangle {
                        id: borderHexField

                        readonly property bool selected: page.borderColor !== "accent"
                        property bool invalid: false

                        width: 132
                        height: 26
                        color: Theme.groove
                        border.width: 1
                        border.color: invalid
                            ? Theme.alert
                            : (borderHexInput.activeFocus || selected ? Theme.accent : Theme.line)

                        Rectangle {
                            id: borderSwatch

                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            color: page.borderColor === "accent" ? Theme.inkMute : page.borderColor
                        }

                        TextInput {
                            id: borderHexInput

                            anchors.left: borderSwatch.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.borderColor === "accent" ? "" : page.borderColor
                            maximumLength: 7
                            color: Theme.ink
                            selectionColor: Theme.tint(Theme.accent, 0.4)
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            selectByMouse: true

                            Text {
                                textFormat: Text.PlainText
                                visible: borderHexInput.text === "" && !borderHexInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: "#rrggbb"
                                color: Theme.inkMute
                                font: borderHexInput.font
                            }

                            onTextEdited: borderHexField.invalid = false

                            onAccepted: {
                                var value = text.trim()
                                if (value.charAt(0) !== "#")
                                    value = "#" + value
                                if (/^#[0-9a-fA-F]{6}$/.test(value)) {
                                    page.borderColor = value.toLowerCase()
                                    page.sendWindow("border_color", page.borderColor)
                                    focus = false
                                } else {
                                    borderHexField.invalid = true
                                }
                            }
                        }
                    }
                }
            }

            Note {
                visible: page.windowStatus !== ""
                text: page.windowStatus
                color: Theme.inkSoft
            }
        }
    }
}
