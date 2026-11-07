#!/bin/sh
# Screen-share picker for xdg-desktop-portal-hyprland
# (screencopy:custom_picker_binary = yakushi-share-picker in hypr/xdph.conf).
#
# xdph reads the choice from our stdout. The Quickshell picker writes it to
# a private file; it is printed from here once the picker has closed.
# Nothing printed = the share request is cancelled.

export QT_QPA_PLATFORMTHEME=qt6ct
export QT_STYLE_OVERRIDE=Fusion
export QT_QUICK_CONTROLS_STYLE=Fusion

self="$(readlink -f -- "$0")" || exit 1
picker_qml="$(cd -- "$(dirname -- "$self")/.." && pwd -P)/share-picker-shell.qml"
case "${XDG_RUNTIME_DIR:-}" in /*) ;; *) echo "share-picker: XDG_RUNTIME_DIR is not set" >&2; exit 1 ;; esac
runtime_root="$XDG_RUNTIME_DIR/yakushi"
log_file="$runtime_root/share-picker.log"

mkdir -p -m 700 "$runtime_root"
out="$(mktemp "$runtime_root/share-pick.XXXXXX")" || exit 1
trap 'rm -f "$out"' EXIT INT TERM

# open on the monitor that has the focus
focused="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null)"

YAKUSHI_PICK_OUT="$out" YAKUSHI_PICK_SCREEN="$focused" \
    qs -n -p "$picker_qml" </dev/null >"$log_file" 2>&1

choice="$(head -n 1 "$out")"
case "$choice" in
    "[SELECTION]"*) printf '%s\n' "$choice" ;;
esac
