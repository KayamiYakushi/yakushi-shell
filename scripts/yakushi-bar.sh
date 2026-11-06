#!/bin/sh
# Start / stop the Yakushi top bar.
#
#   yakushi-bar.sh start     Start the bar.
#   yakushi-bar.sh stop      Stop the bar.
#   yakushi-bar.sh toggle    Stop if running, start otherwise.
#   yakushi-bar.sh restart   Stop, then start.
#
# The bar's settings live in ~/.config/quickshell/yakushi-topbar.local.json.

here="$(cd "$(dirname "$0")" && pwd)"
state="$HOME/.config/quickshell/yakushi-topbar.local.json"
island_qml="$here/../topbar-shell.qml"
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$(id -u)}/yakushi"
pid_file="$runtime_root/topbar.pid"
log_file="$runtime_root/topbar.log"       # your private runtime folder, not /tmp

mkdir -p -m 700 "$runtime_root"

# the bar's pid, only if that process really is the bar (a pid number can be
# reused by another program after the bar has gone)
island_pid() {
    [ -r "$pid_file" ] || return 1
    pid="$(cat "$pid_file" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    grep -qa -- "topbar-shell.qml" "/proc/$pid/cmdline" 2>/dev/null && echo "$pid"
}

running() {
    island_pid >/dev/null
}

start() {
    running && return 0
    # First run: write the defaults so the bar has a file to watch.
    [ -e "$state" ] ||
        python3 "$here/yakushi-topbarctl.py" init >/dev/null 2>&1
    setsid qs -n -p "$island_qml" >"$log_file" 2>&1 </dev/null &
    printf '%s\n' "$!" >"$pid_file"
}

stop() {
    pid="$(island_pid)" && kill "$pid" 2>/dev/null
    rm -f "$pid_file"
}

case "${1:-start}" in
    start)   start ;;
    stop)    stop ;;
    toggle)  if running; then stop; else start; fi ;;
    restart) stop; sleep 0.2; start ;;
    *)
        printf 'Usage: %s start|stop|toggle|restart\n' "$0" >&2
        exit 2
        ;;
esac
