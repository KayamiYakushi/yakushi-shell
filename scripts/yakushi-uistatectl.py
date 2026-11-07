#!/usr/bin/env python3
"""Persist Settings appearance state (panel opacity, accent colour).

Commands:
    get                               Print the saved state as JSON.
    set <opacity> <#rrggbb>           Save the state.

State lives in the "appearance" section of ~/.config/yakushi/config.json
(see yakushi_config.py). Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys

import yakushi_paths as paths

import yakushi_config as config


OPACITY_MIN = 0.40
OPACITY_MAX = 1.00
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def clamp(value: float) -> float:
    return max(OPACITY_MIN, min(OPACITY_MAX, value))


def get() -> None:
    result: dict = {"ok": True}
    state = config.section("appearance")

    opacity = state.get("panelOpacity")
    if isinstance(opacity, (int, float)) and not isinstance(opacity, bool):
        result["panelOpacity"] = clamp(float(opacity))

    accent = state.get("accent")
    if isinstance(accent, str) and HEX.match(accent):
        result["accent"] = accent.lower()

    emit(result)


def set_state(opacity_raw: str, accent: str) -> None:
    try:
        opacity = clamp(float(opacity_raw))
    except ValueError:
        fail("Invalid opacity.")

    if not HEX.match(accent):
        fail("Invalid accent colour.")

    def change(state: dict) -> None:
        state["panelOpacity"] = round(opacity, 3)
        state["accent"] = accent.lower()

    try:
        config.update("appearance", change)
    except config.NewerConfig as error:
        fail(str(error))

    # The shell sees the saved file by itself (inotify). Programs outside
    # it, the launcher, window borders and the terminal, follow through
    # themesync (best effort, does not block).
    try:
        subprocess.Popen(
            ["python3", str(paths.SCRIPTS / "yakushi-themesync.py")],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass

    emit({"ok": True})


def main() -> None:
    args = sys.argv[1:]

    if args[:1] == ["get"]:
        get()
    elif args[:1] == ["set"] and len(args) >= 3:               # older extra words are ignored
        set_state(args[1], args[2])
    else:
        fail("Usage: get | set <opacity> <#rrggbb>")


if __name__ == "__main__":
    main()
