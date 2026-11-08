import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "../KeybindsSearch.js" as KeybindsSearch

Item {
    id: page

    property var hostWindow: null
    clip: true

    readonly property string homeDir: Paths.home
    property string statusText: "Loading keybinds..."
    property bool statusError: false
    property var allBinds: []
    // the system's languages (Settings search reads them the same way)
    readonly property var searchLanguages: KeybindsSearch.languages(function(name) { return Quickshell.env(name) })
    property string loadedText: ""
    // what is typed in the search field (Settings can open the page with a question)
    property alias query: searchInput.text

    function helperPath() {
        return Paths.script("yakushi-keybindctl.py")
    }

    function refresh() {
        if (homeDir === "" || listProc.running)
            return

        listProc.command = ["python3", helperPath(), "list"]
        listProc.running = true
    }

    function applyBinding(bindId, combo) {
        if (setProc.running)
            return

        statusText = "Applying " + combo + "..."
        statusError = false

        setProc.command = [
            "python3",
            helperPath(),
            "set",
            bindId,
            combo
        ]
        setProc.running = true
    }

    function setBindingEnabled(bindId, wanted) {
        if (toggleProc.running)
            return

        statusText = wanted ? "Enabling shortcut..." : "Disabling shortcut..."
        statusError = false

        toggleProc.command = [
            "python3",
            helperPath(),
            wanted ? "enable" : "disable",
            bindId
        ]
        toggleProc.running = true
    }

    // What you typed -> the shortcuts it means (KeybindsSearch.js): words in
    // your languages ("how do I open the launcher"), or keys ("super + c").
    function rebuildFiltered() {
        var found = KeybindsSearch.find(allBinds, searchInput.text, searchLanguages)
        bindsModel.clear()

        for (var i = 0; i < found.rows.length; ++i) {
            var b = found.rows[i]
            bindsModel.append({
                bindId: b.id,
                category: b.category,
                label: b.label,
                combo: b.combo,
                danger: !!b.danger,
                bindEnabled: !!b.bindEnabled,
                viewOnly: !!b.readonly,
                inApp: !!b.inApp,
                source: b.source || "",
                best: found.best === b
            })
        }

        if (found.mode === "all") {
            statusText = loadedText
            statusError = false
        } else if (found.rows.length === 0) {
            statusText = "Nothing matches. Try other words, or the keys themselves (super + c)."
            statusError = false
        } else if (found.best) {
            statusText = "→  " + found.best.label + ":  " + found.best.combo.split(" + ")
                .map(KeybindsSearch.prettyKey).join(" + ")
            statusError = false
        } else {
            statusText = found.rows.length + (found.rows.length === 1 ? " shortcut uses" : " shortcuts use") + " these keys."
            statusError = false
        }

        bindList.positionViewAtBeginning()
    }

    ListModel {
        id: bindsModel
    }

    // first load
    Component.onCompleted: {
        page.refresh()
    }

    Process {
        id: listProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    var apps = KeybindsSearch.appRows()
                    page.loadedText = data.length + " shortcuts, " + apps.length + " keys inside Yakushi's windows."
                    page.allBinds = data.concat(apps)
                    page.rebuildFiltered()
                } catch (e) {
                    page.statusText = "Could not parse keybind list."
                    page.statusError = true
                }
            }
        }
    }

    Process {
        id: setProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim() === ""
                        ? "Keybind update failed."
                        : text.trim()
                    page.statusError = true
                }

                page.refresh()
            }
        }
    }

    Process {
        id: toggleProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim() === ""
                        ? "Keybind toggle failed."
                        : text.trim()
                    page.statusError = true
                }

                page.refresh()
            }
        }
    }

    Process {
        id: restoreProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    page.statusText = result.message
                    page.statusError = !result.ok
                } catch (e) {
                    page.statusText = text.trim()
                    page.statusError = true
                }

                page.refresh()
            }
        }
    }

    Item {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30

        PageTitle {
            anchors.left: parent.left
            anchors.right: titleActions.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            title: "KEYBINDS"
        }

        Row {
            id: titleActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            HeaderButton {
                label: "RELOAD"
                icon: String.fromCodePoint(0xF0450)
                onActivated: page.refresh()
            }

            HeaderButton {
                label: "UNDO LAST"
                icon: String.fromCodePoint(0xF054C)

                onActivated: {
                    if (restoreProc.running)
                        return
                    restoreProc.command = ["python3", page.helperPath(), "restore"]
                    restoreProc.running = true
                }
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: headerRow.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }

    Rectangle {
        id: searchBox
        anchors.top: divider.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        height: 38
        color: Theme.card
        border.width: 1
        border.color: searchInput.activeFocus
            ? Theme.accent
            : Theme.line

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0349)
            color: searchInput.activeFocus ? Theme.accent : Theme.inkSoft
            font.family: Theme.glyphs
            font.pixelSize: 14
        }

        Text {
            textFormat: Text.PlainText
            visible: searchInput.text === ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 36
            text: KeybindsSearch.placeholder(page.searchLanguages)
            color: Theme.inkMute
            font.family: Theme.mono
            font.pixelSize: 10
        }

        TextInput {
            id: searchInput
            anchors.fill: parent
            anchors.leftMargin: 36
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            selectionColor: Theme.accent
            selectedTextColor: Theme.surface
            font.family: Theme.mono
            font.pixelSize: 10
            clip: true

            onTextChanged: page.rebuildFiltered()
        }
    }

    Text {
        id: statusLine
        textFormat: Text.PlainText
        anchors.top: searchBox.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: 16
        text: page.statusText
        color: page.statusError ? Theme.alert
            : searchInput.text !== "" && bindsModel.count > 0 && bindsModel.get(0).best ? Theme.accent
            : Theme.inkSoft
        font.family: Theme.mono
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Text {
        id: helpLine
        textFormat: Text.PlainText
        anchors.top: statusLine.bottom
        anchors.topMargin: 3
        anchors.left: parent.left
        anchors.right: parent.right
        height: 16
        text: "Ask in your own words, or type keys. The pencil edits a shortcut (Enter saves, Esc cancels); the switch turns one off."
        color: Theme.inkMute
        font.family: Theme.mono
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    ScrollHint {
        flick: bindList
    }

    ListView {
        id: bindList
        anchors.top: helpLine.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: 6
        model: bindsModel
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3000
        cacheBuffer: 250

        delegate: Rectangle {
            id: bindRow

            required property string bindId
            required property string category
            required property string label
            required property string combo
            required property bool danger
            required property bool bindEnabled
            required property bool viewOnly
            required property bool inApp
            required property string source
            required property bool best

            property bool editing: false
            // alternatives ("Esc / Right click"), each a list of keys
            readonly property var groups: combo.split(" / ").map(function(alt) {
                return alt.split(" + ").map(function(k) { return KeybindsSearch.prettyKey(k.trim()) })
                    .filter(function(k) { return k !== "" })
            })

            width: ListView.view.width
            height: 50
            color: rowHover.hovered || editing ? Theme.tint(Theme.ink, 0.035) : Theme.card
            border.width: 1
            border.color: editing || best
                ? Theme.accent
                : danger ? Theme.tint(Theme.alert, 0.45)
                : rowHover.hovered ? Theme.lineHot : Theme.line

            Behavior on color {
                ColorAnimation { duration: Theme.tFast }
            }

            HoverHandler {
                id: rowHover
            }

            // the answer to what was asked
            Rectangle {
                visible: bindRow.best
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                color: Theme.accent
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: keyArea.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                opacity: bindRow.bindEnabled ? 1.0 : 0.45

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: bindRow.label
                    color: bindRow.danger ? Theme.alert : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: (bindRow.best ? "BEST MATCH  ·  " : "") + bindRow.category.toUpperCase()
                        + (bindRow.source !== "" ? "  ·  " + bindRow.source : "")
                    color: bindRow.best ? Theme.accent : Theme.inkMute
                    font.family: Theme.mono
                    font.pixelSize: 8
                    font.letterSpacing: 1
                }
            }

            // Keycaps (or the editor while editing)
            Item {
                id: keyArea

                anchors.right: bindRow.viewOnly ? readonlyTag.left : enableSwitch.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: bindRow.editing ? 210 : keycaps.implicitWidth
                height: 28
                opacity: bindRow.bindEnabled || bindRow.editing ? 1.0 : 0.45

                Row {
                    id: keycaps

                    visible: !bindRow.editing
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: bindRow.groups

                        delegate: Row {
                            id: group

                            required property var modelData
                            required property int index

                            spacing: 4

                            Text {
                                visible: group.index > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "/"
                                color: Theme.inkMute
                                font.family: Theme.mono
                                font.pixelSize: 9
                            }

                            Repeater {
                                model: group.modelData

                                delegate: Rectangle {
                                    required property string modelData

                                    width: Math.max(26, capText.implicitWidth + 14)
                                    height: 24
                                    color: Theme.tint(Theme.ink, 0.06)
                                    border.width: 1
                                    border.color: Theme.tint(Theme.ink, 0.10)

                                    // subtle key "depth"
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 1
                                        height: 2
                                        color: Theme.tint("#000000", 0.35)
                                    }

                                    Text {
                                        id: capText

                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        text: parent.modelData
                                        color: Theme.ink
                                        font.family: Theme.mono
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: bindRow.editing
                    anchors.fill: parent
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.accent

                    TextInput {
                        id: comboInput

                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: bindRow.combo
                        readOnly: !bindRow.editing
                        color: Theme.ink
                        selectionColor: Theme.tint(Theme.accent, 0.45)
                        font.family: Theme.mono
                        font.pixelSize: 10
                        clip: true

                        onAccepted: {
                            if (!bindRow.editing)
                                return

                            page.applyBinding(bindRow.bindId, text)
                            bindRow.editing = false
                        }

                        Keys.onEscapePressed: {
                            text = bindRow.combo
                            bindRow.editing = false
                            focus = false
                        }
                    }
                }
            }

            // shortcuts that are not keybinds.lua's: shown, not edited here
            Text {
                id: readonlyTag

                visible: bindRow.viewOnly
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 86
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: bindRow.inApp ? "IN APP" : "SET ELSEWHERE"
                color: Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 8
                font.letterSpacing: 1
            }

            Switch {
                id: enableSwitch

                visible: !bindRow.viewOnly
                anchors.right: editButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                checked: bindRow.bindEnabled
                onToggled: page.setBindingEnabled(bindRow.bindId, !bindRow.bindEnabled)
            }

            IconButton {
                id: editButton

                visible: !bindRow.viewOnly
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                glyph: String.fromCodePoint(bindRow.editing ? 0xF012C : 0xF03EB)

                onActivated: {
                    if (!bindRow.editing) {
                        bindRow.editing = true
                        comboInput.forceActiveFocus()
                        comboInput.selectAll()
                        return
                    }

                    page.applyBinding(bindRow.bindId, comboInput.text)
                    bindRow.editing = false
                }
            }
        }
    }
}
