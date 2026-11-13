import QtQuick
import "../"

// The small caps name over a group of settings (ACCENT, CLOCK, ...), with an
// optional quiet remark after it and an optional action on the right
// (RESET ORDER, TRY IT).
Item {
    id: head

    property string text: ""
    property string hint: ""
    property string action: ""

    signal activated()

    width: parent ? parent.width : 0
    implicitHeight: 16

    Text {
        id: name

        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: head.text
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 11
        font.letterSpacing: 2
    }

    Text {
        textFormat: Text.PlainText
        visible: head.hint !== ""
        anchors.left: name.right
        anchors.leftMargin: 12
        anchors.right: act.left
        anchors.rightMargin: 12
        anchors.baseline: name.baseline
        text: head.hint
        elide: Text.ElideRight
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    Text {
        id: act

        textFormat: Text.PlainText
        visible: head.action !== ""
        anchors.right: parent.right
        anchors.baseline: name.baseline
        text: head.action
        color: actMouse.containsMouse ? Theme.accent : Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 10
        font.letterSpacing: 2

        Behavior on color {
            ColorAnimation { duration: Theme.tFast }
        }

        Rectangle {
            visible: actMouse.containsMouse
            anchors.top: parent.bottom
            anchors.topMargin: 2
            width: parent.width
            height: 1
            color: Theme.accent
        }

        MouseArea {
            id: actMouse

            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: head.activated()
        }
    }
}
