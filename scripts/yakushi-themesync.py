#!/usr/bin/env python3
"""Spread the Settings accent colour to everything outside Quickshell.

Called by yakushi-uistatectl.py whenever the accent changes (and safe to
run by hand). Each step is independent and best effort:

  * hyprlock   $accent in ~/.config/hypr/hyprlock.conf (the old lock, if still
               there; Yakushi's own lock reads the accent itself)
  * windows    border colour, when it follows the accent (yakushi-windowctl)
  * terminal   terminal + fish colours, when matching is on (yakushi-termctl)
  * gtk apps   GTK 3/4 colours, when matching is on (yakushi-gtkctl)

Runs once and exits: no daemon, no timers.
"""
from __future__ import annotations

import json
import os
import re
import subprocess

import yakushi_paths as paths

import yakushi_config as config


def write_safely(path, text: str) -> None:
    """Write a config file in place (same file, so watchers and symlinks keep
    working), but only after a trial copy proved the disk has room for it: on
    a full disk the old file stays whole instead of ending up empty."""
    real = os.path.realpath(path)
    data = text.encode()
    trial = os.path.join(os.path.dirname(real), "." + os.path.basename(real) + ".yakushi-new")
    try:
        with open(trial, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
    finally:
        try:
            os.unlink(trial)
        except OSError:
            pass
    try:
        with open(real, "rb") as f:
            old = f.read()
    except FileNotFoundError:
        old = None
    try:
        with open(real, "r+b" if old is not None else "wb") as f:
            f.write(data)
            f.truncate()
    except OSError:
        if old is not None:                      # put the old one back
            with open(real, "r+b") as f:
                f.write(old)
                f.truncate()
        raise


HYPRLOCK = paths.HYPR / "hyprlock.conf"
HELPERS = (
    paths.SCRIPTS / "yakushi-windowctl.py",
    paths.SCRIPTS / "yakushi-termctl.py",
    paths.SCRIPTS / "yakushi-gtkctl.py",
)
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def accent() -> str:
    try:
        value = config.section("appearance").get("accent")
        if isinstance(value, str) and HEX.match(value):
            return value.lower()
    except (OSError, ValueError, AttributeError):
        pass
    return "#ffffff"


def write_hyprlock(colour: str) -> None:
    try:
        text = HYPRLOCK.read_text()
    except OSError:
        return
    updated = re.sub(r"^\$accent\s*=.*$", f"$accent = rgba({colour[1:]}ff)", text, count=1, flags=re.M)
    if updated != text:
        write_safely(HYPRLOCK, updated)


def main() -> None:
    colour = accent()
    write_hyprlock(colour)
    for helper in HELPERS:
        if helper.exists():
            try:
                subprocess.run(["python3", str(helper), "sync"], capture_output=True, timeout=20)
            except (OSError, subprocess.TimeoutExpired):
                pass
    print(json.dumps({"ok": True, "accent": colour}))


if __name__ == "__main__":
    main()
