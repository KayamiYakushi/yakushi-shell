#!/bin/sh
# toggle-settings.sh          Open or close Settings (SUPER + I).
# toggle-settings.sh <page>   Open Settings on that page (e.g. tasks), or
#                             switch an open Settings to it.

shell="$(dirname "$0")/yakushi-shell.sh"

if [ -n "$1" ]; then
    exec sh "$shell" ipc settings open "$1"
else
    exec sh "$shell" ipc settings toggle
fi
