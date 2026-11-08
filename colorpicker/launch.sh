#!/bin/sh
# SUPER + SHIFT + C: the colour picker. Each screen is captured once (grim),
# so what you point at holds still; the pictures live in a private folder in
# $XDG_RUNTIME_DIR (memory, not disk) and are deleted when the picker closes.
# Pressed again while the picker is open, it closes it.

dir="$(cd "$(dirname "$0")" && pwd)"
qml="$(dirname "$dir")/colorpicker.qml"

# already open: close it (a void IPC call that reached it prints nothing)
out="$(timeout 1 qs -p "$qml" ipc call colorpicker hide 2>&1)" && [ -z "$out" ] && exit 0

for tool in grim wl-copy; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        package="$tool"
        [ "$tool" = wl-copy ] && package=wl-clipboard
        echo "yakushi: the colour picker needs $tool (sudo pacman -S $package)" >&2
        exit 1
    fi
done

run="${XDG_RUNTIME_DIR:?}/yakushi"
mkdir -p -m 700 "$run" || exit 1
shots="$(mktemp -d "$run/colorpicker.XXXXXX")" || exit 1     # 0700
trap 'rm -rf "$shots"' EXIT
trap 'exit 130' INT TERM HUP

# every screen at once; PNG without compression is the quickest to write
for name in $(hyprctl monitors -j | jq -r '.[].name'); do
    case "$name" in
        ''|*[!A-Za-z0-9._-]*) continue ;;
    esac
    grim -t png -l 0 -o "$name" "$shots/$name.png" &
done
wait

# the screens that were captured; none: nothing to pick from, nothing opens
screens=""
for file in "$shots"/*.png; do
    [ -s "$file" ] && screens="$screens $(basename "$file" .png)"
done
if [ -z "$screens" ]; then
    echo "yakushi: the colour picker could not capture the screen" >&2
    exit 1
fi

YAKUSHI_COLORPICKER_SHOTS="$shots" YAKUSHI_COLORPICKER_SCREENS="${screens# }" qs -n -p "$qml"
