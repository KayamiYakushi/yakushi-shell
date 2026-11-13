import Quickshell
import Quickshell.Services.UPower
import QtQuick

// The computer's battery, from UPower: charge, charging or not, time left.
// UPower sends changes, nothing here polls.
//
// The shell loads this only on a computer that has a battery (the bar's
// start-up check, yakushi-topbarctl.py sensors), so a desktop never starts
// the UPower daemon for it.
Item {
    id: battery

    visible: false

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery

    readonly property int percent: present ? Math.round(Math.max(0, Math.min(1, device.percentage)) * 100) : 0
    readonly property bool plugged: !UPower.onBattery
    readonly property bool full: present && device.state === UPowerDeviceState.FullyCharged
    readonly property bool charging: present && (device.state === UPowerDeviceState.Charging
                                                 || device.state === UPowerDeviceState.PendingCharge)

    // running out: the bar turns red at `low`, the pill warns at both
    readonly property int lowAt: 15
    readonly property int criticalAt: 5
    readonly property bool low: present && !plugged && percent <= lowAt
    readonly property bool critical: present && !plugged && percent <= criticalAt

    // "2 h 14 min left", "full in 40 min", "" when UPower has no estimate yet
    readonly property string timeText: {
        if (!present)
            return ""
        var seconds = charging ? device.timeToFull : plugged ? 0 : device.timeToEmpty
        if (!(seconds > 0))
            return ""
        var minutes = Math.round(seconds / 60)
        var span = minutes >= 60 ? Math.floor(minutes / 60) + " h " + (minutes % 60) + " min" : minutes + " min"
        return charging ? "full in " + span : span + " left"
    }

    // the bar icon: a battery filled to the nearest tenth, a bolt while charging
    readonly property string glyph: {
        if (charging || (plugged && !full))
            return String.fromCodePoint(0xF0084)
        if (percent <= criticalAt)
            return String.fromCodePoint(0xF008E)
        var tenth = Math.round(percent / 10)
        return String.fromCodePoint(tenth >= 10 ? 0xF0079 : 0xF0079 + Math.max(1, tenth))
    }

    // Said once each time the charge falls to `lowAt`, and once more at
    // `criticalAt`; plugging in starts over.
    signal warn(int percent)

    property int warned: 101            // the lowest mark already announced

    function check() {
        if (!present)
            return
        if (plugged) {
            warned = 101
            return
        }
        var mark = percent <= criticalAt ? criticalAt : percent <= lowAt ? lowAt : 101
        if (mark < warned)
            warn(percent)
        warned = mark
    }

    // Looked at once the values have settled: UPower's arrive one by one
    // (a charge of 0 for an instant at start-up is not a warning), and a
    // warning two seconds late is still in time.
    Timer {
        id: settle
        interval: 2000
        onTriggered: battery.check()
    }

    onPercentChanged: settle.restart()
    onPluggedChanged: settle.restart()
    onPresentChanged: settle.restart()
}
