#!/bin/sh
# Show / hide the Yakushi top bar (it lives inside the shell).
#
#   yakushi-bar.sh start     Show the bar (starting the shell if needed).
#   yakushi-bar.sh stop      Hide the bar.
#   yakushi-bar.sh toggle    Hide it if shown, show it otherwise.
#   yakushi-bar.sh restart   Restart the whole shell.

shell="$(dirname "$0")/yakushi-shell.sh"

case "${1:-start}" in
    start)   exec sh "$shell" ipc topbar show ;;
    stop)    sh "$shell" running && exec sh "$shell" ipc topbar hide ;;
    toggle)  exec sh "$shell" ipc topbar toggle ;;
    restart) exec sh "$shell" restart ;;
    *)
        printf 'Usage: %s start|stop|toggle|restart\n' "$0" >&2
        exit 2
        ;;
esac
