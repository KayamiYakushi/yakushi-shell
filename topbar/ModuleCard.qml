import QtQuick
import "../"

// The island's own settings for one module (right-click it): only what
// that module has, then putting other modules on the bar next to it and
// taking this one off. `key` "" is the island itself (right-click an empty
// part): only the modules to put on.
//
// It only asks; TopBar.qml saves (scripts/yakushi-topbarctl.py).
Item {
    id: card

    required property var config          // BarConfig
    property string key: ""

    signal setValue(string name, string value)
    signal addModule(string key)
    signal removeModule()
    signal run(var args)

    readonly property real wantedHeight: body.implicitHeight

    function glyph(code) {
        return String.fromCodePoint(code)
    }

    // the same names and icons as Settings -> Top Bar
    readonly property var info: ({
        "":         { name: "TOP BAR",     jp: "トップバー",       icon: glyph(0xF0493) },
        workspaces: { name: "WORKSPACES",  jp: "ワークスペース",   icon: glyph(0xF056E), short: "WORKSPACES" },
        ram:        { name: "RAM USAGE",   jp: "メモリ",           icon: glyph(0xF035B), short: "RAM" },
        cpu:        { name: "CPU USAGE",   jp: "プロセッサ",       icon: glyph(0xF0EE0), short: "CPU" },
        cpuTemp:    { name: "CPU TEMP",    jp: "温度",             icon: glyph(0xF050F), short: "CPU °C" },
        gpuTemp:    { name: "GPU TEMP",    jp: "温度",             icon: glyph(0xF08AE), short: "GPU °C" },
        media:      { name: "NOW PLAYING", jp: "再生中",           icon: glyph(0xF0387), short: "MUSIC" },
        tray:       { name: "TRAY",        jp: "トレイ",           icon: glyph(0xF003B), short: "TRAY" },
        volume:     { name: "VOLUME",      jp: "音量",             icon: glyph(0xF057E), short: "VOLUME" },
        network:    { name: "NETWORK",     jp: "ネットワーク",     icon: glyph(0xF0928), short: "WI-FI" },
        battery:    { name: "BATTERY",     jp: "バッテリー",       icon: glyph(0xF0079), short: "BATTERY" },
        date:       { name: "DATE",        jp: "日付",             icon: glyph(0xF00ED), short: "DATE" },
        time:       { name: "TIME",        jp: "時計",             icon: glyph(0xF0150), short: "TIME" },
        power:      { name: "POWER",       jp: "電源",             icon: glyph(0xF0425), short: "POWER" }
    })
    readonly property var here: info[key] || info[""]

    // modules switched off, in the bar's order: what can be put on
    readonly property var addable: {
        var list = []
        for (var i = 0; i < config.order.length; i++)
            if (config.modules[config.order[i]] === false && info[config.order[i]])
                list.push(config.order[i])
        return list
    }

    // ------------------------------------------------------------------
    // Small parts
    // ------------------------------------------------------------------
    component Label: Text {
        textFormat: Text.PlainText
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 1.5
    }

    component Rule: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.tint(Theme.ink, 0.08)
    }

    // a text button in a cut outline
    component Button: Item {
        id: button

        property string text: ""
        property string icon: ""
        property color hotColor: Theme.accent
        property bool on: false
        signal clicked()

        implicitWidth: buttonRow.implicitWidth + 18
        implicitHeight: 22

        CutBox {
            anchors.fill: parent
            cut: 5
            cutTopLeft: false
            cutBottomRight: false
            fill: button.on ? Theme.tint(button.hotColor, 0.16)
                : buttonMouse.containsMouse ? Theme.tint(button.hotColor, 0.10) : "transparent"
            stroke: button.on || buttonMouse.containsMouse ? button.hotColor : Theme.line
        }

        Row {
            id: buttonRow

            anchors.centerIn: parent
            spacing: 6

            Text {
                visible: button.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: button.icon
                color: buttonMouse.containsMouse || button.on ? button.hotColor : Theme.inkSoft
                font.family: Theme.glyphs
                font.pixelSize: 11
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: button.text
                color: buttonMouse.containsMouse || button.on ? Theme.ink : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.5
            }
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // a row: what it is on the left, the control on the right
    component Option: Item {
        property string text: ""
        default property alias control: optionControl.data

        width: parent ? parent.width : 0
        height: 30

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.text
        }

        Row {
            id: optionControl

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
        }
    }

    // ------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------
    Column {
        id: body

        width: parent.width
        spacing: 10

        // ---- what this is
        Item {
            width: parent.width
            height: 20

            Text {
                id: headIcon

                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: card.here.icon
                color: Theme.accent
                font.family: Theme.glyphs
                font.pixelSize: 13
            }

            Text {
                anchors.left: headIcon.right
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: card.here.name
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 3
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: card.here.jp
                color: Theme.inkMute
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 10
                font.letterSpacing: 2
            }
        }

        Rule {}

        // ---- this module's own settings
        Column {
            id: options

            width: parent.width
            visible: card.key === "time" || card.key === "media" || card.key === "volume"
                || card.key === "network" || card.key === "date"

            Option {
                visible: card.key === "time"
                text: "SECONDS"

                Switch {
                    checked: card.config.seconds
                    onToggled: card.setValue("seconds", checked ? "off" : "on")
                }
            }

            Option {
                visible: card.key === "time"
                text: "24-HOUR CLOCK"

                Switch {
                    checked: card.config.clock24
                    onToggled: card.setValue("clock24", checked ? "off" : "on")
                }
            }

            Option {
                visible: card.key === "media"
                text: "VISUALIZER"

                Repeater {
                    model: [["hover", "HOVER"], ["always", "ALWAYS"], ["off", "OFF"]]

                    delegate: Button {
                        required property var modelData

                        text: modelData[1]
                        on: card.config.visualizer === modelData[0]
                        onClicked: card.setValue("visualizer", modelData[0])
                    }
                }
            }

            Option {
                visible: card.key === "volume"
                text: "APP VOLUMES"

                Button {
                    text: "MIXER"
                    icon: String.fromCodePoint(0xF0C30)
                    onClicked: card.run(["pavucontrol"])
                }
            }

            Option {
                visible: card.key === "network"
                text: "CONNECTIONS"

                Button {
                    text: "SETTINGS"
                    icon: String.fromCodePoint(0xF0493)
                    onClicked: card.run([Paths.shell + "/bin/yakushi", "settings", "network"])
                }
            }

            Option {
                visible: card.key === "date"
                text: "CALENDAR"

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ON HOVER"
                    color: Theme.inkMute
                    font.bold: false
                }
            }
        }

        Rule {
            visible: options.visible
        }

        // ---- put another module on the bar, right after this one
        Label {
            text: card.key === "" ? "PUT ON THE BAR" : "ADD NEXT TO IT"
        }

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: card.addable

                delegate: Button {
                    required property string modelData

                    icon: card.info[modelData].icon
                    text: card.info[modelData].short
                    onClicked: card.addModule(modelData)
                }
            }

            Text {
                visible: card.addable.length === 0
                textFormat: Text.PlainText
                text: "Every module is on the bar."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }

        Rule {}

        // ---- take it off, or everything else
        Item {
            width: parent.width
            height: 22

            Button {
                visible: card.key !== ""
                text: "REMOVE"
                icon: String.fromCodePoint(0xF0374)
                hotColor: Theme.alert
                onClicked: card.removeModule()
            }

            Button {
                anchors.right: parent.right
                text: "ALL SETTINGS"
                icon: String.fromCodePoint(0xF0493)
                onClicked: card.run([Paths.shell + "/bin/yakushi", "settings", "topbar"])
            }
        }
    }
}
