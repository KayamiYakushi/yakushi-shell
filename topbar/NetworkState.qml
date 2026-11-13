import Quickshell
import Quickshell.Networking
import QtQuick

// What the bar says about the network: Wi-Fi and how strong, or offline.
// NetworkManager sends changes, nothing here polls. The shell loads this
// only while the Network module is switched on.
//
// A cable says nothing: plugged in and working, the module is not shown.
Item {
    id: net

    visible: false

    // { kind: "wired" | "wifi" | "offline", strength: 0..1, name, hasWifi }
    // `devices` are Networking's (tests pass look-alikes).
    function describe(devices, wifiType, wiredType) {
        var wifi = null
        var hasWifi = false
        for (var i = 0; i < devices.length; i++) {
            var device = devices[i]
            if (device.type === wiredType && device.connected)
                return { kind: "wired", strength: 1, name: "", hasWifi: false }
            if (device.type !== wifiType)
                continue
            hasWifi = true
            if (!device.connected)
                continue
            var networks = device.networks ? device.networks.values : []
            for (var j = 0; j < networks.length; j++) {
                var network = networks[j]
                if (network.connected && (wifi === null || network.signalStrength > wifi.signalStrength))
                    wifi = network
            }
            if (wifi === null)
                wifi = { name: "", signalStrength: 0 }
        }
        if (wifi !== null)
            return { kind: "wifi", strength: Math.max(0, Math.min(1, wifi.signalStrength)), name: wifi.name || "", hasWifi: true }
        return { kind: "offline", strength: 0, name: "", hasWifi: hasWifi }
    }

    readonly property bool ready: Networking.backend !== NetworkBackendType.None
    readonly property var now: describe(Networking.devices.values, DeviceType.Wifi, DeviceType.Wired)

    // something else carries the connection (a phone over Bluetooth, a
    // modem): NetworkManager still knows the internet is there
    readonly property bool online: now.kind !== "offline" || Networking.connectivity === NetworkConnectivity.Full

    readonly property bool wifi: ready && now.kind === "wifi"
    readonly property real strength: now.strength
    readonly property string name: now.name

    // Offline is said only once it has lasted a moment: waking up or
    // switching networks passes through it.
    property bool offline: false
    readonly property bool offlineNow: ready && !online

    onOfflineNowChanged: {
        if (offlineNow) {
            settle.restart()
        } else {
            settle.stop()
            offline = false
        }
    }

    Timer {
        id: settle
        interval: 4000
        onTriggered: net.offline = net.offlineNow
    }

    Component.onCompleted: if (offlineNow) settle.restart()

    readonly property bool shown: wifi || offline

    readonly property string glyph: {
        if (!wifi)
            return String.fromCodePoint(now.hasWifi ? 0xF05AA : 0xF0318)
        // four steps: outline, then one to four arcs
        return String.fromCodePoint(strength < 0.15 ? 0xF092F
            : strength < 0.4 ? 0xF091F
            : strength < 0.6 ? 0xF0922
            : strength < 0.8 ? 0xF0925 : 0xF0928)
    }
}
