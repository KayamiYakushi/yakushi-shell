import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import "../"

// What one screen shows while locked: the wallpaper, dimmed and softly
// blurred; the clock and date at the top; your picture, name and the
// password field in the middle; the song that is playing at the bottom.
//
// Simple and calm on purpose: nothing to click but the field, details only
// when they matter (a message appears only after a try).
Item {
    id: surface

    required property LockContext context
    property string wallpaper: ""        // absolute path, or "" for plain black
    property bool shown: false           // content faded in
    property bool clock24: false

    readonly property string user: Quickshell.env("USER") || ""

    // ------------------------------------------------------------------
    // Background
    // ------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Image {
        id: wall

        anchors.fill: parent
        visible: false                   // drawn through the blur below
        source: surface.wallpaper === "" ? ""
            : "file://" + surface.wallpaper.split("/").map(encodeURIComponent).join("/")
        sourceSize.width: surface.width
        sourceSize.height: surface.height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wall
        opacity: wall.status === Image.Ready ? 1 : 0
        blurEnabled: true
        blur: 0.55
        blurMax: 40
        autoPaddingEnabled: false

        Behavior on opacity {
            NumberAnimation { duration: Theme.tSlow }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.55
    }

    // ------------------------------------------------------------------
    // Content
    // ------------------------------------------------------------------
    Item {
        id: content

        anchors.fill: parent
        opacity: surface.shown ? 1 : 0
        scale: surface.shown ? 1 : 0.985

        Behavior on opacity {
            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
        }

        // clicking anywhere gives the field the keys back
        MouseArea {
            anchors.fill: parent
            onPressed: input.forceActiveFocus()
        }

        // ---- clock and date
        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(surface.height * 0.14)
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: Qt.formatTime(clock.date, surface.clock24 ? "HH:mm" : "h:mm")
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 96
                font.weight: Font.Light
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: Qt.locale().toString(clock.date, "dddd  ·  d MMMM")
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 16
                font.letterSpacing: 1
            }
        }

        // ---- picture, name, password
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(surface.height * 0.06)
            spacing: 0

            // picture in the cut-corner outline
            Item {
                id: picture

                anchors.horizontalCenter: parent.horizontalCenter
                width: 104
                height: 104

                readonly property bool has: photo.status === Image.Ready

                Image {
                    id: photo

                    anchors.fill: parent
                    visible: false
                    source: "file://" + Config.profilePicture.split("/").map(encodeURIComponent).join("/")
                    sourceSize.width: 208
                    sourceSize.height: 208
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                CutBox {
                    id: photoMask

                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    fill: "white"
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: picture.has
                    source: photo
                    maskEnabled: true
                    maskSource: photoMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                // no picture: a quiet initial
                CutBox {
                    anchors.fill: parent
                    visible: !picture.has
                    fill: Theme.tint(Theme.card, 0.85)
                }

                Text {
                    anchors.centerIn: parent
                    visible: !picture.has
                    textFormat: Text.PlainText
                    text: surface.user.charAt(0).toUpperCase()
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 40
                }

                CutBox {
                    anchors.fill: parent
                    stroke: Theme.accent
                    strokeWidth: 2
                }
            }

            Item { width: 1; height: 18 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: surface.user
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 16
                font.letterSpacing: 1
            }

            Item { width: 1; height: 26 }

            // the field
            Item {
                id: field

                anchors.horizontalCenter: parent.horizontalCenter
                width: 320
                height: 48

                property real shake: 0

                transform: Translate { x: field.shake }

                SequentialAnimation {
                    id: shakeAnim

                    NumberAnimation { target: field; property: "shake"; to: -10; duration: 45 }
                    NumberAnimation { target: field; property: "shake"; to: 9; duration: 70 }
                    NumberAnimation { target: field; property: "shake"; to: -6; duration: 60 }
                    NumberAnimation { target: field; property: "shake"; to: 3; duration: 50 }
                    NumberAnimation { target: field; property: "shake"; to: 0; duration: 40 }
                }

                Connections {
                    target: surface.context

                    function onFailuresChanged() {
                        shakeAnim.restart()
                    }
                }

                CutBox {
                    anchors.fill: parent
                    fill: Qt.rgba(0, 0, 0, 0.5)
                    stroke: surface.context.failed ? Theme.alert
                        : input.activeFocus ? Theme.accent
                        : Theme.lineHot
                    strokeWidth: 1.5

                    Behavior on stroke {
                        ColorAnimation { duration: Theme.tFast }
                    }
                }

                // The real input: invisible, it only holds the keys. What
                // it holds is shown as slanted marks, never as text.
                TextInput {
                    id: input

                    anchors.fill: parent
                    opacity: 0
                    focus: true
                    echoMode: TextInput.Password
                    readOnly: surface.context.busy
                    maximumLength: 512
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
                    persistentSelection: false
                    selectByMouse: false

                    text: surface.context.text
                    onTextChanged: {
                        if (text !== surface.context.text)
                            surface.context.text = text
                    }

                    Keys.onReturnPressed: surface.context.submit()
                    Keys.onEnterPressed: surface.context.submit()
                    Keys.onEscapePressed: surface.context.text = ""

                    // no copy, cut or paste out of (or into) the field
                    Keys.onPressed: function(event) {
                        surface.context.keyPressed()
                        if (event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut)
                                || event.matches(StandardKey.Paste) || event.matches(StandardKey.SelectAll))
                            event.accepted = true
                    }
                }

                Connections {
                    target: surface.context

                    function onTextChanged() {
                        if (input.text !== surface.context.text)
                            input.text = surface.context.text
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: surface.context.text === "" && !surface.context.busy
                    textFormat: Text.PlainText
                    text: "Password"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 14
                    font.letterSpacing: 1
                }

                // Caps Lock on: a quiet tag at the field's right end
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    opacity: surface.context.capsLock && !surface.context.busy ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.tFast }
                    }

                    CutBox {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 12
                        fill: Theme.accent
                        cut: 5
                        cutTopLeft: false
                        cutBottomRight: false
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "CAPS"
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 12
                        font.letterSpacing: 2
                    }
                }

                // one slanted mark per character (at most what fits)
                // (fewer, a little left, while the CAPS tag is shown)
                Row {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: surface.context.capsLock ? -32 : 0
                    spacing: 5
                    visible: !surface.context.busy

                    Repeater {
                        model: Math.min(surface.context.text.length, surface.context.capsLock ? 18 : 24)

                        CutBox {
                            width: 7
                            height: 14
                            fill: Theme.ink
                            cut: 7
                            cutTopLeft: false
                            cutBottomRight: false
                        }
                    }
                }

                // checking: one mark sweeping along the field
                Item {
                    anchors.fill: parent
                    anchors.margins: 14
                    visible: surface.context.busy
                    clip: true

                    CutBox {
                        id: sweep

                        width: 36
                        height: 6
                        anchors.verticalCenter: parent.verticalCenter
                        fill: Theme.accent
                        cut: 6
                        cutTopLeft: false
                        cutBottomRight: false

                        NumberAnimation on x {
                            running: surface.context.busy
                            loops: Animation.Infinite
                            from: -sweep.width
                            to: field.width - 28
                            duration: 900
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            Item { width: 1; height: 14 }

            // the message line keeps its height, so nothing jumps
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 420
                height: 20
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: surface.context.message
                color: surface.context.failed ? Theme.alert : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 13
            }
        }

        // ---- the song that is playing (nothing when none plays)
        Text {
            id: song

            readonly property var player: {
                var list = Mpris.players.values
                for (var i = 0; i < list.length; i++)
                    if (list[i].isPlaying)
                        return list[i]
                return null
            }

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 56
            width: Math.min(parent.width - 64, 640)
            horizontalAlignment: Text.AlignHCenter
            visible: player !== null && text !== ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: {
                if (!player)
                    return ""
                var title = player.trackTitle || ""
                var artist = player.trackArtist || ""
                if (title === "")
                    return ""
                return String.fromCodePoint(0xF075A) + "  " + title + (artist !== "" ? "  —  " + artist : "")
            }
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 14
        }
    }
}
