import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Settings -> Appearance -> Apps
//
// How the programs you open look: light or dark, GTK apps in the shell's
// colours (scripts/yakushi-schemectl.py, yakushi-gtkctl.py) and the terminal
// (scripts/yakushi-termctl.py).
Item {
    id: page

    property var hostWindow: null
    readonly property string homeDir: Paths.home

    // ---- apps light / dark (scripts/yakushi-schemectl.py)
    property string scheme: ""          // "dark" | "light", "" until known
    property string schemeNote: ""

    function setScheme(value) {
        if (schemeJob.running || value === scheme)
            return
        scheme = value                  // the cards answer at once
        schemeJob.command = ["python3", Paths.script("yakushi-schemectl.py"), "set", value]
        schemeJob.running = true
    }

    Process {
        id: schemeJob

        command: ["python3", Paths.script("yakushi-schemectl.py"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    page.scheme = d.scheme
                    page.schemeNote = d.message
                        || (d.portal === false ? "Install xdg-desktop-portal-gtk so Files and other GTK4 apps follow too." : "")
                } catch (e) {
                    page.schemeNote = "Could not read the app theme."
                }
            }
        }
    }

    // first load
    Component.onCompleted: {
        schemeJob.running = true
        termGet.command = ["python3", page.termHelperPath(), "status"]
        termGet.running = true
        appsGet.running = true
    }

    // ------------------------------------------------------------------
    // Terminal colours (yakushi-termctl.py)
    // ------------------------------------------------------------------
    property bool termEnabled: false
    property bool termLoaded: false
    property string termDetected: ""
    property string termStatus: ""
    property real termOpacity: 1.0
    property bool termBlur: true
    property int termBlurStrength: 3
    property int termPadding: 0
    property string termName: ""
    property bool termColours: true

    function readTermSettings(data) {
        if (typeof data.opacity === "number")
            page.termOpacity = data.opacity
        if (typeof data.blur === "boolean")
            page.termBlur = data.blur
        if (typeof data.blurStrength === "number")
            page.termBlurStrength = data.blurStrength
        if (typeof data.padding === "number" && !termPaddingProc.running && !termPaddingDebounce.running)
            page.termPadding = data.padding
    }

    function saveTermPadding() {
        if (homeDir === "")
            return
        if (termPaddingProc.running) {
            termPaddingDebounce.restart()
            return
        }
        termPaddingProc.command = ["python3", termHelperPath(), "padding", String(termPadding)]
        termPaddingProc.running = true
    }

    Timer {
        id: termPaddingDebounce
        interval: 200
        onTriggered: page.saveTermPadding()
    }

    Process {
        id: termPaddingProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.termStatus = JSON.parse(text).message || ""
                } catch (e) {
                }
            }
        }
    }

    function setTermBlur(on) {
        if (termBlurProc.running || homeDir === "")
            return
        termBlur = on
        termBlurProc.command = ["python3", termHelperPath(), "blur", on ? "on" : "off"]
        termBlurProc.running = true
    }

    function saveTermBlurStrength() {
        if (homeDir === "")
            return
        if (termStrengthProc.running) {
            termStrengthDebounce.restart()
            return
        }
        termStrengthProc.command = ["python3", termHelperPath(), "blur-strength", String(termBlurStrength)]
        termStrengthProc.running = true
    }

    Timer {
        id: termStrengthDebounce
        interval: 200
        onTriggered: page.saveTermBlurStrength()
    }

    Process {
        id: termBlurProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.readTermSettings(data)
                    page.termStatus = data.message || ""
                } catch (e) {
                    page.termStatus = "Could not change terminal blur."
                }
            }
        }
    }

    Process {
        id: termStrengthProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.termStatus = JSON.parse(text).message || ""
                } catch (e) {
                }
            }
        }
    }

    function saveTermOpacity() {
        if (homeDir === "")
            return
        if (termOpacityProc.running) {
            termOpacityDebounce.restart()
            return
        }
        termOpacityProc.command = ["python3", termHelperPath(), "opacity", termOpacity.toFixed(2)]
        termOpacityProc.running = true
    }

    Timer {
        id: termOpacityDebounce
        interval: 200
        onTriggered: page.saveTermOpacity()
    }

    Process {
        id: termOpacityProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.termStatus = data.message || ""
                } catch (e) {
                }
            }
        }
    }

    function termHelperPath() {
        return Paths.script("yakushi-termctl.py")
    }

    function describeTerm(data) {
        var parts = []
        var term = data.terminal || ""
        termName = term
        termColours = data.terminalColours !== false
        if (term !== "")
            parts.push(term + " (default" + (termColours ? "" : ", blur + opacity only") + ")")
        var others = (data.terminals || []).filter(function(t) { return t !== term })
        if (others.length > 0)
            parts.push(others.join(", "))
        if (data.fish)
            parts.push(data.shell === "fish" ? "fish (login shell)" : "fish")
        termDetected = parts.length > 0
            ? parts.join("  ·  ")
            : "no kitty, alacritty, foot, ghostty or fish found"
    }

    function setTerm(on) {
        if (termSet.running || homeDir === "")
            return
        termEnabled = on
        termStatus = on ? "Applying colours..." : "Restoring colours..."
        termSet.command = ["python3", termHelperPath(), on ? "enable" : "disable"]
        termSet.running = true
    }

    Process {
        id: termGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.termEnabled = data.enabled === true
                    page.readTermSettings(data)
                    page.describeTerm(data)
                    page.termLoaded = true
                } catch (e) {
                    page.termDetected = "could not detect the terminal"
                }
            }
        }
    }

    Process {
        id: termSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.termEnabled = data.enabled === true
                    page.readTermSettings(data)
                    page.termStatus = data.message || ""
                    page.describeTerm(data)
                } catch (e) {
                    page.termStatus = "Could not change terminal colours."
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // GTK apps: colours, file manager opacity (yakushi-gtkctl.py)
    // ------------------------------------------------------------------
    property bool appsLoaded: false
    property bool appsColours: false
    property real filesOpacity: 1.0
    property string appsStatus: ""
    property bool filesOpen: false          // Files (Nautilus) is running
    property bool appsChanged: false        // changed since this page opened

    function readApps(data) {
        if (typeof data.colours === "boolean")
            appsColours = data.colours
        if (typeof data.filesOpacity === "number")
            filesOpacity = data.filesOpacity
        if (typeof data.filesOpen === "boolean")
            filesOpen = data.filesOpen
    }

    // GTK reads its style only at start-up: open Files windows keep the old
    // look until Files restarts. Done only on request (a running copy would
    // be cut short).
    function reopenFiles() {
        if (appsReopen.running)
            return
        appsStatus = "Reopening Files..."
        appsReopen.running = true
    }

    Process {
        id: appsReopen

        command: ["python3", Paths.script("yakushi-gtkctl.py"), "reopen"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.appsStatus = data.message || ""
                    page.appsChanged = false
                    if (typeof data.filesOpen === "boolean")
                        page.filesOpen = data.filesOpen
                } catch (e) {
                    page.appsStatus = "Could not reopen Files."
                }
            }
        }
    }

    function setAppsColours(on) {
        if (appsSet.running)
            return
        appsColours = on
        appsSet.command = ["python3", Paths.script("yakushi-gtkctl.py"), "set", "colours", on ? "on" : "off"]
        appsSet.running = true
    }

    function saveFilesOpacity() {
        if (appsSet.running) {
            filesOpacityDebounce.restart()      // after the save that is running
            return
        }
        appsSet.command = ["python3", Paths.script("yakushi-gtkctl.py"), "set", "opacity", filesOpacity.toFixed(2)]
        appsSet.running = true
    }

    Timer {
        id: filesOpacityDebounce
        interval: 200
        onTriggered: page.saveFilesOpacity()
    }

    Process {
        id: appsGet

        command: ["python3", Paths.script("yakushi-gtkctl.py"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok) {
                        page.readApps(data)
                        page.appsLoaded = true
                    } else {
                        page.appsStatus = data.message || ""
                    }
                } catch (e) {
                    page.appsStatus = "Could not read the app settings."
                }
            }
        }
    }

    Process {
        id: appsSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.appsStatus = data.message || ""
                    if (data.ok) {
                        page.readApps(data)
                        page.appsChanged = true
                    } else {
                        appsGet.running = true
                    }
                } catch (e) {
                    page.appsStatus = "Could not save the app settings."
                }
            }
        }
    }

    ScrollHint {
        flick: flick
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: body.height + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body

            width: flick.width
            spacing: 16

            PageTitle {
                width: parent.width
                title: "APPS"
            }

            Divider {}

            // ---------------- Apps: light / dark ----------------
            SectionHead {
                text: "LIGHT OR DARK"
                hint: "GTK 3 · GTK 4 · Files · Firefox"
            }

            Row {
                id: schemeRow

                width: parent.width
                spacing: 10

                Repeater {
                    model: [
                        { key: "dark", label: "DARK", jp: "暗", hint: "Dark windows everywhere",
                          paper: "#161616", bar: "#262626", ink: "#e6e6e6" },
                        { key: "light", label: "LIGHT", jp: "明", hint: "Light windows everywhere",
                          paper: "#f4f4f4", bar: "#dcdcdc", ink: "#2a2a2a" }
                    ]

                    delegate: Rectangle {
                        id: schemeCard

                        required property var modelData
                        readonly property bool selected: page.scheme === modelData.key

                        width: (schemeRow.width - schemeRow.spacing) / 2
                        height: 64
                        color: selected ? Theme.tint(Theme.accent, 0.10) : Theme.card
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (schemeMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        // a tiny app window in that scheme
                        Rectangle {
                            id: miniWindow

                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 54
                            height: 38
                            color: schemeCard.modelData.paper
                            border.width: 1
                            border.color: schemeCard.selected ? Theme.accent : Theme.inkMute
                            clip: true

                            Rectangle {
                                width: parent.width
                                height: 9
                                color: schemeCard.modelData.bar
                            }

                            Repeater {
                                model: 3

                                Rectangle {
                                    required property int index

                                    x: 7
                                    y: 14 + index * 7
                                    width: index === 1 ? 26 : 36
                                    height: 3
                                    color: index === 0 && schemeCard.selected ? Theme.accent : schemeCard.modelData.ink
                                    opacity: index === 0 ? 1 : 0.55
                                }
                            }
                        }

                        Column {
                            anchors.left: miniWindow.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Row {
                                spacing: 8

                                Text {
                                    textFormat: Text.PlainText
                                    text: schemeCard.modelData.label
                                    color: schemeCard.selected ? Theme.accent : Theme.ink
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.letterSpacing: 2
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: schemeCard.modelData.jp
                                    color: Theme.inkSoft
                                    font.family: "Noto Sans CJK JP"
                                    font.pixelSize: 11
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                text: schemeCard.modelData.hint
                                color: Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: schemeMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.setScheme(schemeCard.modelData.key)
                        }
                    }
                }
            }

            Note {
                visible: page.schemeNote !== ""
                text: page.schemeNote
            }

            Divider {}

            // ---------------- GTK apps in the shell's colours ----------------
            SectionHead {
                text: "COLOURS"
                hint: "Files, Celluloid, Meld and other GTK apps"
            }

            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF024B)
                label: "Match app colours"
                checked: page.appsColours
                available: page.appsLoaded && !appsSet.running
                onToggled: page.setAppsColours(!page.appsColours)
            }

            Slider {
                width: parent.width
                // always shown, so it can be found; usable once the colours are on
                opacity: page.appsColours ? 1 : 0.35
                enabled: page.appsColours && page.appsLoaded
                label: "File manager opacity  " + Math.round(page.filesOpacity * 100) + "%"
                    + (page.appsColours ? "" : "   (turn on Match app colours)")
                icon: "◐"
                tint: Theme.accent
                value: (page.filesOpacity - 0.30) / 0.70

                onSliding: function(v) {
                    page.filesOpacity = 0.30 + v * 0.70
                    filesOpacityDebounce.restart()
                }

                onSettled: function(v) {
                    page.filesOpacity = 0.30 + v * 0.70
                    filesOpacityDebounce.stop()
                    page.saveFilesOpacity()
                }
            }

            Note {
                text: page.appsStatus !== ""
                    ? page.appsStatus
                    : "Apps take the shell's surfaces and accent. The opacity is for the file manager only: its background lets the wallpaper through, text and icons stay solid. Apps that are open change when reopened. Off brings back plain Adwaita."
            }

            // open Files windows keep the old look until Files restarts
            Row {
                visible: page.appsChanged && page.filesOpen
                spacing: 12

                HeaderButton {
                    label: "REOPEN FILES"
                    icon: String.fromCodePoint(0xF0450)
                    onActivated: page.reopenFiles()
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Files is open with the old look"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                }
            }

            Divider {}

            // ---------------- Terminal ----------------
            SectionHead {
                text: "TERMINAL"
                hint: page.termDetected
            }

            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF018D)
                label: "Match terminal colours"
                checked: page.termEnabled
                available: page.termLoaded && !termSet.running
                onToggled: page.setTerm(!page.termEnabled)
            }

            Slider {
                width: parent.width
                visible: page.termEnabled
                label: "Terminal opacity  " + Math.round(page.termOpacity * 100) + "%"
                icon: "◐"
                tint: Theme.accent
                value: (page.termOpacity - 0.30) / 0.70

                onSliding: function(v) {
                    page.termOpacity = 0.30 + v * 0.70
                    termOpacityDebounce.restart()
                }

                onSettled: function(v) {
                    page.termOpacity = 0.30 + v * 0.70
                    termOpacityDebounce.stop()
                    page.saveTermOpacity()
                }
            }

            Slider {
                width: parent.width
                visible: page.termEnabled && page.termColours
                label: "Terminal padding  " + page.termPadding + "px"
                icon: "▣"
                tint: Theme.accent
                value: page.termPadding / 40

                onSliding: function(v) {
                    var next = Math.round(v * 40)
                    if (next !== page.termPadding) {
                        page.termPadding = next
                        termPaddingDebounce.restart()
                    }
                }

                onSettled: function(v) {
                    page.termPadding = Math.round(v * 40)
                    termPaddingDebounce.stop()
                    page.saveTermPadding()
                }
            }

            ToggleRow {
                width: parent.width
                visible: page.termEnabled
                icon: String.fromCodePoint(0xF00B5)
                label: "Background blur"
                checked: page.termBlur
                available: !termBlurProc.running
                onToggled: page.setTermBlur(!page.termBlur)
            }

            Slider {
                width: parent.width
                visible: page.termEnabled && page.termBlur
                label: "Blur strength  " + page.termBlurStrength
                icon: "≋"
                tint: Theme.accent
                value: (page.termBlurStrength - 1) / 9

                onSliding: function(v) {
                    page.termBlurStrength = Math.round(1 + v * 9)
                    termStrengthDebounce.restart()
                }

                onSettled: function(v) {
                    page.termBlurStrength = Math.round(1 + v * 9)
                    termStrengthDebounce.stop()
                    page.saveTermBlurStrength()
                }
            }

            Note {
                text: page.termStatus !== ""
                    ? page.termStatus
                    : "Background, palette, cursor and selection follow the accent; with fish, command colours do too. Blur is done by Hyprland, so it works with any terminal, and shows when opacity is below 100%. The first time, open a new terminal window. Off restores everything."
            }
        }
    }
}
