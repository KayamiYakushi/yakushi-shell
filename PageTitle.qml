import QtQuick

// Page heading used at the top of each Settings page: an accent block, the
// title in heavy caps and a hard rule.
//
// When the page is one tab of a group in the page list (Programs, Appearance,
// Input: SettingsWindow `pages[].tabs`), the heading names the group's tabs
// instead: the open one as the title, its siblings smaller beside it, in
// the list's order. Click one to open it (Ctrl + Tab does the same).
Item {
    id: heading

    property string title: ""

    // the Settings window, from the page this heading sits on
    readonly property var host: {
        for (var p = heading.parent; p; p = p.parent)
            if (p.hostWindow !== undefined)
                return p.hostWindow
        return null
    }
    readonly property var tabs: host && host.pages[host.page].tabs ? host.pages[host.page].tabs : null

    implicitHeight: 26

    // the width the heading needs before its rule (to place things beside it)
    readonly property real needed: block.width + 12 + (tabs ? tabRow.width : label.implicitWidth) + 14
        + slashes.implicitWidth + 10 + 24

    // accent block, title, rule
    Rectangle {
        id: block

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 18
        color: Theme.accent
    }

    Text {
        id: label

        visible: !heading.tabs
        textFormat: Text.PlainText
        anchors.left: block.right
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: heading.title
        color: Theme.ink
        font.family: Theme.mono
        font.pixelSize: 20
        font.bold: true
        font.letterSpacing: 5
    }

    Row {
        id: tabRow

        visible: !!heading.tabs
        anchors.left: block.right
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 18

        Repeater {
            model: heading.tabs || []

            delegate: Text {
                id: tab

                required property var modelData
                required property int index
                readonly property bool here: heading.host && heading.host.tab === index

                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.name.toUpperCase()
                color: here || tabMouse.containsMouse ? Theme.ink : Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: here ? 20 : 11
                font.bold: true
                font.letterSpacing: here ? 5 : 2

                Behavior on color {
                    ColorAnimation { duration: Theme.tFast }
                }

                // a hover mark under the tabs you can open
                Rectangle {
                    visible: !tab.here && tabMouse.containsMouse
                    anchors.top: parent.bottom
                    anchors.topMargin: 3
                    width: parent.width
                    height: 2
                    color: Theme.accent
                }

                MouseArea {
                    id: tabMouse

                    enabled: !tab.here
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: heading.host.tab = tab.index
                }
            }
        }
    }

    Text {
        id: slashes

        textFormat: Text.PlainText
        anchors.left: heading.tabs ? tabRow.right : label.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "//"
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 12
    }

    Rectangle {
        anchors.left: slashes.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.tint(Theme.ink, 0.10)

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 7
            color: Theme.tint(Theme.ink, 0.35)
        }
    }
}
