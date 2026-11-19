import Quickshell
import QtQuick
import "../"

// A tray program's own menu (right-click its icon), drawn as one of the
// island's cards instead of a stock pop-up menu. A submenu opens in place,
// with a way back at the top. Choosing an entry closes the card.
Item {
    id: tm

    property var item: null               // the SystemTrayItem whose menu this is

    signal done()

    readonly property real wantedHeight: body.implicitHeight

    // the submenus walked into, innermost last
    property var path: []
    readonly property var current: path.length > 0 ? path[path.length - 1] : (item ? item.menu : null)

    onItemChanged: path = []

    function enter(entry) {
        path = path.concat([entry])
    }

    function back() {
        path = path.slice(0, path.length - 1)
    }

    // "_Open" -> "Open"; a doubled "__" stays as one "_"
    function plain(text) {
        return String(text || "").replace(/__/g, "\u0001").replace(/_/g, "").replace(/\u0001/g, "_")
    }

    function iconSource(icon) {
        if (typeof icon !== "string" || icon === "")
            return ""
        var at = icon.indexOf("?path=")
        if (at < 0)
            return icon
        var name = icon.slice(0, at)
        return "file://" + icon.slice(at + 6) + "/" + name.slice(name.lastIndexOf("/") + 1)
    }

    QsMenuOpener {
        id: opener

        menu: tm.current
    }

    component Rule: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.tint(Theme.ink, 0.08)
    }

    Column {
        id: body

        width: parent.width
        spacing: 8

        // ---- whose menu this is
        Item {
            width: parent.width
            height: 20

            Image {
                id: headIcon

                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                sourceSize: Qt.size(28, 28)
                source: tm.item ? tm.iconSource(tm.item.icon) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                anchors.left: headIcon.right
                anchors.leftMargin: 9
                anchors.right: jp.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: !tm.item ? ""
                    : (tm.item.tooltipTitle || tm.item.title || tm.item.id || "").toUpperCase()
                color: Theme.ink
                font.family: Theme.mono
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 3
            }

            Text {
                id: jp

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "トレイ"
                color: Theme.inkMute
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 10
                font.letterSpacing: 2
            }
        }

        Rule {}

        Column {
            width: parent.width

            // ---- back out of a submenu
            Entry {
                visible: tm.path.length > 0
                glyph: String.fromCodePoint(0xF0141)
                label: tm.plain(tm.path.length > 0 ? tm.path[tm.path.length - 1].text : "")
                dim: true
                onPicked: tm.back()
            }

            Repeater {
                model: opener.children

                delegate: Item {
                    id: row

                    required property var modelData

                    width: parent.width
                    height: modelData.isSeparator ? 9 : 26

                    Rule {
                        visible: row.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Entry {
                        visible: !row.modelData.isSeparator
                        width: parent.width
                        entry: row.modelData
                        label: tm.plain(row.modelData.text)
                        image: tm.iconSource(row.modelData.icon)
                        onPicked: {
                            if (row.modelData.hasChildren) {
                                tm.enter(row.modelData)
                            } else {
                                row.modelData.triggered()
                                tm.done()
                            }
                        }
                    }
                }
            }
        }
    }

    // One line of the menu: a check / radio mark or icon, the text, and an
    // arrow when it leads to a submenu.
    component Entry: Item {
        id: e

        property var entry: null
        property string label: ""
        property string image: ""
        property string glyph: ""
        property bool dim: false
        signal picked()

        readonly property bool usable: !entry || entry.enabled
        readonly property bool hot: mouse.containsMouse && usable
        // 1 = CheckBox, 2 = RadioButton (QsMenuButtonType)
        readonly property int kind: entry ? entry.buttonType : 0
        readonly property bool checked: entry !== null && entry.checkState === Qt.Checked

        width: parent ? parent.width : 0
        height: 26

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -8
            anchors.rightMargin: -8
            color: e.hot ? Theme.tint(Theme.accent, 0.10) : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }
        }

        // the mark on the left: a check, a radio dot, an icon, or nothing
        Item {
            id: mark

            width: 16
            height: parent.height

            Text {
                visible: e.kind !== 0 || e.glyph !== ""
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: e.glyph !== "" ? e.glyph
                    : e.kind === 2 ? String.fromCodePoint(e.checked ? 0xF043E : 0xF043D)
                    : String.fromCodePoint(e.checked ? 0xF0132 : 0xF0131)
                color: e.checked || e.hot ? Theme.accent : Theme.inkMute
                font.family: Theme.glyphs
                font.pixelSize: 12
            }

            Image {
                visible: e.kind === 0 && e.glyph === "" && e.image !== ""
                anchors.centerIn: parent
                width: 14
                height: 14
                sourceSize: Qt.size(28, 28)
                source: visible ? e.image : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: e.usable ? 1 : 0.4
            }
        }

        Text {
            anchors.left: mark.right
            anchors.leftMargin: 10
            anchors.right: arrow.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: e.label
            color: !e.usable ? Theme.inkMute
                : e.hot ? Theme.ink
                : e.dim ? Theme.inkSoft : Theme.tint(Theme.ink, 0.88)
            font.family: Theme.mono
            font.pixelSize: 11
        }

        Text {
            id: arrow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: e.entry !== null && e.entry.hasChildren
            textFormat: Text.PlainText
            text: String.fromCodePoint(0xF0142)
            color: e.hot ? Theme.accent : Theme.inkMute
            font.family: Theme.glyphs
            font.pixelSize: 12
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: e.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: e.picked()
        }
    }
}
