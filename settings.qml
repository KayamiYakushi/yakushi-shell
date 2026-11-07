import Quickshell
import Quickshell.Io
import QtQuick

// Settings app. Started by shell.qml as its own short-lived process, so all
// of its memory is handed back the moment it closes. Talk to it through the
// shell (ipc call settings ...), not directly.
ShellRoot {
    id: root

    SettingsWindow {
        id: settingsWindow

        // the shell passes the start page (e.g. "tasks")
        Component.onCompleted: show(Quickshell.env("YAKUSHI_SETTINGS_PAGE") || "")

        onDismissed: quitTimer.restart()
    }

    IpcHandler {
        target: "settings"

        function hide(): void {
            settingsWindow.hide()
        }

        function open(name: string): void {
            settingsWindow.show(name)
        }

        function toggle(): void {
            if (settingsWindow.showing)
                settingsWindow.hide()
            else
                settingsWindow.show()
        }
    }

    Timer {
        id: quitTimer
        interval: Theme.tSlow + 160      // the card closes back into its notches first
        repeat: false
        onTriggered: Qt.quit()
    }
}
