import QtQuick
import QtQuick.Shapes

// A box with 45-degree cut corners: the shell's one outline shape (see
// Theme.cut). Choose which corners are cut; the stroke stays inside the box.
// With only the top-right and bottom-left corners cut and `cut` as large as
// the height, it is a slanted bar (a parallelogram), as in SlantBar.
Shape {
    id: box

    property color fill: "transparent"
    property color stroke: "transparent"
    property real strokeWidth: 1
    property real cut: Theme.cut

    property bool cutTopLeft: true
    property bool cutTopRight: true
    property bool cutBottomRight: true
    property bool cutBottomLeft: true

    // two cuts on one edge share it; a lone cut may take the whole edge
    readonly property real c: Math.max(0, Math.min(cut,
        (cutTopLeft && cutTopRight) || (cutBottomLeft && cutBottomRight) ? width / 2 : width,
        (cutTopLeft && cutBottomLeft) || (cutTopRight && cutBottomRight) ? height / 2 : height))
    readonly property real o: stroke.a > 0 ? strokeWidth / 2 : 0
    readonly property real tl: cutTopLeft ? c : 0
    readonly property real tr: cutTopRight ? c : 0
    readonly property real br: cutBottomRight ? c : 0
    readonly property real bl: cutBottomLeft ? c : 0

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: box.fill
        strokeColor: box.stroke
        strokeWidth: box.stroke.a > 0 ? box.strokeWidth : 0
        joinStyle: ShapePath.MiterJoin

        startX: box.o + box.tl
        startY: box.o

        PathLine { x: box.width - box.o - box.tr; y: box.o }
        PathLine { x: box.width - box.o; y: box.o + box.tr }
        PathLine { x: box.width - box.o; y: box.height - box.o - box.br }
        PathLine { x: box.width - box.o - box.br; y: box.height - box.o }
        PathLine { x: box.o + box.bl; y: box.height - box.o }
        PathLine { x: box.o; y: box.height - box.o - box.bl }
        PathLine { x: box.o; y: box.o + box.tl }
        PathLine { x: box.o + box.tl; y: box.o }
    }
}
