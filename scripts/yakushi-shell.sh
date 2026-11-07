#!/bin/sh
# Start / stop the Yakushi shell (top bar, Settings, volume pill).
#
#   yakushi-shell.sh start          Start it unless it is already running.
#   yakushi-shell.sh stop           Stop it.
#   yakushi-shell.sh restart        Stop, then start.
#   yakushi-shell.sh running        Exit 0 if it is running.
#   yakushi-shell.sh ipc <args...>  Send an IPC call, starting the shell
#                                   first if needed (e.g. ipc settings toggle).

root="$(cd "$(dirname "$0")/.." && pwd)"
shell_qml="$root/shell.qml"
settings_qml="$root/settings.qml"
runtime_root="${XDG_RUNTIME_DIR:-/tmp/yakushi-$(id -u)}/yakushi"
pid_file="$runtime_root/shell.pid"
log_file="$runtime_root/shell.log"        # your private runtime folder, not /tmp

mkdir -p -m 700 "$runtime_root"

# the shell's pid, only if that process really is this shell (a pid number
# can be reused by another program after the shell has gone)
shell_pid() {
    [ -r "$pid_file" ] || return 1
    pid="$(cat "$pid_file" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    grep -qa -- "$shell_qml" "/proc/$pid/cmdline" 2>/dev/null && echo "$pid"
}

running() {
    shell_pid >/dev/null
}

# Settings runs as a child of the shell. If the shell went away (stopped or
# crashed) while Settings was open, close that leftover Settings too, so the
# next SUPER + I always gets a fresh one.
stop_settings() {
    timeout 2 qs kill -p "$settings_qml" >/dev/null 2>&1
}

start() {
    running && return 0
    stop_settings
    # Create the config (carrying over old settings) or upgrade it first, so
    # the shell finds a current file to watch.
    python3 "$root/scripts/yakushi-configctl.py" init >/dev/null 2>&1
    setsid qs -n -p "$shell_qml" >"$log_file" 2>&1 </dev/null &
    printf '%s\n' "$!" >"$pid_file"
}

stop() {
    pid="$(shell_pid)" || { rm -f "$pid_file"; stop_settings; return 0; }
    kill "$pid" 2>/dev/null
    # wait up to 2 s for it to go, so a restart never runs two at once
    i=0
    while [ "$i" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 0.1
        i=$((i + 1))
    done
    kill -9 "$pid" 2>/dev/null
    rm -f "$pid_file"
    stop_settings
}

call() {
    timeout 2 qs -p "$shell_qml" ipc call "$@" >/dev/null 2>&1
}

ipc() {
    call "$@" && return 0
    # not running (or not answering): start it and give it a moment to load
    running || start
    i=0
    while [ "$i" -lt 30 ]; do
        sleep 0.1
        call "$@" && return 0
        i=$((i + 1))
    done
    return 1
}

case "${1:-start}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; start ;;
    running) running ;;
    ipc)     shift; ipc "$@" ;;
    *)
        printf 'Usage: %s start|stop|restart|running|ipc <target> <function> [args]\n' "$0" >&2
        exit 2
        ;;
esac
