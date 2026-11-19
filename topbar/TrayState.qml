import QtQuick
import Quickshell.Services.SystemTray

// The system tray: the little icons programs put up for themselves
// (StatusNotifierItem). Loaded by file from shell.qml only while the tray
// module is on, so with it off nothing listens on D-Bus for them.
//
// Every program is shown, in the order it arrived. "Passive" ones are not
// hidden: Spotify, for one, reports itself Passive all the time.
QtObject {
    readonly property var items: SystemTray.items.values
    readonly property int count: items.length
}
