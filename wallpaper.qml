import Quickshell
import Quickshell.Io
import QtQuick
import "wallpicker"

// The wallpaper picker (SUPER + W): its own short-lived process, started by
// wallpicker/launch.sh after the pictures have been indexed. Every byte of
// its thumbnails is handed back the moment it closes. SUPER + W again
// closes it (launch.sh calls `hide`).
ShellRoot {
    WallpaperPicker {
        id: picker

        onDismissed: Qt.quit()
    }

    IpcHandler {
        target: "wallpaper"

        function hide(): void {
            picker.hide()
        }
    }
}
