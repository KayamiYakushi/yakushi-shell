import Quickshell
import QtQuick

// Screen-share picker, started by scripts/share-picker.sh (yakushi share-picker) for
// xdg-desktop-portal-hyprland. Quits as soon as a choice is made.
ShellRoot {
    SharePicker {}
}
