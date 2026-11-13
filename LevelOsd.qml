import QtQuick

// The pill for things the shell is told about, not ones it listens to: the
// screen brightness after a brightness key (yakushi brightness ...) and the
// battery running low (topbar/BatteryState.qml).
OsdPill {
    id: osd

    // kind: "brightness" | "battery"; percent 0..100
    function present(kind, percent) {
        var p = Math.max(0, Math.min(100, Math.round(percent)))
        var warning = kind === "battery"
        level = p / 100
        text = p + "%"
        tone = warning ? Theme.alert : Theme.accent
        textColor = warning ? Theme.alert : Theme.ink
        hold = warning ? 5000 : 1200
        glyph = String.fromCodePoint(warning ? 0xF0083
            : p < 34 ? 0xF00DE
            : p < 67 ? 0xF00DF : 0xF00E0)
        poke()
    }
}
