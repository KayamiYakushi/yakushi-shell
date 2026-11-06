import QtQuick
import "../"

// One bordered strip of options (Tasks, Programs); the chosen one is lit and
// underlined in the accent. `options` should stay constant (a new array
// rebuilds the buttons); put numbers that change in `counts`.
Rectangle {
    id: seg

    property var options: []           // [[key, label], ...]
    property var counts: ({})          // key -> number shown after the label
    property string current: ""

    signal chose(string key)

    width: segRow.width + 2
    height: 36
    color: "transparent"
    border.width: 1
    border.color: Theme.line

    Row {
        id: segRow

        x: 1
        y: 1

        Repeater {
            model: seg.options

            delegate: Rectangle {
                id: option

                required property var modelData
                required property int index
                readonly property bool on: seg.current === modelData[0]

                width: optionText.implicitWidth + 30
                height: seg.height - 2
                color: on ? Theme.tint(Theme.accent, 0.14) : optionMouse.containsMouse ? Theme.tint(Theme.ink, 0.05) : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.tFast }
                }

                Rectangle {
                    visible: option.index > 0
                    width: 1
                    height: parent.height
                    color: Theme.line
                }

                Rectangle {
                    visible: option.on
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 2
                    color: Theme.accent
                }

                Text {
                    id: optionText

                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: option.modelData[1] + (seg.counts[option.modelData[0]] !== undefined ? "  " + seg.counts[option.modelData[0]] : "")
                    color: option.on ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    font.bold: option.on
                }

                MouseArea {
                    id: optionMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.chose(option.modelData[0])
                }
            }
        }
    }
}
