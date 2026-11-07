import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland

// The little volume pill that drops in under the bar when you press the
// volume keys. Click-through; the shell loads it on "ipc call volumeOsd
// show" (yakushi volume ...) and frees it shortly after the last change.
PanelWindow {
    id: osd

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

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var out: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property real level: out ? out.volume : 0
    readonly property bool silent: out ? out.muted : false
    property bool up: false

    function poke() {
        up = true
        fade.restart()
    }

    Timer {
        id: fade
        interval: 1200
        onTriggered: osd.up = false
    }

    Connections {
        target: osd.out
        function onVolumeChanged() { osd.poke() }
        function onMutedChanged() { osd.poke() }
    }

    readonly property color tone: silent ? Theme.alert : Theme.accent

    Rectangle {
        id: pill

        x: (osd.width - width) / 2
        y: osd.up ? 46 : 34
        width: 300
        height: 46
        radius: height / 2
        color: "#eb050505"
        border.width: 1
        border.color: "#12ffffff"
        opacity: osd.up ? 1 : 0
        scale: osd.up ? 1 : 0.94

        Behavior on y { NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic } }

        // speaker
        Rectangle {
            id: dot

            x: 8
            y: (pill.height - height) / 2
            width: 32
            height: 32
            radius: 16
            color: Theme.tint(osd.tone, 0.18)

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                color: osd.tone
                font.family: Theme.glyphs
                font.pixelSize: 16
                text: String.fromCodePoint(osd.silent || osd.level < 0.005 ? 0xF0581
                    : osd.level < 0.34 ? 0xF057F
                    : osd.level < 0.67 ? 0xF0580 : 0xF057E)
            }
        }

        // level bar
        Rectangle {
            x: dot.x + dot.width + 14
            y: (pill.height - height) / 2
            width: readout.x - x - 12
            height: 6
            radius: 3
            color: "#1affffff"

            Rectangle {
                height: parent.height
                radius: 3
                width: osd.silent ? 0 : parent.width * Math.min(1, osd.level)
                color: Theme.accent

                Behavior on width { NumberAnimation { duration: 100 } }
            }
        }

        Text {
            id: readout

            textFormat: Text.PlainText
            x: pill.width - width - 16
            y: (pill.height - height) / 2
            width: 42
            horizontalAlignment: Text.AlignRight
            text: osd.silent ? "Muted" : Math.round(osd.level * 100) + "%"
            color: osd.silent ? Theme.alert : Theme.ink
            font.family: Theme.mono
            font.pixelSize: 12
            font.bold: true
        }
    }
}
