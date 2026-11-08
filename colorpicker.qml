import Quickshell
import Quickshell.Io
import QtQuick
import "colorpicker"

// The colour picker (SUPER + SHIFT + C): its own short-lived process,
// started by colorpicker/launch.sh once every screen has been captured.
// One window per screen; a click on any of them copies that colour and
// ends the process. SUPER + SHIFT + C again closes it (launch.sh calls
// `hide`).
ShellRoot {
    id: root

    readonly property string shots: Quickshell.env("YAKUSHI_COLORPICKER_SHOTS") || ""
    // only the screens launch.sh captured get a window
    readonly property var captured: (Quickshell.env("YAKUSHI_COLORPICKER_SCREENS") || "").split(" ")

    // "" while picking; the copied colour while it says so, just before
    // the picker closes
    property string copied: ""

    function pick(hex) {
        if (copied !== "")
            return
        // the text on the clipboard; wl-copy stays in the background to
        // serve it
        Quickshell.execDetached(["wl-copy", "--", hex])
        copied = hex
        quitTimer.restart()
    }

    // the accent from Settings (read only: the picker saves nothing)
    function applyAccent() {
        var a = Config.appearance.accent
        if (typeof a === "string" && /^#[0-9a-fA-F]{6}$/.test(a))
            Theme.accent = a
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false
        applyAccent()
    }

    Connections {
        target: Config

        function onAppearanceChanged() {
            root.applyAccent()
        }
    }

    Variants {
        model: Quickshell.screens.filter(s => root.captured.indexOf(s.name) >= 0)

        ColorPicker {
            shots: root.shots
            copied: root.copied

            onPicked: hex => root.pick(hex)
            onCancelled: Qt.quit()
        }
    }

    IpcHandler {
        target: "colorpicker"

        function hide(): void {
            Qt.quit()
        }
    }

    // long enough to read COPIED
    Timer {
        id: quitTimer

        interval: 650
        onTriggered: Qt.quit()
    }
}
