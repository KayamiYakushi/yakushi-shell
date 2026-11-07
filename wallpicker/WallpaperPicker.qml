import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import "../"

// The wallpaper picker (SUPER + W): one card in the Settings shape, opening
// from its notches along the diagonal like Settings and the launcher.
//
// Inside, a strip of tiles that grow toward the middle like a dock; the one
// in the middle opens up to its real 16:9 shape. Tiles are cut on the same
// diagonal as the card. It opens on the wallpaper you have now.
//
//   Left / Right, wheel    move one wallpaper
//   Enter, Space, click    set it (the card closes)
//   Esc, W, click outside  close
//
// Layout: `pos` is the (fractional) index in the middle of the strip. Every
// tile's size and place is a function of its distance from `pos`, stacked
// edge to edge, so nothing overlaps or jitters while the strip moves.
PanelWindow {
    id: picker

    // Folders and look, worked out by index.py (from the config) and handed
    // over by launch.sh.
    readonly property var cfg: {
        try {
            return JSON.parse(Quickshell.env("YAKUSHI_WALLPAPER") || "{}")
        } catch (e) {
            return {}
        }
    }
    readonly property string here: Paths.shell + "/wallpicker"
    readonly property string indexDir: cfg.index || ""
    readonly property string thumbsDir: cfg.thumbs || ""
    readonly property string current: cfg.current || ""
    readonly property int visibleCount: cfg.visibleCount || 10

    property bool showing: false

    signal dismissed()      // fully closed (after the animation)

    // ---- look
    readonly property real middleScale: 0.86     // height of the middle tile
    readonly property real edgeScale: 0.34       // height at the strip's ends
    readonly property real wideAspect: 16 / 9    // shape of the middle tile
    readonly property int gap: 12
    readonly property int pad: 28
    readonly property real speed: 5000           // px / s while moving

    // Opening / closing time: the same as the launcher's
    // (Settings -> Appearance -> Launcher; 0 = none)
    readonly property int animation: {
        var ms = Config.launcher.animationMs
        return typeof ms === "number" ? Math.max(0, Math.min(1000, Math.round(ms))) : 480
    }

    function focusedScreen() {
        var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        var list = Quickshell.screens
        for (var i = 0; i < list.length; i++)
            if (list[i].name === name)
                return list[i]
        return list.length > 0 ? list[0] : null
    }

    screen: focusedScreen()
    Component.onCompleted: {
        screen = focusedScreen()
        // thumbnails are made in the background; missing ones retry below
        Quickshell.execDetached(["sh", here + "/thumbs.sh", indexDir, thumbsDir, String(cfg.thumbJobs || 4)])
        openTimer.start()
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yakushi-wallpaper"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // the accent and glass from Settings
    ThemeState {}

    // open on the next frame, so the opening is animated from the notches
    Timer {
        id: openTimer
        interval: 16
        onTriggered: {
            picker.showing = true
            strip.forceActiveFocus()
        }
    }

    function hide() {
        if (!showing)
            return
        showing = false
        closeTimer.restart()
    }

    // the card closes back into its notches first
    Timer {
        id: closeTimer
        interval: picker.animation + 60
        onTriggered: picker.dismissed()
    }

    function apply(i) {
        var file = files.get(i, "filePath")
        if (file)
            Quickshell.execDetached(["sh", here + "/apply.sh", file])
        hide()
    }

    // "sakura-b20d17a5a1e7.png" -> "sakura"
    function title(name) {
        return String(name || "").replace(/-[0-9a-f]{12}(\.[^.]*)?$/, "").replace(/[_-]+/g, " ")
    }

    function two(n) {
        return n < 10 ? "0" + n : String(n)
    }

    FolderListModel {
        id: files

        folder: "file://" + picker.indexDir.split("/").map(encodeURIComponent).join("/")
        showDirs: false
        sortField: FolderListModel.Name
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]

        onStatusChanged: {
            if (status !== FolderListModel.Ready || strip.started || count === 0)
                return
            var start = 0
            for (var i = 0; i < count; i++)
                if (get(i, "fileName") === picker.current)
                    start = i
            strip.jump(start)
            strip.started = true
        }
    }

    // a click outside the card closes it
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: picker.hide()
    }

    // ------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------
    TiltCard {
        id: card

        anchors.centerIn: parent
        width: Math.min(1560, picker.width - 80)
        height: header.height + stripBox.height + footer.height
        leanDegrees: 1
        duration: picker.animation
        shown: picker.showing

        // clicks on the card stay on the card
        MouseArea {
            anchors.fill: parent
        }

        // ---- header: the same strip as the share picker's
        Item {
            id: header

            width: parent.width
            height: 52

            Row {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "薬"
                    color: Theme.alert
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 24
                    font.bold: true
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "WALLPAPER"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 6
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "壁紙"
                    color: Theme.inkSoft
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 13
                    font.letterSpacing: 3
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                text: files.count > 0 ? picker.two(strip.marked + 1) + " / " + picker.two(files.count) : ""
                color: Theme.accent
                font.family: Theme.mono
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 2
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.tint(Theme.ink, 0.12)
            }
        }

        // ---- the strip
        Item {
            id: stripBox

            y: header.height
            width: parent.width
            height: Math.round(Math.min(440, picker.height * 0.42)) + 2 * 22
            clip: true

            Item {
                id: strip

                x: picker.pad
                y: 22
                width: parent.width - 2 * picker.pad
                height: parent.height - 2 * 22
                focus: true

                property bool started: false
                property int target: 0          // index the strip moves to / rests on
                property int marked: 0          // framed tile (hovered or target)
                property real pos: 0            // index in the middle, animated

                Behavior on pos {
                    enabled: strip.started

                    SmoothedAnimation {
                        velocity: picker.speed / strip.slot
                        duration: 1000
                    }
                }

                // ---- geometry
                readonly property real slot: width / Math.max(1, picker.visibleCount) - 10
                readonly property real half: width / 2
                readonly property real reach: Math.max(1, half / (slot + picker.gap))
                readonly property real wide: Math.min(height * picker.middleScale * picker.wideAspect, width * 0.5)

                function smooth(x) {
                    return x * x * (3 - 2 * x)
                }

                // tiles farther than this from the middle cannot be in view
                // (all the tiles in between are at least end size): they skip
                // the layout sums, so hundreds of pictures move as lightly as ten
                readonly property real limit: half / (slot * picker.edgeScale + picker.gap) + 4

                // dock size by distance d (in tiles) from the middle
                function sizeAt(d) {
                    var t = 1 - smooth(Math.min(1, Math.abs(d) / reach))
                    return picker.edgeScale + (picker.middleScale - picker.edgeScale) * t
                }

                // 1 in the middle, 0 from one tile away
                function opennessAt(d) {
                    return smooth(Math.max(0, 1 - Math.abs(d)))
                }

                function widthAt(d) {
                    var normal = slot * sizeAt(d)
                    return normal + (wide - normal) * opennessAt(d)
                }

                // centre-to-centre distance between tile d and tile d + 1
                function pitch(d) {
                    return (widthAt(d) + widthAt(d + 1)) / 2 + picker.gap
                }

                // horizontal offset of tile d from the middle
                function offset(d) {
                    var a = Math.floor(pos) - pos                // tile left of the middle, -1 < a <= 0
                    var steps = Math.round(d - a)
                    var x = a * pitch(a)
                    for (var i = 0; i < steps; i++)
                        x += pitch(a + i)
                    for (var j = -1; j >= steps; j--)
                        x -= pitch(a + j)
                    return x
                }

                // ---- moving
                function jump(i) {
                    target = i
                    marked = i
                    pos = i
                }

                function go(i) {
                    target = Math.max(0, Math.min(files.count - 1, i))
                    marked = target
                    pos = target
                }

                // wheel: one notch (120) = one wallpaper; smooth wheels and
                // touchpads add up first, a pause or a change of direction
                // starts over
                property real wheelSum: 0

                function wheel(event) {
                    var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
                    if (!wheelPause.running || delta * wheelSum < 0)
                        wheelSum = 0
                    wheelPause.restart()
                    wheelSum += delta
                    while (Math.abs(wheelSum) >= 120) {
                        var dir = wheelSum > 0 ? 1 : -1
                        wheelSum -= 120 * dir
                        go(target + dir)
                    }
                    event.accepted = true
                }

                Timer {
                    id: wheelPause
                    interval: 400
                }

                WheelHandler {
                    onWheel: function(event) { strip.wheel(event) }
                }

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Left)
                        strip.go(strip.target - 1)
                    else if (event.key === Qt.Key_Right)
                        strip.go(strip.target + 1)
                    else if (event.key === Qt.Key_Home)
                        strip.go(0)
                    else if (event.key === Qt.Key_End)
                        strip.go(files.count - 1)
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                        picker.apply(strip.marked)
                    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_W)
                        picker.hide()
                    else
                        return
                    event.accepted = true
                }

                // ---- tiles (only the ones in view load their picture)
                Repeater {
                    model: files

                    delegate: Item {
                        id: tile

                        required property int index
                        required property string fileName

                        readonly property real d: index - strip.pos
                        readonly property bool near: Math.abs(d) <= strip.limit
                        readonly property real open: near ? strip.opennessAt(d) : 0
                        readonly property real middle: near ? strip.half + strip.offset(d) : (d < 0 ? -1e6 : 1e6)
                        readonly property bool inView: middle + width / 2 > -picker.pad
                            && middle - width / 2 < strip.width + picker.pad
                        readonly property bool marked: strip.marked === index
                        readonly property bool isCurrent: fileName === picker.current
                        // the cut grows with the tile: small tiles, small cuts
                        readonly property real cut: Theme.cutSmall + (Theme.cut - Theme.cutSmall) * open
                        property bool seen: false

                        onInViewChanged: if (inView) seen = true
                        Component.onCompleted: if (inView) seen = true

                        width: near ? strip.widthAt(d) : 0
                        height: near ? strip.height * Math.min(1, strip.sizeAt(d)) : 0
                        x: middle - width / 2
                        y: (strip.height - height) / 2
                        visible: inView

                        // the empty tile, until (or unless) its picture is there
                        CutBox {
                            anchors.fill: parent
                            fill: Theme.tint(Theme.ink, 0.05)
                            cut: tile.cut
                            cutTopLeft: false
                            cutBottomRight: false
                        }

                        Text {
                            id: waiting

                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            color: Theme.inkMute
                            font.family: Theme.mono
                            font.pixelSize: 10
                            font.letterSpacing: 2
                        }

                        Image {
                            id: picture

                            anchors.fill: parent
                            visible: false               // drawn through the cut mask
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            smooth: true
                            sourceSize.width: strip.wide
                            sourceSize.height: strip.height
                            // names can hold # % ? and spaces: encode them for the URL
                            source: tile.seen ? "file://" + picker.thumbsDir.split("/").map(encodeURIComponent).join("/")
                                + "/" + encodeURIComponent(tile.fileName) : ""

                            // the thumbnail may still be being made: try again,
                            // a while (a picture that cannot be read is given up on)
                            property int tries: 0

                            onStatusChanged: {
                                if (status === Image.Error) {
                                    if (tries < 30) {
                                        waiting.text = "CACHING"
                                        again.restart()
                                    } else {
                                        waiting.text = "UNREADABLE"
                                    }
                                } else if (status === Image.Ready) {
                                    waiting.text = ""
                                }
                            }

                            Timer {
                                id: again

                                interval: 1000
                                onTriggered: {
                                    picture.tries += 1
                                    var src = picture.source
                                    picture.source = ""
                                    picture.source = src
                                }
                            }
                        }

                        CutBox {
                            id: mask

                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            fill: "white"
                            cut: tile.cut
                            cutTopLeft: false
                            cutBottomRight: false
                        }

                        MultiEffect {
                            anchors.fill: parent
                            visible: picture.status === Image.Ready
                            source: picture
                            maskEnabled: true
                            maskSource: mask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                            // the middle one at full light, the rest quieter
                            opacity: tile.marked ? 1 : 0.5 + 0.45 * tile.open

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.tFast }
                            }
                        }

                        // the marked one: an accent outline
                        CutBox {
                            anchors.fill: parent
                            visible: tile.marked
                            stroke: Theme.accent
                            strokeWidth: 2
                            cut: tile.cut
                            cutTopLeft: false
                            cutBottomRight: false
                        }

                        // the one on screen now: a small slanted mark on top
                        CutBox {
                            visible: tile.isCurrent
                            x: 10
                            y: 10
                            width: 22
                            height: 5
                            fill: Theme.accent
                            cut: 5
                            cutTopLeft: false
                            cutBottomRight: false
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: strip.marked = tile.index
                            onClicked: picker.apply(tile.index)
                            onWheel: function(event) { strip.wheel(event) }
                        }
                    }
                }
            }
        }

        // ---- footer: the name of the marked one, quietly
        Item {
            id: footer

            y: header.height + stripBox.height
            width: parent.width
            height: 56

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.tint(Theme.ink, 0.12)
            }

            Row {
                x: 28
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: files.count > 0 ? picker.title(files.get(strip.marked, "fileName")) : ""
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 15
                    font.letterSpacing: 1
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, card.width * 0.5)
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: files.count > 0 && files.get(strip.marked, "fileName") === picker.current
                    text: "NOW  現在"
                    color: Theme.accent
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                text: "←→  MOVE     ENTER  SET     ESC  CLOSE"
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 10
                font.letterSpacing: 1
            }
        }
    }
}
