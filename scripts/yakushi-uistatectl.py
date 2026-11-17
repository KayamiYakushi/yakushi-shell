#!/usr/bin/env python3
"""Persist Settings appearance state (panel opacity, accent colour).

Commands:
    get                               Print the saved state as JSON.
    set <opacity> <#rrggbb>           Save the state.
    order <key,key,...>               Save the order of the Settings icons
                                      (appearance.settingsOrder; system stays first).

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


ORDER_KEY = re.compile(r"^[a-z]{1,24}$")


def set_order(raw: str) -> None:
    """The icons' order in the Settings header. Only the shape of each key
    is checked here; Settings drops keys it does not know when it reads."""
    keys: list[str] = ["system"]
    for key in raw.split(","):
        if ORDER_KEY.match(key) and key not in keys:
            keys.append(key)
    if len(keys) > 40:
        fail("Too many entries.")

    def change(state: dict) -> None:
        state["settingsOrder"] = keys

    try:
        config.update("appearance", change)
    except config.NewerConfig as error:
        fail(str(error))
    emit({"ok": True, "order": keys})


def main() -> None:
    args = sys.argv[1:]

    if args[:1] == ["get"]:
        get()
    elif args[:1] == ["set"] and len(args) >= 3:               # older extra words are ignored
        set_state(args[1], args[2])
    elif len(args) == 2 and args[0] == "order":
        set_order(args[1])
    else:
        fail("Usage: get | set <opacity> <#rrggbb> | order <key,key,...>")


if __name__ == "__main__":
    main()
