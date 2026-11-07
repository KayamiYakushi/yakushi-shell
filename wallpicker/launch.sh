#!/bin/sh
# SUPER + W: index the pictures in the wallpaper folder (config.json
# "wallpaper.folder", default your Documents folder), then open the picker.

dir="$(cd "$(dirname "$0")" && pwd)"
settings="$(python3 "$dir/index.py")" || exit 1
count="$(printf '%s' "$settings" | jq -r '.count')"

if [ "${count:-0}" = 0 ]; then
    folder="$(printf '%s' "$settings" | jq -r '.folder')"
    # never wait on a missing notification daemon
    timeout 3 notify-send "Wallpaper" "No pictures found in $folder" 2>/dev/null
    exit 0
fi

YAKUSHI_WALLPAPER="$settings" exec qs -p "$dir/shell.qml"
