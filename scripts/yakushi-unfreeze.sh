#!/bin/sh
# SUPER + CTRL + Escape: for when the top bar, Settings or a pop-up stops
# answering. Ends every Quickshell of yours at once (and rofi, if it is
# stuck too), then starts the top bar again. Your windows and apps
# are not touched. A single Hyprland shortcut runs it, so it works even
# while Quickshell itself is frozen.
uid="$(id -u)"
for name in qs quickshell rofi; do
    pkill -KILL -u "$uid" -x "$name" 2>/dev/null
done
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$uid}/yakushi"
rm -f "$runtime_root/shell.pid"
sleep 0.3
exec sh "$(dirname "$0")/yakushi-shell.sh" start
