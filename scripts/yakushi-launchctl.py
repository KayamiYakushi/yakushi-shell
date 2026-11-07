#!/usr/bin/env python3
"""Helper for the launcher (SUPER + Space).

Commands:
    get                        Print the launcher settings as JSON.
    set animation <0..1000>    Opening / closing time in ms (0 = none);
                               config.json "launcher.animationMs".
    import-rofi                Add rofi's launch counts (~/.cache/rofi3.druncache)
                               once, so the old order carries over.
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

import yakushi_config as config
import yakushi_paths as paths

STATE = paths.STATE / "launcher.json"
MAX_APPS = 500
ANIMATION_DEFAULT, ANIMATION_MAX = 480, 1000


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def settings(saved: dict) -> dict:
    ms = saved.get("animationMs")
    if not isinstance(ms, int) or isinstance(ms, bool):
        ms = ANIMATION_DEFAULT
    return {"animationMs": max(0, min(ANIMATION_MAX, ms))}


def set_animation(raw: str) -> None:
    try:
        ms = max(0, min(ANIMATION_MAX, int(raw)))
    except ValueError:
        emit({"ok": False, "message": "Use a whole number of milliseconds."})
        raise SystemExit(1)

    def change(saved: dict) -> dict:
        saved.update(settings(saved))
        saved["animationMs"] = ms
        return saved

    try:
        state = settings(config.update("launcher", change))
    except config.NewerConfig as error:
        emit({"ok": False, "message": str(error)})
        raise SystemExit(1)
    emit({"ok": True, **state, "message": "Launcher animation " + (f"{ms} ms." if ms else "off.")})


# Terminals that take the program after -e (the rest take it as is).
DASH_E = {"alacritty", "ghostty", "xterm", "urxvt", "konsole", "xfce4-terminal", "st", "terminator", "tilix"}
DASH_DASH = {"gnome-terminal", "kgx", "ptyxis"}


def valid_id(app_id: str) -> bool:
    return bool(app_id) and len(app_id) <= 255 and "/" not in app_id


def used(app_id: str) -> None:
    if not valid_id(app_id):
        raise SystemExit("bad app id")
    add_counts({app_id: 1})


def import_rofi() -> None:
    """rofi's history: `<count> <id>.desktop` per line."""
    found: dict[str, int] = {}
    try:
        text = (paths.CACHE_HOME / "rofi3.druncache").read_text(encoding="utf-8", errors="replace")
    except OSError:
        emit({"ok": False, "message": "No rofi history found."})
        raise SystemExit(1)
    for line in text.splitlines():
        parts = line.strip().split(" ", 1)
        if len(parts) == 2 and parts[0].isdigit():
            app_id = parts[1].strip().removesuffix(".desktop")
            if valid_id(app_id):
                found[app_id] = found.get(app_id, 0) + int(parts[0])
    add_counts(found)
    emit({"ok": True, "imported": len(found), "message": f"Took over the launch counts of {len(found)} apps from rofi."})


def add_counts(extra: dict[str, int]) -> None:
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
        for app_id, n in extra.items():
            counts[app_id] = counts.get(app_id, 0) + n
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
    if args == ["get"]:
        emit({"ok": True, **settings(config.section("launcher"))})
    elif len(args) == 3 and args[:2] == ["set", "animation"]:
        set_animation(args[2])
    elif args == ["import-rofi"]:
        import_rofi()
    elif len(args) == 2 and args[0] == "used":
        used(args[1])
    elif len(args) == 2 and args[0] == "terminal":
        terminal(args[1])
    else:
        raise SystemExit("Usage: get | set animation <ms> | import-rofi | used <desktop id> | terminal <Exec line>")


if __name__ == "__main__":
    main()
