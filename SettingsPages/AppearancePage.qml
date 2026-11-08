import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page


    property var hostWindow: null
    readonly property string homeDir: Paths.home

    property var presets: [
        { name: "MONO",    accent: "#ffffff" },
        { name: "RED",     accent: "#ff003c" },
        { name: "SAKURA",  accent: "#ff7a9d" },
        { name: "AMBER",   accent: "#ffb000" },
        { name: "MATCHA",  accent: "#9ccc65" },
        { name: "MINT",    accent: "#3ee6b5" },
        { name: "CYAN",    accent: "#00d4ff" },
        { name: "OCEAN",   accent: "#4d8dff" },
        { name: "VIOLET",  accent: "#9d7bff" },
        { name: "ORCHID",  accent: "#e070ff" }
    ]

    // ---- launcher animation (scripts/yakushi-launchctl.py)
    property bool launcherLoaded: false
    property int launcherAnim: 480
    property bool clipboardOn: true
    property string clipboardNote: ""

    function setClipboard(on) {
        clipboardOn = on
        clipboardSet.command = ["python3", Paths.script("yakushi-launchctl.py"), "clipboard", on ? "on" : "off"]
        clipboardSet.running = true
    }

    Process {
        id: clipboardSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.clipboardNote = data.message || ""
                    if (typeof data.clipboard === "boolean")
                        page.clipboardOn = data.clipboard
                } catch (e) {
                }
            }
        }
    }

    function saveLauncherAnim() {
        if (launcherSet.running) {
            launcherSave.restart()          // try again once the last save is done
            return
        }
        launcherSet.command = ["python3", Paths.script("yakushi-launchctl.py"), "set", "animation", String(launcherAnim)]
        launcherSet.running = true
    }

    Process {
        id: launcherGet

        running: true
        command: ["python3", Paths.script("yakushi-launchctl.py"), "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok && typeof data.animationMs === "number")
                        page.launcherAnim = data.animationMs
                    if (data.ok && typeof data.clipboard === "boolean")
                        page.clipboardOn = data.clipboard
                } catch (e) {
                }
                page.launcherLoaded = true
            }
        }
    }

    Process {
        id: launcherSet
    }

    Timer {
        id: launcherSave
        interval: 150
        onTriggered: page.saveLauncherAnim()
    }

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
        page.loadWindow()
        termGet.command = ["python3", page.termHelperPath(), "status"]
        termGet.running = true
        appsGet.running = true
    }

    // ------------------------------------------------------------------
    // Windows: gaps and corners (yakushi-windowctl.py)
    // ------------------------------------------------------------------
    property bool windowLoaded: false
    property int gapsOut: 3
    property int gapsIn: 3
    property int rounding: 8
    property int lastRadius: 8
    property bool shadow: true
    property int shadowSize: 8
    property bool border: false
    property int borderSize: 2
    property string borderColor: "accent"
    property string windowStatus: ""
    property var windowQueue: []

    function windowHelperPath() {
        return Paths.script("yakushi-windowctl.py")
    }

    function loadWindow() {
        windowGet.command = ["python3", windowHelperPath(), "get"]
        windowGet.running = true
    }

    function sendWindow(key, value) {
        windowQueue = windowQueue.filter(function(item) { return item[0] !== key })
        windowQueue.push([key, String(value)])
        pumpWindow()
    }

    function pumpWindow() {
        if (windowSet.running || windowQueue.length === 0 || homeDir === "")
            return
        var next = windowQueue.shift()
        windowSet.command = ["python3", windowHelperPath(), "set", next[0], next[1]]
        windowSet.running = true
    }

    function setRounding(value) {
        rounding = value
        if (value > 0)
            lastRadius = value
        sendWindow("rounding", value)
    }

    Process {
        id: windowGet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    if (data.ok) {
                        page.gapsOut = data.gaps_out
                        page.gapsIn = data.gaps_in
                        page.rounding = data.rounding
                        if (data.rounding > 0)
                            page.lastRadius = data.rounding
                        page.shadow = data.shadow === true
                        page.shadowSize = data.shadow_size || 8
                        page.border = data.border === true
                        page.borderSize = data.border_size || 2
                        page.borderColor = data.border_color || "accent"
                        page.windowLoaded = true
                    } else {
                        page.windowStatus = data.message
                    }
                } catch (e) {
                    page.windowStatus = "Could not read window settings."
                }
            }
        }
    }

    Process {
        id: windowSet

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.windowStatus = data.ok ? "" : data.message
                } catch (e) {
                    page.windowStatus = "Could not save window settings."
                }
            }
        }

        onRunningChanged: if (!running) page.pumpWindow()
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
    property string termName: ""
    property bool termColours: true

    function readTermSettings(data) {
        if (typeof data.opacity === "number")
            page.termOpacity = data.opacity
        if (typeof data.blur === "boolean")
            page.termBlur = data.blur
        if (typeof data.blurStrength === "number")
            page.termBlurStrength = data.blurStrength
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
            ? "Detected: " + parts.join("  ·  ")
            : "No supported terminal found (kitty, alacritty, foot, ghostty) and no fish."
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
                    page.termDetected = "Could not detect the terminal."
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

    // ------------------------------------------------------------------
    // Accent
    // ------------------------------------------------------------------
    function hexOf(c) {
        function h(v) {
            var s = Math.round(v * 255).toString(16)
            return s.length < 2 ? "0" + s : s
        }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    function applyCustom(raw) {
        var value = raw.trim()
        if (value.charAt(0) !== "#")
            value = "#" + value
        if (/^#[0-9a-fA-F]{6}$/.test(value)) {
            Theme.accent = value.toLowerCase()
            return true
        }
        return false
    }

    component SectionLabel: Text {
        textFormat: Text.PlainText
        color: Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 11
        font.letterSpacing: 2
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.line
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
            spacing: 18

            PageTitle {
                width: parent.width
                title: "APPEARANCE"
            }

            Divider {}

            // ---------------- Apps: light / dark ----------------
            Row {
                spacing: 10

                SectionLabel { text: "APPS" }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "GTK 3 · GTK 4 · Files · Firefox"
                    color: Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
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

            Text {
                textFormat: Text.PlainText
                visible: page.schemeNote !== ""
                width: parent.width
                text: page.schemeNote
                wrapMode: Text.WordWrap
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
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
                visible: page.appsColours
                label: "File manager opacity  " + Math.round(page.filesOpacity * 100) + "%"
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

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: page.appsStatus !== ""
                    ? page.appsStatus
                    : "GTK apps (Files, Celluloid, Meld...) take the shell's surfaces and accent. The opacity is for the file manager only (Files, Nemo, Thunar): its background lets the wallpaper through, text and icons stay solid. Apps that are open change when reopened (REOPEN FILES does it for Files). Off brings back plain Adwaita dark."
                wrapMode: Text.WordWrap
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
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
                    font.pixelSize: 9
                }
            }

            Divider {}

            SectionLabel { text: "ACCENT" }

            Grid {
                id: presetGrid

                width: parent.width
                columns: 5
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: page.presets

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool selected: Qt.colorEqual(Theme.accent, modelData.accent)

                        width: (presetGrid.width - 4 * presetGrid.columnSpacing) / 5
                        height: 40
                        color: Theme.card
                        border.width: 1
                        border.color: selected
                            ? modelData.accent
                            : (presetMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 12
                                height: 12
                                color: modelData.accent
                                border.width: 1
                                border.color: Theme.inkSoft
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: modelData.name
                                color: parent.parent.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: presetMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.accent = modelData.accent
                        }
                    }
                }
            }

            // Custom colour: any #rrggbb
            Item {
                width: parent.width
                height: 30

                Text {
                    id: customIcon

                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF03D8)
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 14
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: customIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Custom colour"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Rectangle {
                    id: hexField

                    property bool invalid: false

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 132
                    height: 26
                    color: Theme.groove
                    border.width: 1
                    border.color: invalid
                        ? Theme.alert
                        : (hexInput.activeFocus ? Theme.accent : Theme.line)

                    Rectangle {
                        id: swatch

                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        color: Theme.accent
                    }

                    TextInput {
                        id: hexInput

                        anchors.left: swatch.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.hexOf(Theme.accent)
                        maximumLength: 7
                        color: Theme.ink
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        selectByMouse: true

                        onTextEdited: hexField.invalid = false

                        onAccepted: {
                            hexField.invalid = !page.applyCustom(text)
                            if (!hexField.invalid)
                                focus = false
                        }

                        onActiveFocusChanged: {
                            if (!activeFocus) {
                                hexField.invalid = false
                                text = Qt.binding(function() { return page.hexOf(Theme.accent) })
                            }
                        }
                    }
                }
            }

            Divider {}

            SectionLabel { text: "GLASS" }

            Slider {
                width: parent.width
                label: "PANEL OPACITY  "
                    + Math.round(Theme.glass * 100)
                    + "%"
                icon: "◐"
                tint: Theme.accent
                value: (Theme.glass - 0.40) / 0.60

                onSliding: function(v) {
                    Theme.glass = 0.40 + (v * 0.60)
                }

                onSettled: function(v) {
                    Theme.glass = 0.40 + (v * 0.60)
                }
            }

            Divider {}

            // ---------------- Launcher ----------------
            SectionLabel { text: "LAUNCHER" }

            Slider {
                width: parent.width
                opacity: page.launcherLoaded ? 1 : 0.35
                enabled: page.launcherLoaded
                label: "Opening animation  " + (page.launcherAnim > 0 ? page.launcherAnim + " ms" : "off")
                icon: String.fromCodePoint(0xF0954)
                tint: Theme.accent
                value: page.launcherAnim / 1000

                // in steps of 20 ms
                onSliding: function(v) {
                    var next = Math.round(v * 50) * 20
                    if (next !== page.launcherAnim) {
                        page.launcherAnim = next
                        launcherSave.restart()
                    }
                }

                onSettled: function(v) {
                    page.launcherAnim = Math.round(v * 50) * 20
                    launcherSave.stop()
                    page.saveLauncherAnim()
                }
            }

            // open the launcher to see the new speed
            Rectangle {
                width: tryLabel.implicitWidth + 28
                height: 26
                color: tryMouse.containsMouse ? Theme.tint(Theme.accent, 0.12) : Theme.card
                border.width: 1
                border.color: tryMouse.containsMouse ? Theme.accent : Theme.line

                Text {
                    id: tryLabel

                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "TRY IT"
                    color: tryMouse.containsMouse ? Theme.ink : Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }

                MouseArea {
                    id: tryMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([Paths.shell + "/bin/yakushi", "launcher"])
                }
            }

            // Clipboard history: off = nothing recorded, the old history deleted
            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF0147)
                label: "Clipboard history"
                checked: page.clipboardOn
                available: page.launcherLoaded && !clipboardSet.running

                onToggled: page.setClipboard(!page.clipboardOn)
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: page.clipboardNote !== "" ? page.clipboardNote
                    : page.clipboardOn ? "Keeps what you copy, passwords too (SUPER + SHIFT + V). Off: nothing is kept and the old history is deleted."
                    : "Off: nothing you copy is kept."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 11
            }

            Divider {}

            // ---------------- Windows ----------------
            SectionLabel { text: "WINDOWS" }

            Slider {
                width: parent.width
                opacity: page.windowLoaded ? 1 : 0.35
                label: "Screen edge gap  " + page.gapsOut + "px"
                icon: String.fromCodePoint(0xF00CE)
                tint: Theme.accent
                value: page.gapsOut / 30

                onSliding: function(v) {
                    var next = Math.round(v * 30)
                    if (next !== page.gapsOut) {
                        page.gapsOut = next
                        page.sendWindow("gaps_out", next)
                    }
                }

                onSettled: function(v) {
                    page.gapsOut = Math.round(v * 30)
                    page.sendWindow("gaps_out", page.gapsOut)
                }
            }

            Slider {
                width: parent.width
                opacity: page.windowLoaded ? 1 : 0.35
                label: "Gap between windows  " + page.gapsIn + "px"
                icon: String.fromCodePoint(0xF00D2)
                tint: Theme.accent
                value: page.gapsIn / 20

                onSliding: function(v) {
                    var next = Math.round(v * 20)
                    if (next !== page.gapsIn) {
                        page.gapsIn = next
                        page.sendWindow("gaps_in", next)
                    }
                }

                onSettled: function(v) {
                    page.gapsIn = Math.round(v * 20)
                    page.sendWindow("gaps_in", page.gapsIn)
                }
            }

            // Corners: cut (Hyprland rounding with rounding_power 1, set in
            // hyprland.lua) or sharp
            Row {
                width: parent.width
                spacing: 12
                opacity: page.windowLoaded ? 1 : 0.35

                Repeater {
                    model: [
                        { key: "rounded", name: "CUT" },
                        { key: "sharp", name: "SHARP" }
                    ]

                    delegate: Rectangle {
                        id: cornerCard

                        required property var modelData
                        readonly property bool selected: modelData.key === "sharp"
                            ? page.rounding === 0
                            : page.rounding > 0

                        width: (body.width - 12) / 2
                        height: 48
                        color: Theme.card
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (cornerMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.tFast }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 12

                            // Tiny window showing the corner style
                            CutBox {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 18
                                cut: cornerCard.modelData.key === "sharp" ? 0 : 5
                                strokeWidth: 1.5
                                stroke: cornerCard.selected ? Theme.accent : Theme.inkSoft
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                text: cornerCard.modelData.name
                                color: cornerCard.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.letterSpacing: 2
                            }
                        }

                        MouseArea {
                            id: cornerMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: page.windowLoaded
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (cornerCard.selected)
                                    return
                                page.setRounding(cornerCard.modelData.key === "sharp" ? 0 : page.lastRadius)
                            }
                        }
                    }
                }
            }

            Slider {
                width: parent.width
                visible: page.rounding > 0
                label: "Corner cut  " + page.rounding + "px"
                icon: String.fromCodePoint(0xF0607)
                tint: Theme.accent
                value: (page.rounding - 1) / 19

                onSliding: function(v) {
                    var next = 1 + Math.round(v * 19)
                    if (next !== page.rounding)
                        page.setRounding(next)
                }

                onSettled: function(v) {
                    page.setRounding(1 + Math.round(v * 19))
                }
            }

            // ---------------- Shadow ----------------
            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF0637)
                label: "Window shadow"
                checked: page.shadow
                available: page.windowLoaded

                onToggled: {
                    page.shadow = !page.shadow
                    page.sendWindow("shadow", page.shadow ? "on" : "off")
                }
            }

            Slider {
                width: parent.width
                visible: page.shadow
                label: "Shadow size  " + page.shadowSize + "px"
                icon: String.fromCodePoint(0xF1854)
                tint: Theme.accent
                value: (page.shadowSize - 2) / 38

                onSliding: function(v) {
                    var next = 2 + Math.round(v * 38)
                    if (next !== page.shadowSize) {
                        page.shadowSize = next
                        page.sendWindow("shadow_size", next)
                    }
                }

                onSettled: function(v) {
                    page.shadowSize = 2 + Math.round(v * 38)
                    page.sendWindow("shadow_size", page.shadowSize)
                }
            }

            // ---------------- Border ----------------
            ToggleRow {
                width: parent.width
                icon: String.fromCodePoint(0xF00C9)
                label: "Window border"
                checked: page.border
                available: page.windowLoaded

                onToggled: {
                    page.border = !page.border
                    page.sendWindow("border", page.border ? "on" : "off")
                }
            }

            Slider {
                width: parent.width
                visible: page.border
                label: "Border width  " + page.borderSize + "px"
                icon: String.fromCodePoint(0xF08A1)
                tint: Theme.accent
                value: (page.borderSize - 1) / 5

                onSliding: function(v) {
                    var next = 1 + Math.round(v * 5)
                    if (next !== page.borderSize) {
                        page.borderSize = next
                        page.sendWindow("border_size", next)
                    }
                }

                onSettled: function(v) {
                    page.borderSize = 1 + Math.round(v * 5)
                    page.sendWindow("border_size", page.borderSize)
                }
            }

            // Border colour: follow the accent, or any #rrggbb
            Item {
                width: parent.width
                height: 30
                visible: page.border

                Text {
                    id: borderColourIcon

                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: String.fromCodePoint(0xF0266)
                    color: Theme.accent
                    font.family: Theme.glyphs
                    font.pixelSize: 14
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: borderColourIcon.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Border colour"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        readonly property bool selected: page.borderColor === "accent"

                        width: accentLabel.implicitWidth + 34
                        height: 26
                        color: selected ? Theme.tint(Theme.accent, 0.16) : "transparent"
                        border.width: 1
                        border.color: selected
                            ? Theme.accent
                            : (accentMouse.containsMouse ? Theme.lineHot : Theme.line)

                        Row {
                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10
                                height: 10
                                color: Theme.accent
                            }

                            Text {
                                id: accentLabel

                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                text: "ACCENT"
                                color: parent.parent.selected ? Theme.ink : Theme.inkSoft
                                font.family: Theme.mono
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                        }

                        MouseArea {
                            id: accentMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                page.borderColor = "accent"
                                page.sendWindow("border_color", "accent")
                            }
                        }
                    }

                    Rectangle {
                        id: borderHexField

                        readonly property bool selected: page.borderColor !== "accent"
                        property bool invalid: false

                        width: 132
                        height: 26
                        color: Theme.groove
                        border.width: 1
                        border.color: invalid
                            ? Theme.alert
                            : (borderHexInput.activeFocus || selected ? Theme.accent : Theme.line)

                        Rectangle {
                            id: borderSwatch

                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            color: page.borderColor === "accent" ? Theme.inkMute : page.borderColor
                        }

                        TextInput {
                            id: borderHexInput

                            anchors.left: borderSwatch.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.borderColor === "accent" ? "" : page.borderColor
                            maximumLength: 7
                            color: Theme.ink
                            selectionColor: Theme.tint(Theme.accent, 0.4)
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            selectByMouse: true

                            Text {
                                textFormat: Text.PlainText
                                visible: borderHexInput.text === "" && !borderHexInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: "#rrggbb"
                                color: Theme.inkMute
                                font: borderHexInput.font
                            }

                            onTextEdited: borderHexField.invalid = false

                            onAccepted: {
                                var value = text.trim()
                                if (value.charAt(0) !== "#")
                                    value = "#" + value
                                if (/^#[0-9a-fA-F]{6}$/.test(value)) {
                                    page.borderColor = value.toLowerCase()
                                    page.sendWindow("border_color", page.borderColor)
                                    focus = false
                                } else {
                                    borderHexField.invalid = true
                                }
                            }
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Shadows cost a little GPU time; turn them off for the lightest setup."
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Divider {}

            // ---------------- Terminal ----------------
            SectionLabel { text: "TERMINAL" }

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

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: page.termDetected
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: page.termStatus !== ""
                    ? page.termStatus
                    : "Background, palette, cursor and selection follow the accent; with fish, command colours do too. Blur is done by Hyprland, so it works with any terminal, and shows when opacity is below 100%. The first time, open a new terminal window. Off restores everything."
                wrapMode: Text.WordWrap
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }


            Text {
                textFormat: Text.PlainText
                visible: page.windowStatus !== ""
                width: parent.width
                text: page.windowStatus
                color: Theme.inkSoft
                font.family: Theme.mono
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}
