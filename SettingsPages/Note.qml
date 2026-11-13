import QtQuick
import "../"

// A line or two of explanation under a group of settings, or what the last
// change did. Wraps to the page's width.
Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.WordWrap
    color: Theme.inkMute
    font.family: Theme.mono
    font.pixelSize: 10
    lineHeight: 1.35
}
