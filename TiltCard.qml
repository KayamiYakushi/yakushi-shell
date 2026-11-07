import QtQuick

// The card of Settings and the screen-share picker, in the shell's shape:
// top-right and bottom-left corners cut (Theme.cutLarge), with an accent
// notch on each cut.
//
// Opening: at first there are only the two notches, crossed in the middle.
// They slide apart along the top-right / bottom-left diagonal, the card opens
// between them, and they land on its cut corners. (A card with those two
// corners cut is exactly a band across that diagonal, so the opening band
// and the finished card are one shape.) Closing runs the same way back.
// While the pointer is over it, it leans a few degrees toward the pointer.
//
//   shown        visible or not
//   leanDegrees  how far it leans toward the pointer
//   still        no leaning (while it is being resized)
//   duration     how long opening and closing take, in ms (0 = at once)
Item {
    id: card

    default property alias content: inside.data
    property bool shown: false
    property real leanDegrees: 5
    property bool still: false
    property real cut: Theme.cutLarge
    property int duration: Theme.tSlow + 100     // opening / closing, ms (0 = none)

    // pointer position over the card, centre = (0, 0), edges = ±0.5
    property point pointer: Qt.point(0, 0)

    // 0 = just the two notches, 1 = the whole card
    property real reveal: shown ? 1 : 0
    readonly property bool opening: reveal < 0.999

    Behavior on reveal {
        NumberAnimation { duration: card.duration; easing.type: Easing.OutCubic }
    }

    property real tiltX: shown && !still ? -pointer.y * leanDegrees : 0
    property real tiltY: shown && !still ? pointer.x * leanDegrees : 0

    Behavior on tiltX { NumberAnimation { duration: Theme.tSlow; easing.type: Easing.OutCubic } }
    Behavior on tiltY { NumberAnimation { duration: Theme.tSlow; easing.type: Easing.OutCubic } }

    // on until the notches have met again after closing
    opacity: shown || reveal > 0.002 ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: Math.min(Theme.tFast, card.duration) } }

    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // Distance from the centre to a cut edge, along the diagonal, and how much
    // of it is open now. `span` is longer than any line across the card.
    readonly property real fullHalf: Math.max(0, (width + height - 2 * cut) / (2 * Math.SQRT2))
    readonly property real half: reveal * fullHalf
    readonly property real span: (width + height) / Math.SQRT2 + 16

    transform: [
        Rotation { origin { x: card.cx; y: card.cy } axis { x: 1; y: 0; z: 0 } angle: card.tiltX },
        Rotation { origin { x: card.cx; y: card.cy } axis { x: 0; y: 1; z: 0 } angle: card.tiltY }
    ]

    HoverHandler {
        onPointChanged: card.pointer = Qt.point(point.position.x / Math.max(1, card.width) - 0.5,
                                                point.position.y / Math.max(1, card.height) - 0.5)
        onHoveredChanged: if (!hovered) card.pointer = Qt.point(0, 0)
    }

    // Accent stroke along a cut corner, just outside it; while opening it
    // rides the edge of the band.
    component Notch: Rectangle {
        property real side: 1        // 1 = top-right, -1 = bottom-left

        readonly property real along: card.half + 4
        readonly property real across: card.reveal * (card.width - card.height) / (2 * Math.SQRT2)

        width: card.cut * Math.SQRT2 + 10
        height: 2
        x: card.cx + side * (along + across) / Math.SQRT2 - width / 2
        y: card.cy + side * (across - along) / Math.SQRT2 - height / 2
        rotation: 45
        antialiasing: true
        color: Theme.accent
    }

    // The band: shows what lies within `half` of the centre, measured along
    // the diagonal. It is turned only while opening or closing, so the open
    // card is drawn without any rotation (crisp text).
    Item {
        id: band

        width: card.span
        height: card.opening ? 2 * card.half : card.span
        x: (card.width - width) / 2
        y: (card.height - height) / 2
        rotation: card.opening ? 45 : 0
        clip: card.opening

        Item {
            id: body

            width: card.width
            height: card.height
            x: (band.width - width) / 2
            y: (band.height - height) / 2
            rotation: card.opening ? -45 : 0

            CutBox {
                anchors.fill: parent
                fill: Theme.backdrop
                stroke: Theme.tint(Theme.ink, 0.12)
                cut: card.cut
                cutTopLeft: false
                cutBottomRight: false
            }

            Item {
                id: inside

                anchors.fill: parent
            }
        }
    }

    Notch { side: 1 }
    Notch { side: -1 }
}
