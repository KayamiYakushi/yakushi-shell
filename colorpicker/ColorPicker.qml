import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "../"

// One screen of the colour picker. The screen as it was when the picker
// opened (launch.sh captured it) is drawn over it, so nothing moves while
// you aim; next to the pointer a lens in the shell's cut-corner shape
// shows the pixels around it, enlarged, the colour and its hex code.
//
//   click             copy the hex code (#RRGGBB) and close
//   Esc, right click  close, nothing copied
PanelWindow {
    id: win

    required property var modelData      // the ShellScreen
    property string shots: ""
    property string copied: ""

    signal picked(string hex)
    signal cancelled()

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "yakushi-colorpicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property string file: shots !== "" ? "file://" + shots + "/" + modelData.name + ".png" : ""
    property bool ready: false           // the captured screen is drawn
    property bool chosen: false          // the click that copied was on this screen
    readonly property bool done: copied !== ""

    // the pixel under the pointer
    property int px: -1
    property int py: -1
    property color here: "black"
    property string hex: ""

    // ---- the lens
    readonly property int span: 15       // pixels across, the middle one is the one you pick
    readonly property int zoom: 10       // each shown this many times larger
    readonly property int pad: 9
    readonly property int gap: 26        // between the pointer and the lens

    function two(v) {
        var s = v.toString(16).toUpperCase()
        return s.length < 2 ? "0" + s : s
    }

    function sample() {
        if (!ready || px < 0 || py < 0)
            return
        var col = Math.max(0, Math.min(Math.floor(frozen.width) - 1, px))
        var row = Math.max(0, Math.min(Math.floor(frozen.height) - 1, py))
        var d = frozen.getContext("2d").getImageData(col, row, 1, 1).data
        var r = d[0], g = d[1], b = d[2]
        hex = "#" + two(r) + two(g) + two(b)
        here = Qt.rgba(r / 255, g / 255, b / 255, 1)
    }

    // ---- the screen, held still
    Canvas {
        id: frozen

        // the screen's size from the start: the window gets its size from
        // the compositor a moment after it appears
        width: win.modelData.width
        height: win.modelData.height
        visible: !win.done              // copied: the real screen is back at once

        Component.onCompleted: {
            if (win.file !== "")
                loadImage(win.file)
        }
        onImageLoaded: requestPaint()
        onCanvasSizeChanged: requestPaint()

        onPaint: {
            if (!isImageLoaded(win.file) || canvasSize.width < 2 || canvasSize.height < 2)
                return
            var ctx = getContext("2d")
            ctx.drawImage(win.file, 0, 0, canvasSize.width, canvasSize.height)
            win.ready = true
            win.sample()
        }
    }

    // the picture never came: nothing to pick from
    Timer {
        interval: 3000
        running: !win.ready
        onTriggered: win.cancelled()
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: win.cancelled()
    }

    MouseArea {
        id: aim

        anchors.fill: parent
        enabled: !win.done
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        function follow(mouse) {
            win.px = Math.floor(mouse.x)
            win.py = Math.floor(mouse.y)
            win.sample()
        }

        onPositionChanged: mouse => follow(mouse)
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                win.cancelled()
                return
            }
            follow(mouse)
            if (win.ready && win.hex !== "") {
                win.chosen = true
                win.picked(win.hex)
            }
        }
    }

    // ---- the lens: beside the pointer, on whichever side has room
    Item {
        id: lens

        readonly property int inner: win.span * win.zoom

        visible: win.ready && win.hex !== "" && (win.done ? win.chosen : aim.containsMouse)
        width: inner + 2 * win.pad
        height: win.pad + inner + 14 + 30 + 12 + 12 + win.pad + 2
        x: win.px + win.gap + width <= win.width ? win.px + win.gap : win.px - win.gap - width
        y: win.py + win.gap + height <= win.height ? win.py + win.gap : win.py - win.gap - height

        CutBox {
            anchors.fill: parent
            fill: Theme.surface
            stroke: win.done ? Theme.accent : Theme.lineHot
        }

        // the pixels around the pointer, enlarged
        Item {
            id: glass

            x: win.pad
            y: win.pad
            width: lens.inner
            height: lens.inner
            clip: true

            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: frozen
                sourceRect: Qt.rect(win.px - Math.floor(win.span / 2), win.py - Math.floor(win.span / 2),
                                    win.span, win.span)
                textureSize: Qt.size(win.span, win.span)
                smooth: false
                // copied: the frozen screen is hidden, keep the last view
                live: !win.done
                recursive: false
            }

            // the pixel you pick: a light and a dark ring, readable on any colour
            Rectangle {
                x: Math.floor(win.span / 2) * win.zoom - 1
                y: x
                width: win.zoom + 2
                height: width
                color: "transparent"
                border.width: 1
                border.color: "#000000"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    color: "transparent"
                    border.width: 1
                    border.color: "#ffffff"
                }
            }

            // corners cut parallel to the lens's own (Theme.cut, inset by pad)
            Shape {
                id: corners

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                readonly property real c: Math.max(0, Theme.cut - win.pad * (2 - Math.SQRT2))

                ShapePath {
                    fillColor: Theme.surface
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill

                    // the square, then the cut shape inside it: only the four corners fill
                    startX: 0; startY: 0
                    PathLine { x: glass.width; y: 0 }
                    PathLine { x: glass.width; y: glass.height }
                    PathLine { x: 0; y: glass.height }
                    PathLine { x: 0; y: 0 }
                    PathMove { x: corners.c; y: 0 }
                    PathLine { x: glass.width - corners.c; y: 0 }
                    PathLine { x: glass.width; y: corners.c }
                    PathLine { x: glass.width; y: glass.height - corners.c }
                    PathLine { x: glass.width - corners.c; y: glass.height }
                    PathLine { x: corners.c; y: glass.height }
                    PathLine { x: 0; y: glass.height - corners.c }
                    PathLine { x: 0; y: corners.c }
                    PathLine { x: corners.c; y: 0 }
                }
            }
        }

        // the colour and its code
        Row {
            id: info

            x: win.pad
            y: glass.y + glass.height + 14
            spacing: 12

            CutBox {
                width: 30
                height: 30
                cut: Theme.cutSmall
                fill: win.here
                stroke: Theme.tint(Theme.ink, 0.25)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: win.hex
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 2
            }
        }

        Text {
            x: win.pad
            y: info.y + info.height + 12
            textFormat: Text.PlainText
            text: win.done ? "COPIED" : "CLICK  ·  COPY"
            color: win.done ? Theme.accent : Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 10
            font.bold: win.done
            font.letterSpacing: 2
        }
    }
}
