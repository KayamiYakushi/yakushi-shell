#!/usr/bin/env python3
"""Helper for the launcher (SUPER + Space).

Commands:
    used <desktop id>          Count one launch (apps you use often rise in
                               the list). Kept in ~/.local/state/yakushi/
                               launcher.json: counts only, nothing else.
    terminal <Exec line>       Run a terminal app (Terminal=true) in your
                               terminal: the one Hyprland's SUPER + Q opens
                               (`terminal = "..."` in hypr/hyprland.lua),
                               else $TERMINAL.

Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

import yakushi_paths as paths

STATE = paths.STATE / "launcher.json"
MAX_APPS = 500

# Terminals that take the program after -e (the rest take it as is).
DASH_E = {"alacritty", "ghostty", "xterm", "urxvt", "konsole", "xfce4-terminal", "st", "terminator", "tilix"}
DASH_DASH = {"gnome-terminal", "kgx", "ptyxis"}


def used(app_id: str) -> None:
    if not app_id or len(app_id) > 255 or "/" in app_id:
        raise SystemExit("bad app id")
    paths.STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = os.open(paths.STATE / ".launcher.lock", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = json.loads(STATE.read_text(encoding="utf-8"))
            counts = data.get("counts") if isinstance(data, dict) else None
        except (OSError, ValueError):
            counts = None
        if not isinstance(counts, dict):
            counts = {}
        counts = {k: v for k, v in counts.items() if isinstance(k, str) and isinstance(v, int) and v > 0}
        counts[app_id] = counts.get(app_id, 0) + 1
        # keep the file small: drop the least used
        if len(counts) > MAX_APPS:
            counts = dict(sorted(counts.items(), key=lambda kv: -kv[1])[:MAX_APPS])
        fd, tmp = tempfile.mkstemp(dir=paths.STATE, prefix=".launcher-", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump({"counts": counts}, handle)
        os.replace(tmp, STATE)
    finally:
        os.close(lock)


def your_terminal() -> list[str]:
    try:
        text = (paths.HYPR / "hyprland.lua").read_text(encoding="utf-8")
        m = re.search(r'^\s*terminal\s*=\s*"([^"]+)"', text, re.M)
        if m:
            return shlex.split(m.group(1))
    except (OSError, ValueError):
        pass
    if os.environ.get("TERMINAL"):
        return shlex.split(os.environ["TERMINAL"])
    raise SystemExit("no terminal found (hyprland.lua `terminal = ...` or $TERMINAL)")


def terminal(exec_line: str) -> None:
    # Desktop entry field codes (%f, %U, ...) mean nothing without files.
    argv = [a for a in shlex.split(exec_line) if not re.fullmatch(r"%[fFuUdDnNickvm]", a)]
    if not argv:
        raise SystemExit("empty Exec line")
    term = your_terminal()
    # skip launch wrappers to find the terminal's own name
    names = [os.path.basename(a) for a in term if not a.startswith("-") and "=" not in a]
    name = next((n for n in names if n not in ("uwsm", "app", "uwsm-app", "env", "setsid")), names[-1] if names else "")
    if name in DASH_E:
        cmd = term + ["-e"] + argv
    elif name in DASH_DASH:
        cmd = term + ["--"] + argv
    else:
        cmd = term + argv
    if shutil.which(cmd[0]) is None:
        raise SystemExit(f"terminal not found: {cmd[0]}")
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def main() -> None:
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "used":
        used(args[1])
    elif len(args) == 2 and args[0] == "terminal":
        terminal(args[1])
    else:
        raise SystemExit("Usage: used <desktop id> | terminal <Exec line>")


if __name__ == "__main__":
    main()
