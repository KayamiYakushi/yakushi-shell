import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The volume pill: drops in under the bar when you press the volume keys.
// The shell loads it on "ipc call volumeOsd reveal" (yakushi volume ...)
// and frees it shortly after the last change.
OsdPill {
    id: osd

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var out: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property real volume: out ? out.volume : 0
    readonly property bool silent: out ? out.muted : false

    Connections {
        target: osd.out
        function onVolumeChanged() { osd.poke() }
        function onMutedChanged() { osd.poke() }
    }

    tone: silent ? Theme.alert : Theme.accent
    level: silent ? 0 : volume
    text: silent ? "Muted" : Math.round(volume * 100) + "%"
    textColor: silent ? Theme.alert : Theme.ink
    glyph: String.fromCodePoint(silent || volume < 0.005 ? 0xF0581
        : volume < 0.34 ? 0xF057F
        : volume < 0.67 ? 0xF0580 : 0xF057E)
}
