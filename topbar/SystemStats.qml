import Quickshell
import Quickshell.Io
import QtQuick
import "../"

// RAM, CPU usage and temperatures for the top bar.
//
// Cost: every 2 seconds a few small kernel files are re-read (/proc/stat,
// /proc/meminfo, two hwmon inputs). No processes are spawned after start-up,
// and anything whose module is switched off is not read.
//
// While the bar shows seconds, the reads ride on the clock's tick (every
// other second) and are read right then (tiny files, no thread hop): the
// new numbers land in the frame the clock draws anyway, instead of waking
// the bar for frames of their own.
Item {
    id: stats

    visible: false

    required property var config
    // the bar's SystemClock: its seconds tick drives the reads when it has one
    property var clock: null
    readonly property bool onClockTick: clock !== null && clock.precision === SystemClock.Seconds
    readonly property bool wantAny: wantCpu || wantRam || wantCpuTemp || wantGpuTemp

    function read() {
        if (wantCpu)
            procStat.reload()
        if (wantRam)
            memInfo.reload()
        if (wantCpuTemp)
            cpuTempFile.reload()
        if (wantGpuTemp)
            gpuTempFile.reload()
    }

    Connections {
        target: stats.onClockTick && stats.wantAny ? stats.clock : null

        function onSecondsChanged() {
            if (stats.clock.seconds % 2 === 0)
                stats.read()
        }
    }

    readonly property bool wantCpu: config.modules.cpu
    readonly property bool wantRam: config.modules.ram
    readonly property bool wantCpuTemp: config.modules.cpuTemp && cpuTempPath !== ""
    readonly property bool wantGpuTemp: config.modules.gpuTemp && gpuTempPath !== ""

    property real cpuPercent: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property int cpuTemp: -1
    property int gpuTemp: -1

    property string cpuTempPath: ""
    property string gpuTempPath: ""

    // a laptop: the shell loads the battery (UPower) only then
    property bool hasBattery: false

    property real lastBusy: -1
    property real lastTotal: -1

    function readTemp(raw) {
        var milli = parseInt(raw)
        return isNaN(milli) ? -1 : Math.round(milli / 1000)
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: stats.wantAny && !stats.onClockTick

        onTriggered: stats.read()
    }

    FileView {
        id: procStat

        path: "/proc/stat"
        printErrors: false
        blockLoading: true

        onLoaded: {
            // first line: "cpu  user nice system idle iowait irq softirq steal ..."
            var t = text().slice(0, text().indexOf("\n")).trim().split(/\s+/).slice(1, 9).map(Number)
            if (t.length < 8 || t.some(isNaN))
                return

            var total = 0
            t.forEach(function(n) { total += n })
            var busy = total - t[3] - t[4]

            if (stats.lastTotal >= 0 && total > stats.lastTotal)
                stats.cpuPercent = Math.max(0, Math.min(100,
                    100 * (busy - stats.lastBusy) / (total - stats.lastTotal)))

            stats.lastBusy = busy
            stats.lastTotal = total
        }
    }

    FileView {
        id: memInfo

        path: "/proc/meminfo"
        printErrors: false
        blockLoading: true

        onLoaded: {
            var t = text()
            var total = t.match(/MemTotal:\s+(\d+)/)
            var avail = t.match(/MemAvailable:\s+(\d+)/)

            if (!total || !avail)
                return

            // kB -> GiB, matching what Waybar showed.
            stats.ramTotalGb = Number(total[1]) / 1048576
            stats.ramUsedGb = (Number(total[1]) - Number(avail[1])) / 1048576
        }
    }

    FileView {
        id: cpuTempFile

        path: stats.cpuTempPath
        printErrors: false
        blockLoading: true
        onLoaded: stats.cpuTemp = stats.readTemp(text())
    }

    FileView {
        id: gpuTempFile

        path: stats.gpuTempPath
        printErrors: false
        blockLoading: true
        onLoaded: stats.gpuTemp = stats.readTemp(text())
    }

    // Find the temperature sensors once (hwmon numbers change between boots),
    // and whether there is a battery.
    Process {
        running: true
        command: [
            "python3",
            Paths.script("yakushi-topbarctl.py"),
            "sensors"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)

                    if (data.cpu)
                        stats.cpuTempPath = data.cpu
                    if (data.gpu)
                        stats.gpuTempPath = data.gpu
                    stats.hasBattery = data.battery === true
                } catch (e) {
                }
            }
        }
    }
}
