#!/bin/sh
# SUPER + W: index the pictures in the wallpaper folder (config.json
# "wallpaper.folder", default your Documents folder), then open the picker.
# Pressed again while the picker is open, it closes it.

dir="$(cd "$(dirname "$0")" && pwd)"
qml="$(dirname "$dir")/wallpaper.qml"

# already open: close it (a void IPC call that reached it prints nothing)
out="$(timeout 1 qs -p "$qml" ipc call wallpaper hide 2>&1)" && [ -z "$out" ] && exit 0

settings="$(python3 "$dir/index.py")" || exit 1
count="$(printf '%s' "$settings" | jq -r '.count')"

if [ "${count:-0}" = 0 ]; then
    folder="$(printf '%s' "$settings" | jq -r '.folder')"
    # never wait on a missing notification daemon
    timeout 3 notify-send "Wallpaper" "No pictures found in $folder" 2>/dev/null
    exit 0
fi

YAKUSHI_WALLPAPER="$settings" exec qs -n -p "$qml"
