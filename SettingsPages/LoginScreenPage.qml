import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page


    property var hostWindow: null
    readonly property string homeDir: Paths.home
    property url previewSource: ""
    property bool hasBackground: false
    property string statusMessage: ""

    // what the login screen shares with the shell, as it has it now
    property bool canSync: false
    property string loginAccent: ""        // "" = never matched (white)
    property bool loginClock24: false
    property url loginAvatar: ""
    readonly property bool matched: loginAccent !== ""
        && loginAccent.toLowerCase() === Theme.accent.toString().toLowerCase()
        && loginClock24 === (Config.topbar.clock24 === true)

    function helperPath() {
        return Paths.script("yakushi-sddmctl.py")
    }

    function loadState() {
        if (homeDir === "" || statusProc.running)
            return

        statusProc.command = ["python3", helperPath(), "status"]
        statusProc.running = true
    }

    // Changing the system's login screen needs your password: it is asked
    // right here (no dialog that could open behind Settings) and goes to
    // sudo through a pipe.
    property var pendingArgs: []       // ["set", <image>] or ["reset"], waiting for the password
    property var lastArgs: []
    property string secret: ""

    function ask(args) {
        if (rootProc.running)
            return
        pendingArgs = args
        statusMessage = ""
        passwordAsk.error = ""
        Qt.callLater(passwordAsk.open)
    }

    function runRoot(args, password) {
        lastArgs = args
        secret = password
        statusMessage = args[0] === "set" ? "Preparing the picture..."
            : args[0] === "sync" ? "Matching the shell..." : "Resetting..."
        rootProc.stdinEnabled = true
        rootProc.command = ["python3", helperPath(), "--password-stdin"].concat(args)
        rootProc.running = true
    }

    function setBackground(path) {
        ask(["set", path])
    }

    function resetBackground() {
        ask(["reset"])
    }

    function matchShell() {
        ask(["sync"])
    }

    function readLook(data) {
        if (data.accent !== undefined)
            page.loginAccent = data.accent || ""
        if (data.clock24 !== undefined)
            page.loginClock24 = data.clock24 === true
        if (data.avatar !== undefined)
            page.loginAvatar = data.avatar || ""
    }

    // first load
    Component.onCompleted: {
        page.loadState()
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    page.hasBackground = data.background === true
                    page.previewSource = data.preview || ""
                    page.canSync = data.canSync === true
                    page.readLook(data)
                    if (page.statusMessage === "")
                        page.statusMessage = data.message || ""
                } catch (e) {
                    page.statusMessage = "Could not read login screen state."
                }
            }
        }
    }

    Process {
        id: rootProc

        onStarted: {
            if (stdinEnabled) {
                rootProc.write(page.secret + "\n")
                page.secret = ""
                stdinEnabled = false
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                var setting = page.lastArgs[0] === "set"
                if (page.lastArgs[0] === "sync") {
                    try {
                        var look = JSON.parse(text)
                        if (look.wrongPassword) {
                            page.pendingArgs = page.lastArgs
                            page.statusMessage = ""
                            passwordAsk.error = "Wrong password. Try again."
                            Qt.callLater(passwordAsk.open)
                            return
                        }
                        page.statusMessage = look.message || (look.ok ? "Done." : "Could not match the shell.")
                        if (look.ok) {
                            page.readLook(look)
                            return
                        }
                    } catch (e) {
                        page.statusMessage = "Could not match the shell."
                    }
                    page.loadState()
                    return
                }
                try {
                    var data = JSON.parse(text)

                    if (data.wrongPassword) {
                        page.pendingArgs = page.lastArgs
                        page.statusMessage = ""
                        passwordAsk.error = "Wrong password. Try again."
                        Qt.callLater(passwordAsk.open)
                        return
                    }
                    page.statusMessage = data.message
                        || (data.ok ? "Done." : setting ? "Could not update login background." : "Could not reset login background.")
                    if (data.ok) {
                        page.hasBackground = setting
                        if (!setting)
                            page.previewSource = ""
                        return
                    }
                } catch (e) {
                    page.statusMessage = setting ? "Could not update login background." : "Could not reset login background."
                }
                page.loadState()           // show what the login screen really has
            }
        }
    }

    function chooseBackground() {
        if (!hostWindow)
            return

        hostWindow.openImagePicker(
            homeDir,
            Paths.pictures,
            function(path) {
                page.previewSource = "file://" + path.split("/").map(encodeURIComponent).join("/")
                page.setBackground(path)
            }
        )
    }

    Column {
        anchors.fill: parent
        spacing: 18

        PageTitle {
            width: parent.width
            title: "LOGIN SCREEN"
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.line
        }

        Text {
            textFormat: Text.PlainText
            text: "SDDM"
            color: Theme.inkSoft
            font.family: Theme.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        Rectangle {
            width: parent.width
            height: 290
            color: "#080808"
            border.width: 1
            border.color: Theme.line
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#181818" }
                    GradientStop { position: 1.0; color: "#030303" }
                }
            }

            Image {
                id: previewImage

                anchors.fill: parent
                source: page.previewSource
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: false
            }

            // blurred like the login itself (scaled down with the preview)
            MultiEffect {
                anchors.fill: parent
                visible: page.previewSource.toString() !== "" && previewImage.status === Image.Ready
                source: previewImage
                blurEnabled: true
                blur: 0.55
                blurMax: 12
                autoPaddingEnabled: false
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.55
            }

            // a small copy of the login screen, as it is now: the clock,
            // the picture in its cut outline, the field
            Item {
                id: mini

                anchors.fill: parent

                readonly property color accent: page.loginAccent !== "" ? page.loginAccent : "#ffffff"
                readonly property real k: height / 1080

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(mini.height * 0.12)
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: Qt.formatTime(new Date(), page.loginClock24 ? "HH:mm" : "h:mm")
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: Math.round(96 * mini.k * 1.3)
                        font.weight: Font.Light
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: Qt.locale().toString(new Date(), "dddd  ·  d MMMM")
                        color: Theme.inkSoft
                        font.family: Theme.mono
                        font.pixelSize: 8
                    }
                }

                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: Math.round(mini.height * 0.08)
                    spacing: 6

                    Item {
                        id: miniPicture

                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 40
                        height: 40

                        readonly property bool has: miniPhoto.status === Image.Ready

                        Image {
                            id: miniPhoto

                            anchors.fill: parent
                            visible: false
                            source: page.loginAvatar
                            sourceSize.width: 80
                            sourceSize.height: 80
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }

                        CutBox {
                            id: miniMask

                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            cut: 6
                            fill: "white"
                        }

                        MultiEffect {
                            anchors.fill: parent
                            visible: miniPicture.has
                            source: miniPhoto
                            maskEnabled: true
                            maskSource: miniMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }

                        CutBox {
                            anchors.fill: parent
                            visible: !miniPicture.has
                            cut: 6
                            fill: Theme.tint(Theme.card, 0.85)
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !miniPicture.has
                            textFormat: Text.PlainText
                            text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                            color: Theme.inkSoft
                            font.family: Theme.mono
                            font.pixelSize: 16
                        }

                        CutBox {
                            anchors.fill: parent
                            cut: 6
                            stroke: mini.accent
                            strokeWidth: 1.5
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: Quickshell.env("USER") || ""
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 9
                    }

                    CutBox {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 124
                        height: 20
                        cut: 5
                        fill: Qt.rgba(0, 0, 0, 0.5)
                        stroke: mini.accent
                        strokeWidth: 1
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    textFormat: Text.PlainText
                    text: page.hasBackground ? "CUSTOM BACKGROUND" : "PLAIN BLACK"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }
        }

        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                width: 200
                height: 38
                color: Theme.tint(Theme.accent, 0.10)
                border.width: 1
                border.color: Theme.accent

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "CHOOSE BACKGROUND"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.chooseBackground()
                }
            }

            Rectangle {
                width: 100
                height: 38
                color: "transparent"
                border.width: 1
                border.color: Theme.line
                opacity: page.hasBackground ? 1.0 : 0.45

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "RESET"
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: page.hasBackground
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: page.resetBackground()
                }
            }

            // accent, clock and picture from the shell (the greeter cannot read them itself)
            Rectangle {
                width: 170
                height: 38
                visible: page.canSync
                color: matchMouse.containsMouse && !page.matched ? Theme.tint(Theme.accent, 0.10) : "transparent"
                border.width: 1
                border.color: page.matched ? Theme.line : Theme.accent

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "MATCH THE SHELL"
                    color: page.matched ? Theme.inkSoft : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: matchMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.matchShell()
                }
            }
        }

        PasswordRow {
            id: passwordAsk

            width: parent.width
            visible: page.pendingArgs.length > 0
            label: page.pendingArgs[0] === "reset" ? "Your password, to reset the login background"
                 : page.pendingArgs[0] === "sync" ? "Your password, to give the login screen the shell's look"
                 : "Your password, to change the login background"
            action: page.pendingArgs[0] === "reset" ? "RESET" : page.pendingArgs[0] === "sync" ? "MATCH" : "SET"
            onAccepted: function(password) {
                var args = page.pendingArgs
                page.pendingArgs = []
                page.runRoot(args, password)
            }
            onCanceled: {
                page.pendingArgs = []
                page.statusMessage = "Cancelled. Nothing was changed."
                page.loadState()
            }
        }

        Note {
            text: page.statusMessage !== ""
                ? page.statusMessage
                : "Changes appear on the next SDDM login."
            color: Theme.inkSoft
        }

        Note {
            text: "Pictures are made into clean PNGs as you (never opened as root), then copied into the system SDDM theme with your password. Your files stay untouched. MATCH THE SHELL copies your accent, 12/24 h clock, profile picture and mouse cursor: the login screen cannot read your home. Press it again after you change one of them."
        }
    }
}
