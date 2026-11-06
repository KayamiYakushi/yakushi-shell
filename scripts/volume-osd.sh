#!/bin/sh
# volume-osd.sh up|down|mute|show
# Changes the volume with wpctl, then shows the volume pill.

case "$1" in
    up)   wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ ;;   # never past 100 % (like the bar)
    down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    show) ;;
    *)    echo "usage: volume-osd.sh up|down|mute|show" >&2; exit 2 ;;
esac

exec sh "$(dirname "$0")/yakushi-shell.sh" ipc volumeOsd show
