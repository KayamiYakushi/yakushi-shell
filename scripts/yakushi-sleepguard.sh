#!/bin/bash
# Lock before sleep: whatever puts the machine to sleep (the lid, a
# `systemctl suspend` typed anywhere, hibernate), it wakes up locked.
#
# Started by the shell (shell.qml) and ends with it. How it works, with
# nothing polling while you work:
#   - it holds a logind "delay" inhibitor, so a sleep request waits for us
#     (at most InhibitDelayMaxSec, 5 s by default);
#   - logind announces the sleep on D-Bus (PrepareForSleep true); we start
#     the lock, wait until every screen is covered, then let go of the
#     inhibitor and the machine sleeps;
#   - on wake-up (PrepareForSleep false) we take a new inhibitor.
#
# Usage: yakushi-sleepguard.sh <path to bin/yakushi>
# Needs gdbus (glib2) and systemd-inhibit (systemd); both are in core.

set -u

yakushi="${1:?usage: yakushi-sleepguard.sh <yakushi>}"
run="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/yakushi"
mkdir -p -m 700 "$run"

# One guard per session. Every child closes fds 6-8 (the inhibitor, the
# monitor, this lock): a child that kept one would hold the inhibitor or
# the guard lock long after it should.
exec 8>"$run/sleep-guard.flock" || exit 1
flock -n 8 || exit 0

command -v gdbus >/dev/null && command -v systemd-inhibit >/dev/null || exit 1

monitor_pid=""

hold() {
    # The inhibitor lives as long as `cat` reads our fd 6; closing fd 6
    # ends it. (Re-opening fd 6 closes the previous one first.)
    exec 6> >(exec systemd-inhibit --what=sleep --mode=delay \
        --who=Yakushi --why="Locking the screen first" cat >/dev/null 6>&- 7<&- 8>&-)
}

release() {
    exec 6>&- 2>/dev/null
}

now_ms() {
    echo $(( ${EPOCHREALTIME/[.,]/} / 1000 ))
}

lock_screen() {
    # the lock is its own process; `yakushi lock` returns at unlock, so it
    # runs detached and we only wait until it reports every screen covered
    setsid "$yakushi" lock >/dev/null 2>&1 </dev/null 6>&- 7<&- 8>&- &
    deadline=$(( $(now_ms) + 4000 ))    # stay under logind's 5 s delay
    while [ "$(now_ms)" -lt "$deadline" ]; do
        "$yakushi" lock status >/dev/null 2>&1 6>&- 7<&- 8>&- && return 0
        sleep 0.05
    done
    return 1
}

cleanup() {
    release
    [ -n "$monitor_pid" ] && kill "$monitor_pid" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

# If D-Bus goes away the monitor ends; try again a few times, then give up
# (the shell's next start brings the guard back).
for attempt in 1 2 3 4 5; do
    # pdeathsig: the monitor ends with us even when we are killed outright
    # (it only notices a missing reader at the next sleep; until then an
    # orphan would linger, one per shell restart)
    exec 7< <(exec setpriv --pdeathsig TERM gdbus monitor --system --dest org.freedesktop.login1 \
        --object-path /org/freedesktop/login1 2>/dev/null 6>&- 8>&-)
    monitor_pid=$!
    hold
    while IFS= read -r line <&7; do
        case $line in
            *".PrepareForSleep (true,)"*)  lock_screen; release ;;
            *".PrepareForSleep (false,)"*) hold ;;
        esac
    done
    release
    exec 7<&-
    sleep 2
done
exit 1
