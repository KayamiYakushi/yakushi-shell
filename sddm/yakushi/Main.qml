import QtQuick
import QtQuick.Effects
import SddmComponents 2.0

// The Yakushi login screen (SDDM). It is the lock screen's twin, so logging
// in and unlocking look like one thing: the wallpaper dimmed and softly
// blurred, the clock at the top, your picture, name and the password field
// in the middle, what is typed shown as slanted marks. Cut corners, mono
// type, the accent on what has focus; nothing rounded.
//
// The greeter runs as the sddm user and cannot read your home, so what it
// shares with the shell (accent, 12/24 h clock, your picture) is copied into
// the theme by Settings -> Login Screen -> MATCH THE SHELL, as
// theme.conf.user (SDDM reads it over theme.conf) and avatar.png.
Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "black"

    // ---- the theme's settings (theme.conf, theme.conf.user)
    function setting(key) {
        var v = config[key]
        return v === undefined || v === null ? "" : String(v)
    }

    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(setting("accent")) ? setting("accent") : "#ffffff"
    readonly property bool clock24: setting("clock24") === "true"
    readonly property string avatarUser: setting("avatarUser")

    // ---- the shell's tokens (Theme.qml), as far as this screen needs them
    readonly property color ink: "#ffffff"
    readonly property color inkSoft: "#a6a6a6"
    readonly property color inkMute: "#707070"
    readonly property color card: "#0e0e0e"
    readonly property color lineHot: "#2b2b2b"
    readonly property color alert: "#ff2e4d"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string jp: "Noto Sans CJK JP"
    readonly property int tFast: 120
    readonly property int tMid: 220
    readonly property int tSlow: 380

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // ---- state
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false
    property bool failed: false
    property bool leaving: false
    property bool shown: false
    property string message: ""
    property int failures: 0
    property date now: new Date()

    readonly property int userCount: users.count
    readonly property int sessionCount: sessions.count
    readonly property var user: userCount > 0 && users.itemAt(userIndex) ? users.itemAt(userIndex) : null
    readonly property string userName: user ? user.name : nameInput.text.trim()
    readonly property string sessionName: sessionCount > 0 && sessions.itemAt(sessionIndex) ? sessions.itemAt(sessionIndex).name : ""
    readonly property bool typedName: userCount === 0      // no user list: type the name

    function cycleUser(step) {
        if (userCount < 2 || busy)
            return
        userIndex = (userIndex + step + userCount) % userCount
        failed = false
        message = ""
        passwordInput.text = ""
        passwordInput.forceActiveFocus()
    }

    function cycleSession(step) {
        if (sessionCount < 2 || busy)
            return
        sessionIndex = (sessionIndex + step + sessionCount) % sessionCount
    }

    function submit() {
        if (busy)
            return
        if (userName === "") {
            nameInput.forceActiveFocus()
            return
        }
        busy = true
        failed = false
        message = ""
        sddm.login(userName, passwordInput.text, sessionIndex)
    }

    // the lists SDDM gives: kept as invisible items, read by index
    Repeater {
        id: users

        model: userModel

        Item {
            required property string name
            required property string realName
            required property string icon
            required property bool needsPassword
        }
    }

    Repeater {
        id: sessions

        model: sessionModel

        Item {
            required property string name
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var d = new Date()
            if (d.getMinutes() !== root.now.getMinutes() || d.getHours() !== root.now.getHours())
                root.now = d
        }
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.busy = false
            root.failed = true
            root.failures += 1
            if (root.message === "")
                root.message = "Wrong password"
            passwordInput.text = ""
            passwordInput.forceActiveFocus()
        }

        function onLoginSucceeded() {
            root.leaving = true
        }

        function onInformationMessage(text) {
            root.message = text
        }
    }

    Component.onCompleted: {
        shown = true
        if (typedName)
            nameInput.forceActiveFocus()
        else
            passwordInput.forceActiveFocus()
    }

    // ------------------------------------------------------------------
    // Background
    // ------------------------------------------------------------------
    Image {
        id: wall

        anchors.fill: parent
        visible: GraphicsInfo.api === GraphicsInfo.Software && status === Image.Ready
        source: root.setting("background") !== "" ? Qt.resolvedUrl(root.setting("background")) : ""
        sourceSize.width: root.width
        sourceSize.height: root.height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }

    // blurred like the lock screen (no shader with the software renderer:
    // then the plain picture above shows instead)
    MultiEffect {
        anchors.fill: parent
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        source: wall
        opacity: wall.status === Image.Ready ? 1 : 0
        blurEnabled: true
        blur: 0.55
        blurMax: 40
        autoPaddingEnabled: false

        Behavior on opacity {
            NumberAnimation { duration: root.tSlow }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.55
    }

    // ------------------------------------------------------------------
    // Content
    // ------------------------------------------------------------------
    Item {
        id: content

        anchors.fill: parent
        opacity: root.shown && !root.leaving ? 1 : 0
        scale: root.shown && !root.leaving ? 1 : 0.985

        Behavior on opacity {
            NumberAnimation { duration: root.tMid; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: root.tMid; easing.type: Easing.OutCubic }
        }

        // clicking anywhere gives the field the keys back
        MouseArea {
            anchors.fill: parent
            onPressed: (root.typedName && root.userName === "" ? nameInput : passwordInput).forceActiveFocus()
        }

        // ---- clock and date
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(root.height * 0.14)
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: Qt.formatTime(root.now, root.clock24 ? "HH:mm" : "h:mm")
                color: root.ink
                font.family: root.mono
                font.pixelSize: 96
                font.weight: Font.Light
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: Qt.locale().toString(root.now, "dddd  ·  d MMMM")
                color: root.inkSoft
                font.family: root.mono
                font.pixelSize: 16
                font.letterSpacing: 1
            }
        }

        // ---- picture, name, password
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(root.height * 0.06)
            spacing: 0

            // picture in the cut-corner outline
            Item {
                id: picture

                anchors.horizontalCenter: parent.horizontalCenter
                width: 104
                height: 104

                // the picture Settings copied for that user, else the one
                // the system knows (SDDM's stock face counts as none)
                readonly property string source: {
                    if (!root.user)
                        return ""
                    if (root.avatarUser !== "" && root.avatarUser === root.user.name)
                        return Qt.resolvedUrl("avatar.png")
                    var icon = root.user.icon || ""
                    if (icon === "" || /\/sddm\/faces\/\.face\.icon$/.test(icon))
                        return ""
                    return icon.indexOf("/") === 0 ? "file://" + icon : icon
                }
                readonly property bool has: photo.status === Image.Ready

                Image {
                    id: photo

                    anchors.fill: parent
                    visible: false
                    source: picture.source
                    sourceSize.width: 208
                    sourceSize.height: 208
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                CutBox {
                    id: photoMask

                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    fill: "white"
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: picture.has
                    source: photo
                    maskEnabled: true
                    maskSource: photoMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                // no picture: a quiet initial
                CutBox {
                    anchors.fill: parent
                    visible: !picture.has
                    fill: root.tint(root.card, 0.85)
                }

                Text {
                    anchors.centerIn: parent
                    visible: !picture.has
                    textFormat: Text.PlainText
                    text: root.userName !== "" ? root.userName.charAt(0).toUpperCase() : String.fromCodePoint(0xF0004)
                    color: root.inkSoft
                    font.family: root.mono
                    font.pixelSize: 40
                }

                CutBox {
                    anchors.fill: parent
                    stroke: root.accent
                    strokeWidth: 2
                }
            }

            Item { width: 1; height: 18 }

            // the name; with more than one user, slanted arrows (or Up / Down) switch
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 320
                height: 24
                visible: !root.typedName

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 72
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: root.user ? (root.user.realName || root.user.name) : ""
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 16
                    font.letterSpacing: 1
                }

                Repeater {
                    model: root.userCount > 1 ? [-1, 1] : []

                    Item {
                        required property int modelData

                        x: modelData < 0 ? 0 : parent.width - width
                        width: 24
                        height: 24

                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: parent.modelData < 0 ? String.fromCodePoint(0xF0141) : String.fromCodePoint(0xF0142)
                            color: arrowMouse.containsMouse ? root.accent : root.inkMute
                            font.family: root.mono
                            font.pixelSize: 18

                            Behavior on color {
                                ColorAnimation { duration: root.tFast }
                            }
                        }

                        MouseArea {
                            id: arrowMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycleUser(parent.modelData)
                        }
                    }
                }
            }

            // no user list (hidden users): the name is typed, in the same field shape
            Item {
                id: nameField

                anchors.horizontalCenter: parent.horizontalCenter
                width: 320
                height: 48
                visible: root.typedName

                CutBox {
                    anchors.fill: parent
                    fill: Qt.rgba(0, 0, 0, 0.5)
                    stroke: nameInput.activeFocus ? root.accent : root.lineHot
                    strokeWidth: 1.5

                    Behavior on stroke {
                        ColorAnimation { duration: root.tFast }
                    }
                }

                TextInput {
                    id: nameInput

                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    readOnly: root.busy
                    maximumLength: 64
                    color: root.ink
                    selectionColor: root.tint(root.accent, 0.4)
                    selectedTextColor: root.ink
                    font.family: root.mono
                    font.pixelSize: 16
                    font.letterSpacing: 1
                    text: root.typedName ? userModel.lastUser : ""
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

                    KeyNavigation.tab: passwordInput
                    Keys.onReturnPressed: passwordInput.forceActiveFocus()
                    Keys.onEnterPressed: passwordInput.forceActiveFocus()
                }

                Text {
                    anchors.centerIn: parent
                    visible: nameInput.text === ""
                    textFormat: Text.PlainText
                    text: "Name"
                    color: root.inkMute
                    font.family: root.mono
                    font.pixelSize: 14
                    font.letterSpacing: 1
                }
            }

            Item { width: 1; height: root.typedName ? 12 : 26 }

            // the password field
            Item {
                id: field

                anchors.horizontalCenter: parent.horizontalCenter
                width: 320
                height: 48

                readonly property bool caps: keyboard.capsLock === true
                property real shake: 0

                transform: Translate { x: field.shake }

                SequentialAnimation {
                    id: shakeAnim

                    NumberAnimation { target: field; property: "shake"; to: -10; duration: 45 }
                    NumberAnimation { target: field; property: "shake"; to: 9; duration: 70 }
                    NumberAnimation { target: field; property: "shake"; to: -6; duration: 60 }
                    NumberAnimation { target: field; property: "shake"; to: 3; duration: 50 }
                    NumberAnimation { target: field; property: "shake"; to: 0; duration: 40 }
                }

                Connections {
                    target: root

                    function onFailuresChanged() {
                        shakeAnim.restart()
                    }
                }

                CutBox {
                    anchors.fill: parent
                    fill: Qt.rgba(0, 0, 0, 0.5)
                    stroke: root.failed ? root.alert
                        : passwordInput.activeFocus ? root.accent
                        : root.lineHot
                    strokeWidth: 1.5

                    Behavior on stroke {
                        ColorAnimation { duration: root.tFast }
                    }
                }

                // The real input: invisible, it only holds the keys. What
                // it holds is shown as slanted marks, never as text.
                TextInput {
                    id: passwordInput

                    anchors.fill: parent
                    opacity: 0
                    echoMode: TextInput.Password
                    readOnly: root.busy
                    maximumLength: 512
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
                    persistentSelection: false
                    selectByMouse: false

                    onTextChanged: {
                        if (text !== "" && root.failed) {
                            root.failed = false
                            root.message = ""
                        }
                    }

                    KeyNavigation.backtab: nameInput
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: text = ""
                    Keys.onUpPressed: root.cycleUser(-1)
                    Keys.onDownPressed: root.cycleUser(1)

                    // no copy, cut or paste out of (or into) the field
                    Keys.onPressed: function(event) {
                        if (event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut)
                                || event.matches(StandardKey.Paste) || event.matches(StandardKey.SelectAll))
                            event.accepted = true
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: passwordInput.text === "" && !root.busy
                    textFormat: Text.PlainText
                    text: root.user && !root.user.needsPassword ? "Press Enter" : "Password"
                    color: root.inkMute
                    font.family: root.mono
                    font.pixelSize: 14
                    font.letterSpacing: 1
                }

                // Caps Lock on: a quiet tag at the field's right end
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    opacity: field.caps && !root.busy ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: root.tFast }
                    }

                    CutBox {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 12
                        fill: root.accent
                        cut: 5
                        cutTopLeft: false
                        cutBottomRight: false
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "CAPS"
                        color: root.inkSoft
                        font.family: root.mono
                        font.pixelSize: 12
                        font.letterSpacing: 2
                    }
                }

                // one slanted mark per character (at most what fits)
                // (fewer, a little left, while the CAPS tag is shown)
                Row {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: field.caps ? -32 : 0
                    spacing: 5
                    visible: !root.busy

                    Repeater {
                        model: Math.min(passwordInput.text.length, field.caps ? 18 : 24)

                        CutBox {
                            width: 7
                            height: 14
                            fill: root.ink
                            cut: 7
                            cutTopLeft: false
                            cutBottomRight: false
                        }
                    }
                }

                // checking: one mark sweeping along the field
                Item {
                    anchors.fill: parent
                    anchors.margins: 14
                    visible: root.busy
                    clip: true

                    CutBox {
                        id: sweep

                        width: 36
                        height: 6
                        anchors.verticalCenter: parent.verticalCenter
                        fill: root.accent
                        cut: 6
                        cutTopLeft: false
                        cutBottomRight: false

                        NumberAnimation on x {
                            running: root.busy
                            loops: Animation.Infinite
                            from: -sweep.width
                            to: field.width - 28
                            duration: 900
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            Item { width: 1; height: 14 }

            // the message line keeps its height, so nothing jumps
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 420
                height: 20
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: root.message
                color: root.failed ? root.alert : root.inkSoft
                font.family: root.mono
                font.pixelSize: 13
            }
        }

        // ---- bottom left: the session (a choice only when there is one)
        Chip {
            anchors.left: parent.left
            anchors.leftMargin: 48
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            visible: root.sessionCount > 0
            enabled: root.sessionCount > 1 && !root.busy
            glyph: String.fromCodePoint(0xF0379)
            label: root.sessionName
            sub: "セッション"
            onClicked: root.cycleSession(1)
        }

        // ---- bottom right: restart, shut down
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 48
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            spacing: 12

            Chip {
                visible: sddm.canReboot
                glyph: String.fromCodePoint(0xF0709)
                label: "RESTART"
                sub: "再起動"
                onClicked: sddm.reboot()
            }

            Chip {
                visible: sddm.canPowerOff
                glyph: String.fromCodePoint(0xF0425)
                label: "SHUT DOWN"
                sub: "電源オフ"
                onClicked: sddm.powerOff()
            }
        }
    }

    // a quiet button: cut corners, mono caps, a Japanese sub-label; hover =
    // the accent outline and a light tint (calm, never a full fill)
    component Chip: Item {
        id: chip

        property string glyph: ""
        property string label: ""
        property string sub: ""
        signal clicked

        readonly property bool hot: enabled && chipMouse.containsMouse

        implicitWidth: chipRow.implicitWidth + 32
        implicitHeight: 48
        width: implicitWidth
        height: implicitHeight

        CutBox {
            anchors.fill: parent
            cut: 7
            fill: chip.hot ? root.tint(root.accent, 0.10) : Qt.rgba(0, 0, 0, 0.35)
            stroke: chip.hot ? root.accent : root.lineHot
            strokeWidth: 1

            Behavior on stroke {
                ColorAnimation { duration: root.tFast }
            }
        }

        Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: chip.glyph
                color: chip.hot ? root.ink : root.inkSoft
                font.family: root.mono
                font.pixelSize: 16
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    textFormat: Text.PlainText
                    text: chip.label.toUpperCase()
                    color: chip.hot ? root.ink : root.inkSoft
                    font.family: root.mono
                    font.pixelSize: 12
                    font.letterSpacing: 2
                }

                Text {
                    textFormat: Text.PlainText
                    text: chip.sub
                    color: root.inkMute
                    font.family: root.jp
                    font.pixelSize: 10
                }
            }
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: chip.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
}
