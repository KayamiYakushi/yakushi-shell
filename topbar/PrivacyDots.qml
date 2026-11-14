import QtQuick
import "../"

// Two small marks at the end of the island: red while the screen is being
// recorded or shared, green while a program listens to the microphone
// (PrivacyState.qml). With neither there is nothing here, not even a gap.
// Hover a mark to read what it means and who it is. Nothing animates while
// they are lit: they fade in and then stand still.
Item {
    id: dots

    required property var privacy
    required property int barHeight

    readonly property bool screenOn: privacy !== null && privacy.screen
    readonly property bool micOn: privacy !== null && privacy.mic
    readonly property int lead: 20        // air between the last module and the marks

    implicitWidth: row.implicitWidth > 0 ? lead + row.implicitWidth : 0
    implicitHeight: barHeight
    height: barHeight

    // One mark: a small diamond (the shell's diagonal) with a faint halo of
    // its own colour; the words slide out on hover.
    component Mark: Item {
        id: mark

        property bool lit: false
        property color tone: Theme.ink
        property string label: ""
        property string detail: ""
        readonly property bool hovered: hover.hovered

        implicitWidth: 13 + words.width
        height: dots.barHeight
        opacity: lit ? 1 : 0
        visible: opacity > 0
        scale: lit ? 1 : 0.4
        transformOrigin: Item.Left

        Behavior on opacity {
            NumberAnimation { duration: Theme.tSlow; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: Theme.tSlow; easing.type: Easing.OutCubic }
        }

        Item {
            width: 13
            height: 13
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 9
                height: 9
                rotation: 45
                antialiasing: true
                color: Theme.tint(mark.tone, mark.hovered ? 0.30 : 0.16)

                Behavior on color {
                    ColorAnimation { duration: Theme.tFast }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 5
                height: 5
                rotation: 45
                antialiasing: true
                color: mark.tone
            }
        }

        Item {
            id: words

            x: 13
            width: mark.hovered ? wordRow.implicitWidth + 7 : 0
            height: parent.height
            visible: width > 0.5
            clip: true

            Behavior on width {
                NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
            }

            Row {
                id: wordRow

                x: 7
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: mark.label
                    color: mark.tone
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 1
                }

                Text {
                    textFormat: Text.PlainText
                    visible: mark.detail !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 170)
                    text: mark.detail
                    elide: Text.ElideRight
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
            }
        }

        HoverHandler {
            id: hover
        }
    }

    Row {
        id: row

        x: dots.lead
        height: dots.barHeight
        spacing: 9

        Mark {
            lit: dots.screenOn
            tone: Theme.alert
            label: "SCREEN"
            detail: dots.privacy ? dots.privacy.screenWhat : ""
        }

        Mark {
            lit: dots.micOn
            tone: Theme.good
            label: "MIC"
            detail: dots.privacy ? dots.privacy.micApps : ""
        }
    }
}
