import QtQuick
import Quickshell.Services.SystemTray

// The system tray: the little icons programs put up for themselves
// (StatusNotifierItem). Loaded by file from shell.qml only while the tray
// module is on, so with it off nothing listens on D-Bus for them.
//
// Programs that ask to be hidden for now (Passive) are left out; the rest
// keep the order they arrived in.
QtObject {
    readonly property var items: SystemTray.items.values.filter(function(item) {
        return item.status !== Status.Passive
    })
    readonly property int count: items.length
}
