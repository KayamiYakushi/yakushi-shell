import QtQuick

// A level / progress bar in the shell's slanted style: the track and the
// filled part are parallelograms leaning along the same diagonal as every cut
// corner (top-right and bottom-left cut).
//
//   value       0 .. 1
//   trackColor  the empty part
//   fillColor   the filled part
Item {
    id: bar

    property real value: 0
    property color trackColor: Theme.tint(Theme.ink, 0.14)
    property color fillColor: Theme.accent
    property real slant: height

    CutBox {
        anchors.fill: parent
        fill: bar.trackColor
        cut: bar.slant
        cutTopLeft: false
        cutBottomRight: false
    }

    CutBox {
        width: bar.width * Math.max(0, Math.min(1, bar.value))
        height: bar.height
        visible: width > 0.5
        fill: bar.fillColor
        cut: bar.slant
        cutTopLeft: false
        cutBottomRight: false
    }
}
