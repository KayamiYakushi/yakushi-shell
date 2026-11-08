#!/usr/bin/env python3
"""The wallpaper: which picture it is, and setting it.

    yakushi-wallpaperctl.py get          {"ok": true, "current": "/path/to/picture" | ""}
    yakushi-wallpaperctl.py set <file>   show it on every screen and remember it

The choice lives in the "wallpaper" section of ~/.config/yakushi/config.json
("current"), so the picker and the lock screen know it without asking the
program that draws it. Drawing is left to awww (official repos; under a
megabyte, and a process of its own, so the wallpaper stays when the shell
restarts): its daemon is started when it is not running. Before Yakushi
remembered the choice itself, awww did: `get` falls back to asking it once.

Runs only when called: no daemon of its own, no timers.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yakushi_config as config

EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def from_awww() -> str:
    """what awww shows (the first screen), for choices made before Yakushi kept them"""
    if not shutil.which("awww"):
        return ""
    try:
        out = subprocess.run(["awww", "query"], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""
    m = re.search(r"currently displaying: image: (/.+)$", out, re.M)
    return m.group(1).strip() if m else ""


def current() -> str:
    saved = config.section("wallpaper").get("current")
    if isinstance(saved, str) and saved and Path(saved).is_file():
        return saved
    return from_awww()


def awww_running() -> bool:
    try:
        return subprocess.run(["awww", "query"], capture_output=True, timeout=2).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def show(picture: str) -> str:
    """'' when awww took it, else why not"""
    if not shutil.which("awww"):
        return "awww is not installed (sudo pacman -S awww): the choice is saved, nothing is drawn."
    if not awww_running():
        subprocess.Popen(["awww-daemon"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(30):
            time.sleep(0.1)
            if awww_running():
                break
    res = subprocess.run(["awww", "img", picture, "--transition-type", "random", "--transition-duration", "1"],
                         capture_output=True, text=True, timeout=15)
    return "" if res.returncode == 0 else (res.stderr.strip().splitlines() or ["awww failed"])[-1]


def main() -> None:
    args = sys.argv[1:]
    if args == ["get"]:
        emit({"ok": True, "current": current()})
    elif len(args) == 2 and args[0] == "set":
        try:
            picture = Path(args[1]).expanduser().resolve(strict=True)
        except OSError:
            fail("No such picture.")
            return
        if not picture.is_file() or picture.suffix.lower() not in EXTS:
            fail("Not a picture.")

        def remember(section: dict) -> None:
            section["current"] = str(picture)

        try:
            config.update("wallpaper", remember)
        except config.NewerConfig as error:
            fail(str(error))
        problem = show(str(picture))
        emit({"ok": problem == "", "current": str(picture), "message": problem or "Wallpaper set."})
    else:
        fail("Usage: get | set <picture>")


if __name__ == "__main__":
    main()
