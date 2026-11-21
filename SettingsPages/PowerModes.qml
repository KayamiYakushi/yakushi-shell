import QtQuick
import "../"

// Settings -> System: the CPU power mode, standing in the top right corner.
// Three tiles side by side, always in the same order (power saving,
// balanced, performance), only an icon each; the chosen one hangs down the
// whole corner as a column with its name written down it (and its mark at
// the foot). Pointing at another tile lets it hang down faintly: a preview
// of the change, and its name. Every tile has the same cut foot as the
// column it can become.
Item {
    id: modes

    property string mode: ""            // what the computer is in now
    property var available: []          // modes it can tell apart, in order
    property bool canSet: false
    property string pending: ""         // asked for, not answered yet
    property bool failed: false         // the last change was refused

    signal chose(string mode)

    readonly property var all: [
        { key: "saver", title: "POWER SAVING", glyph: 0xF032A, mark: "省" },        // leaf
        { key: "balanced", title: "BALANCED", glyph: 0xF0680, mark: "均" },          // yin-yang
        { key: "performance", title: "PERFORMANCE", glyph: 0xF140B, mark: "速" }     // lightning
    ]
    readonly property var shown: all.filter(function(m) { return available.indexOf(m.key) >= 0 })
    readonly property string lit: pending !== "" ? pending : mode

    readonly property int tile: 30
    readonly property int gap: 4

    visible: shown.length > 1
    width: shown.length * tile + Math.max(0, shown.length - 1) * gap

    Repeater {
        model: modes.shown

        delegate: Item {
            id: one

            required property var modelData
            required property int index

            readonly property bool on: modelData.key === modes.lit
            readonly property bool pointed: mouse.containsMouse && modes.canSet && modes.pending === ""
            readonly property bool preview: pointed && !on
            readonly property bool refused: on && modes.failed
            // the foot of the column: room for the mark under the name?
            readonly property bool roomy: modes.height >= 170

            x: index * (modes.tile + modes.gap)
            width: modes.tile
            height: modes.height

            property real reach: on || preview ? modes.height : modes.tile

            Behavior on reach {
                NumberAnimation { duration: Theme.tMid; easing.type: Easing.OutCubic }
            }

            CutBox {
                width: parent.width
                height: one.reach
                cut: Theme.cutSmall
                cutTopLeft: false
                cutTopRight: false
                fill: one.on ? Theme.tint(Theme.accent, 0.14)
                    : one.preview ? Theme.tint(Theme.accent, 0.05) : Theme.tint(Theme.ink, 0.03)
                stroke: one.refused ? Theme.alert
                      : one.on ? Theme.tint(Theme.accent, 0.6)
                      : one.preview ? Theme.tint(Theme.accent, 0.35) : Theme.tint(Theme.ink, 0.14)
            }

            // the chosen one's accent bar
            Rectangle {
                visible: one.on
                width: parent.width
                height: 2
                color: one.refused ? Theme.alert : Theme.accent
            }

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                y: (modes.tile - height) / 2
                text: String.fromCodePoint(one.modelData.glyph)
                color: one.on || one.pointed ? Theme.accent : Theme.inkSoft
                font.family: Theme.glyphs
                font.pixelSize: 15
            }

            // the name, written down the column; it shrinks to fit a short page
            Item {
                id: lane

                y: modes.tile + 8
                width: parent.width
                height: (one.roomy ? mark.y - 8 : modes.height - Theme.cutSmall - 6) - y

                Text {
                    id: name

                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    rotation: 90
                    scale: Math.min(1, lane.height / Math.max(1, implicitWidth))
                    opacity: one.on || one.preview ? 1 : 0
                    text: one.refused ? "FAILED" : one.modelData.title
                    color: one.refused ? Theme.alert : one.on ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 3

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.tFast }
                    }
                }
            }

            Text {
                id: mark

                textFormat: Text.PlainText
                visible: one.roomy
                opacity: one.on ? 1 : 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: modes.height - Theme.cutSmall - 4 - height
                text: one.modelData.mark
                color: one.refused ? Theme.alert : Theme.accent
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 13

                Behavior on opacity {
                    NumberAnimation { duration: Theme.tFast }
                }
            }

            // only the tile answers the pointer: the column under it is the
            // preview, not a bigger button
            MouseArea {
                id: mouse

                width: parent.width
                height: modes.tile
                hoverEnabled: true
                enabled: modes.canSet
                cursorShape: one.on || modes.pending !== "" ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                    if (!one.on && modes.pending === "")
                        modes.chose(one.modelData.key)
                }
            }
        }
    }
}
