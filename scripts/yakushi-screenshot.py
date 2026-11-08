#!/usr/bin/env python3
"""Screenshots, for the keybinds and Settings -> Programs -> Default Apps.

Commands:
    take area|window|screen   Take one. It always goes to the clipboard; it is
                              written to a file only while saving is on.
                              area   : drag a rectangle (Esc cancels)
                              window : the focused window
                              screen : the screen the cursor is on
    get                       Print the settings as JSON.
    set save on|off           Also keep every screenshot as a PNG file in
                              Pictures/Screenshots (off by default: nothing
                              piles up in your folders unless you ask for it).

Settings live in the "screenshots" section of ~/.config/yakushi/config.json.
The picture is kept in memory between grim and wl-copy: with saving off it
never touches the disk. Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import fcntl
import json
import os
import shutil
import subprocess
import sys
import time

import yakushi_config as config
import yakushi_paths as paths

DEFAULTS = {"save": False}


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def sanitize(saved: dict) -> dict:
    state = dict(DEFAULTS)
    if isinstance(saved.get("save"), bool):
        state["save"] = saved["save"]
    return state


def folder():
    return paths.user_dir("PICTURES") / "Screenshots"


def on_off(raw: str) -> bool:
    if raw in ("on", "true", "1"):
        return True
    if raw in ("off", "false", "0"):
        return False
    fail("Use on or off.")
    return False


# ---------------------------------------------------------------------------
# Taking one
# ---------------------------------------------------------------------------

def hyprctl(what: str):
    try:
        out = subprocess.run(["hyprctl", "-j", what], capture_output=True, text=True, timeout=3)
        return json.loads(out.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def window_geometry() -> str | None:
    """'x,y wxh' of the focused window, in layout coordinates (what grim -g
    takes), or None when nothing is focused."""
    win = hyprctl("activewindow")
    if not isinstance(win, dict):
        return None
    at, size = win.get("at"), win.get("size")
    if not (isinstance(at, list) and isinstance(size, list) and len(at) == 2 and len(size) == 2):
        return None
    if not all(number(v) for v in at + size) or size[0] <= 0 or size[1] <= 0:
        return None
    return f"{int(at[0])},{int(at[1])} {int(size[0])}x{int(size[1])}"


def focused_output() -> str | None:
    monitors = hyprctl("monitors")
    if not isinstance(monitors, list):
        return None
    for mon in monitors:
        if isinstance(mon, dict) and mon.get("focused") and isinstance(mon.get("name"), str):
            return mon["name"]
    return None


def capture(mode: str) -> bytes | None:
    """The PNG, or None when cancelled."""
    command = ["grim", "-t", "png"]
    if mode == "area":
        if not shutil.which("slurp"):
            fail("Area screenshots need slurp (sudo pacman -S slurp).")
        pick = subprocess.run(["slurp"], capture_output=True, text=True)
        area = pick.stdout.strip()
        if pick.returncode != 0 or not area:      # Esc / right click: cancelled
            return None
        command += ["-g", area]
    elif mode == "window":
        geometry = window_geometry()
        if geometry:
            command += ["-g", geometry]
        else:                                     # nothing focused: the screen
            mode = "screen"
    if mode == "screen":
        output = focused_output()
        if output:
            command += ["-o", output]
    command.append("-")
    shot = subprocess.run(command, capture_output=True, timeout=15)
    if shot.returncode != 0 or not shot.stdout:
        fail("grim could not take the screenshot: " + shot.stderr.decode(errors="replace").strip())
    return shot.stdout


def to_clipboard(png: bytes) -> None:
    # wl-copy stays in the background to serve the clipboard: give it no
    # pipes but stdin, or run() would wait on it until the next copy
    subprocess.run(["wl-copy", "--type", "image/png"], input=png,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)


def to_file(png: bytes) -> str:
    target_dir = folder()
    target_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%d_%H-%M-%S")
    for n in range(100):
        name = f"Screenshot_{stamp}{'' if n == 0 else f'_{n}'}.png"
        target = target_dir / name
        try:
            # O_EXCL: never overwrite a file that is already there
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o644)
        except FileExistsError:
            continue
        with os.fdopen(fd, "wb") as handle:
            handle.write(png)
        return str(target)
    fail("Could not pick a file name in " + str(target_dir))
    return ""


def take(mode: str) -> None:
    for tool in ("grim", "wl-copy"):
        if not shutil.which(tool):
            fail(f"Screenshots need {tool} (sudo pacman -S {'wl-clipboard' if tool == 'wl-copy' else tool}).")

    # one at a time: a key pressed twice must not stack two area pickers
    lock = os.open(paths.runtime() / "screenshot.lock", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        emit({"ok": True, "message": "Already taking one."})
        return

    png = capture(mode)
    if png is None:
        emit({"ok": True, "cancelled": True, "message": "Cancelled."})
        return
    to_clipboard(png)
    if sanitize(config.section("screenshots"))["save"]:
        emit({"ok": True, "saved": to_file(png), "message": "Copied and saved."})
    else:
        emit({"ok": True, "message": "Copied."})


# ---------------------------------------------------------------------------

def main() -> None:
    args = sys.argv[1:]

    if len(args) == 2 and args[0] == "take" and args[1] in ("area", "window", "screen"):
        take(args[1])

    elif args == ["get"]:
        emit({"ok": True, **sanitize(config.section("screenshots")), "folder": str(folder())})

    elif len(args) == 3 and args[:2] == ["set", "save"]:
        value = on_off(args[2])

        def apply(saved: dict) -> dict:
            state = sanitize(saved)
            state["save"] = value
            return state

        try:
            state = config.update("screenshots", apply)
        except config.NewerConfig as error:
            fail(str(error))
            return
        emit({"ok": True, **state, "folder": str(folder()),
              "message": "Screenshots are also saved." if value else "Screenshots go to the clipboard only."})

    else:
        fail("Usage: take area|window|screen | get | set save on|off")


if __name__ == "__main__":
    main()
