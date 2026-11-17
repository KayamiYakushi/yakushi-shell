import QtQuick
import "../"

// The month under the date (hover it): today lit in the accent, the days of
// the months around it faint. The arrows or the wheel go to other months;
// the month's name brings today back. The week starts where the locale
// says (Monday in most of the world).
Item {
    id: cal

    required property date today
    property bool open: false

    // months away from today's month
    property int offset: 0
    onOpenChanged: if (!open) offset = 0

    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property int firstWeekday: Qt.locale().firstDayOfWeek % 7      // 0 = Sunday
    readonly property var english: Qt.locale("en_US")

    readonly property int cellW: Math.floor(width / 7)
    readonly property int cellH: 24
    readonly property real wantedHeight: head.height + 12 + weekdays.height + 4 + 6 * cellH

    // the 42 days on the grid, from the week the month starts in
    readonly property var days: {
        var lead = (month.getDay() - firstWeekday + 7) % 7
        var list = []
        for (var i = 0; i < 42; i++)
            list.push(new Date(month.getFullYear(), month.getMonth(), 1 - lead + i))
        return list
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    // black or white, whichever reads on the accent
    readonly property color onAccent: 0.299 * Theme.accent.r + 0.587 * Theme.accent.g + 0.114 * Theme.accent.b > 0.55
        ? "#0a0a0a" : "#f5f5f5"

    WheelHandler {
        onWheel: event => cal.offset += event.angleDelta.y > 0 ? -1 : 1
    }

    // ---- month, year, arrows
    Item {
        id: head

        width: parent.width
        height: 20

        MouseArea {
            id: titleMouse

            width: title.width
            height: parent.height
            hoverEnabled: true
            cursorShape: cal.offset !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: cal.offset = 0

            Row {
                id: title

                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.baseline: parent.verticalCenter
                    anchors.baselineOffset: 4
                    textFormat: Text.PlainText
                    text: cal.english.standaloneMonthName(cal.month.getMonth(), Locale.LongFormat).toUpperCase()
                    color: titleMouse.containsMouse && cal.offset !== 0 ? Theme.accent : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 4
                }

                Text {
                    anchors.baseline: parent.verticalCenter
                    anchors.baselineOffset: 4
                    textFormat: Text.PlainText
                    text: cal.month.getFullYear()
                    color: Theme.inkSoft
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 8
                textFormat: Text.PlainText
                text: (cal.month.getMonth() + 1) + "月"
                color: Theme.inkMute
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 10
            }

            Repeater {
                model: [[-1, 0xF0141], [1, 0xF0142]]

                delegate: Item {
                    id: arrow

                    required property var modelData

                    width: 20
                    height: 20

                    CutBox {
                        anchors.fill: parent
                        cut: 5
                        cutTopLeft: false
                        cutBottomRight: false
                        fill: arrowMouse.containsMouse ? Theme.tint(Theme.ink, 0.08) : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String.fromCodePoint(arrow.modelData[1])
                        color: arrowMouse.containsMouse ? Theme.accent : Theme.inkSoft
                        font.family: Theme.glyphs
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: arrowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cal.offset += arrow.modelData[0]
                    }
                }
            }
        }
    }

    // ---- MO TU WE ...
    Row {
        id: weekdays

        y: head.height + 12
        height: 14

        Repeater {
            model: 7

            delegate: Text {
                required property int index
                readonly property int weekday: (cal.firstWeekday + index) % 7

                width: cal.cellW
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: cal.english.dayName(weekday, Locale.ShortFormat).slice(0, 2).toUpperCase()
                color: weekday === 0 || weekday === 6 ? Theme.tint(Theme.accent, 0.8) : Theme.inkMute
                font.family: Theme.mono
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1
            }
        }
    }

    // ---- the days
    Grid {
        y: weekdays.y + weekdays.height + 4
        columns: 7

        Repeater {
            model: cal.days

            delegate: Item {
                id: day

                required property var modelData
                readonly property bool inMonth: modelData.getMonth() === cal.month.getMonth()
                readonly property bool isToday: cal.sameDay(modelData, cal.today)
                readonly property bool weekend: modelData.getDay() === 0 || modelData.getDay() === 6

                width: cal.cellW
                height: cal.cellH

                CutBox {
                    visible: day.isToday
                    anchors.centerIn: parent
                    width: 26
                    height: 20
                    cut: 6
                    cutTopLeft: false
                    cutBottomRight: false
                    fill: Theme.accent
                }

                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: day.modelData.getDate()
                    color: day.isToday ? cal.onAccent
                        : !day.inMonth ? Theme.tint(Theme.ink, 0.22)
                        : day.weekend ? Theme.inkSoft : Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.bold: day.isToday
                }
            }
        }
    }
}
