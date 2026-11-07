import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../"

// The stack of notification pop-ups, top-right on the monitor that had the
// focus when the first one arrived. Click-through except for the cards.
// shell.qml loads this only while there is something to show.
PanelWindow {
    id: popups

    required property var server
    property int timeout: 5

    function focusedScreen() {
        var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        var list = Quickshell.screens
        for (var i = 0; i < list.length; i++)
            if (list[i].name === name)
                return list[i]
        return list.length > 0 ? list[0] : null
    }

    // chosen once: the stack does not jump between monitors while it is up
    screen: focusedScreen()
    Component.onCompleted: screen = focusedScreen()

    anchors {
        top: true
        right: true
    }
    margins {
        top: 10
        right: 12
    }

    implicitWidth: 380
    implicitHeight: Math.max(1, stack.implicitHeight + 8)
    color: "transparent"

    // stays below the bar's zone, reserves nothing itself
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yakushi-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: stack
    }

    Column {
        id: stack

        x: 4
        width: popups.implicitWidth - 8
        spacing: 10

        Repeater {
            model: popups.server.trackedNotifications

            NotificationCard {
                required property var modelData

                width: stack.width
                notification: modelData
                timeout: popups.timeout
            }
        }
    }
}
