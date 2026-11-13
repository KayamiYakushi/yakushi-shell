import QtQuick
import Quickshell
import Quickshell.Wayland

// The little pill that drops in under the bar: an icon, a level bar and a
// number. The volume keys (VolumeOsd), the brightness keys and the low
// battery warning (LevelOsd) all show it. Click-through; the shell loads
// it when it is needed and frees it shortly after.
PanelWindow {
    id: osd

    property string glyph: ""
    property real level: 0                    // 0..1
    property string text: ""
    property color tone: Theme.accent
    property color textColor: Theme.ink
    property int hold: 1200                   // how long it stays, ms
    property bool up: false

    function poke() {
        up = true
        fade.restart()
    }

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 110
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yakushi-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Timer {
        id: fade
        interval: osd.hold
        onTriggered: osd.up = false
    }

    Item {
        id: pill

        x: (osd.width - width) / 2
        y: osd.up ? 46 : 34
        width: 300
        height: 46
        opacity: osd.up ? 1 : 0
        scale: osd.up ? 1 : 0.94

        Behavior on y { NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }

        CutBox {
            anchors.fill: parent
            fill: "#eb050505"
            stroke: "#12ffffff"
        }

        // speaker: inset evenly from the pill, its cuts parallel to the
        // pill's (a 45-degree cut moved in by `inset` shrinks by
        // inset * (2 - sqrt 2)), so it never reaches past the outline
        Item {
            id: dot

            readonly property real inset: 6

            x: inset
            y: inset
            width: pill.height - 2 * inset
            height: pill.height - 2 * inset

            CutBox {
                anchors.fill: parent
                fill: Theme.tint(osd.tone, 0.18)
                cut: Theme.cut - dot.inset * (2 - Math.SQRT2)
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                color: osd.tone
                font.family: Theme.glyphs
                font.pixelSize: 16
                text: osd.glyph
            }
        }

        // level bar
        SlantBar {
            x: dot.x + dot.width + 14
            y: (pill.height - height) / 2
            width: readout.x - x - 12
            height: 8
            trackColor: "#1affffff"
            value: Math.max(0, Math.min(1, osd.level))

            Behavior on value { NumberAnimation { duration: 100 } }
        }

        Text {
            id: readout

            textFormat: Text.PlainText
            x: pill.width - width - 16
            y: (pill.height - height) / 2
            width: 42
            horizontalAlignment: Text.AlignRight
            text: osd.text
            color: osd.textColor
            font.family: Theme.mono
            font.pixelSize: 12
            font.bold: true
        }
    }
}
