import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import "../"

// One notification pop-up: a small sibling of the Settings card (top-right
// and bottom-left corners cut, an accent notch on each cut). App name with
// 通知, summary, body, the app's buttons, and a slanted bar that runs down
// until the pop-up goes. Pointer over it: the time stops. Click: the app's
// default action (or just close); ✕ closes.
//
// Text is always plain: markup, links and remote images in a notification
// are never interpreted.
Item {
    id: card

    required property var notification
    property int timeout: 5                 // seconds, when the app asks for none

    readonly property var n: notification
    readonly property bool critical: n !== null && n.urgency === NotificationUrgency.Critical

    // Critical ones stay until you close them; otherwise the app's own
    // timeout (it arrives in milliseconds, as sent over D-Bus; capped at a
    // minute) or ours, in seconds.
    readonly property real lifetime: critical ? 0
        : n.expireTimeout > 0 ? Math.min(n.expireTimeout / 1000, 60) : timeout

    readonly property var buttons: {
        var list = []
        var actions = n ? n.actions : []
        for (var i = 0; i < actions.length; i++)
            if (actions[i].identifier !== "default" && actions[i].text !== "")
                list.push(actions[i])
        return list
    }

    readonly property var defaultAction: {
        var actions = n ? n.actions : []
        for (var i = 0; i < actions.length; i++)
            if (actions[i].identifier === "default")
                return actions[i]
        return null
    }

    function plain(text) {
        return String(text || "")
            .replace(/<[^>]*>/g, "")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'")
            .replace(/&amp;/g, "&")
            .trim()
    }

    function iconSource() {
        if (!n)
            return ""
        if (n.image !== "")
            return n.image
        var icon = n.appIcon || ""
        if (icon === "")
            return ""
        if (icon.charAt(0) === "/")
            return "file://" + icon
        if (icon.indexOf("file://") === 0)
            return icon
        return Quickshell.iconPath(icon, true)
    }

    function activate() {
        if (defaultAction)
            defaultAction.invoke()
        else
            n.dismiss()
    }

    implicitHeight: content.implicitHeight + 28

    // ---- slide in from the right
    property real arrive: 0
    Component.onCompleted: arrive = 1
    Behavior on arrive {
        NumberAnimation { duration: Theme.tMid + 40; easing.type: Easing.OutCubic }
    }
    opacity: arrive
    transform: Translate { x: (1 - card.arrive) * 48 }

    // ---- time left (1 -> 0); stops while the pointer is over the card
    property real remaining: 1

    NumberAnimation on remaining {
        id: countdown

        running: card.lifetime > 0
        paused: running && hover.hovered
        from: 1
        to: 0
        duration: card.lifetime * 1000
        onFinished: if (card.n) card.n.expire()
    }

    HoverHandler {
        id: hover
    }

    // ---- shape
    CutBox {
        anchors.fill: parent
        fill: "#eb050505"
        stroke: card.critical ? Theme.tint(Theme.alert, 0.6) : Theme.tint(Theme.ink, 0.12)
        cutTopLeft: false
        cutBottomRight: false
    }

    component Notch: Rectangle {
        property real side: 1        // 1 = top-right, -1 = bottom-left

        width: Theme.cut * Math.SQRT2 + 8
        height: 2
        x: (side > 0 ? card.width - Theme.cut / 2 : Theme.cut / 2) + side * 2.8 - width / 2
        y: (side > 0 ? Theme.cut / 2 : card.height - Theme.cut / 2) - side * 2.8 - height / 2
        rotation: 45
        antialiasing: true
        color: card.critical ? Theme.alert : Theme.accent
    }

    Notch { side: 1 }
    Notch { side: -1 }

    // click anywhere (under the buttons below)
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: card.activate()
    }

    Column {
        id: content

        x: 16
        y: 14
        width: card.width - 32
        spacing: 6

        // header: icon, APP 通知, close
        Item {
            width: parent.width
            height: 16

            Image {
                id: appIcon

                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                sourceSize: Qt.size(32, 32)
                source: card.iconSource()
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Row {
                anchors.left: appIcon.visible ? appIcon.right : parent.left
                anchors.leftMargin: appIcon.visible ? 8 : 0
                anchors.right: close.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                clip: true

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: (card.plain(card.n ? card.n.appName : "") || "Notification").toUpperCase()
                    color: card.critical ? Theme.alert : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "通知"
                    color: Theme.inkMute
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }

            Text {
                id: close

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: closeMouse.containsMouse ? Theme.accent : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 11

                MouseArea {
                    id: closeMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.n.dismiss()
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            text: card.plain(card.n ? card.n.summary : "")
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 12
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            text: card.plain(card.n ? card.n.body : "")
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            lineHeight: 1.15
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        // the app's own buttons
        Flow {
            width: parent.width
            visible: card.buttons.length > 0
            spacing: 6
            topPadding: 2

            Repeater {
                model: card.buttons

                Rectangle {
                    id: button

                    required property var modelData

                    width: label.implicitWidth + 20
                    height: 22
                    color: buttonMouse.containsMouse ? Theme.tint(Theme.accent, 0.12) : Theme.tint(Theme.ink, 0.045)
                    border.width: 1
                    border.color: buttonMouse.containsMouse ? Theme.tint(Theme.accent, 0.7) : Theme.tint(Theme.ink, 0.08)

                    Text {
                        id: label

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: card.plain(button.modelData.text).toUpperCase()
                        color: buttonMouse.containsMouse ? Theme.ink : Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        id: buttonMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: button.modelData.invoke()
                    }
                }
            }
        }

        // time left
        SlantBar {
            width: parent.width
            height: 3
            visible: card.lifetime > 0
            value: card.remaining
            trackColor: Theme.tint(Theme.ink, 0.06)
        }
    }
}
