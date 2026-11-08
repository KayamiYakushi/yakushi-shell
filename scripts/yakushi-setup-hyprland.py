#!/usr/bin/env python3
"""Put Yakushi's starter Hyprland config in ~/.config/hypr.

    yakushi setup-hyprland            asks first, then sets it up
    yakushi setup-hyprland --yes      no question (for scripts)
    yakushi setup-hyprland --dry-run  only says what it would do

Settings edits a few Hyprland files in place (keybinds.lua, the apps and
input lines in hyprland.lua, monitors/window/cursor/terminal *.local.lua),
so it needs this layout. The starter comes from <shell>/hypr.

Nothing of yours is changed or deleted: an existing ~/.config/hypr is moved
aside as a whole to ~/.config/hypr.before-yakushi-<date> (if it is a
symlink, only the link moves; what it points to stays as it is). To go
back, delete the new folder and rename the old one.

The terminal, file manager, browser and keyboard layout are taken from what
this computer has; Settings -> Programs -> Default Apps / Input change them later.
Standard library only.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yakushi_paths as paths

STARTER = paths.SHELL / "hypr"
FILES = ("hyprland.lua", "keybinds.lua", "rules.lua", "monitors.lua", "xdph.conf")

# first one found wins
TERMINALS = ["kitty", "foot", "alacritty", "ghostty", "wezterm", "konsole",
             "gnome-terminal", "xfce4-terminal"]
FILE_MANAGERS = [("nautilus", "nautilus --new-window"), ("dolphin", "dolphin"),
                 ("thunar", "thunar"), ("nemo", "nemo"), ("pcmanfm-qt", "pcmanfm-qt"),
                 ("pcmanfm", "pcmanfm")]
BROWSERS = ["firefox", "chromium", "librewolf", "brave", "google-chrome-stable",
            "vivaldi-stable", "epiphany", "falkon", "qutebrowser"]

LAYOUT_RE = re.compile(r"^[a-z]{2,3}(\([a-z0-9_-]+\))?(,[a-z]{2,3}(\([a-z0-9_-]+\))?)*$")
SAFE_VALUE = re.compile(r'^[^"\\\n]*$')        # goes inside a Lua "string"


def say(text: str = "") -> None:
    print(text, flush=True)


def first_on_path(names: list[str], fallback: str) -> str:
    for name in names:
        if shutil.which(name):
            return name
    return fallback


def file_manager() -> str:
    for binary, command in FILE_MANAGERS:
        if shutil.which(binary):
            return command
    return "xdg-open ~"


def keyboard_layout() -> str:
    """the system's X11 layout (localectl), else us"""
    try:
        out = subprocess.run(["localectl", "status"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        out = ""
    for line in out.splitlines():
        key, _, value = line.partition(":")
        if key.strip() == "X11 Layout":
            value = value.strip()
            if LAYOUT_RE.match(value):
                return value
    return "us"


def detected() -> dict[str, str]:
    values = {
        "TERMINAL": first_on_path(TERMINALS, "kitty"),
        "FILE_MANAGER": file_manager(),
        "BROWSER": first_on_path(BROWSERS, "firefox"),
        "KB_LAYOUT": keyboard_layout(),
    }
    for key, value in values.items():
        if not SAFE_VALUE.match(value):
            raise SystemExit(f"setup-hyprland: unexpected {key} value: {value!r}")
    return values


def already_yakushi(folder: Path) -> bool:
    try:
        text = (folder / "hyprland.lua").read_text(encoding="utf-8")
    except OSError:
        return False
    return '"yakushi login"' in text


def has_content(folder: Path) -> bool:
    if folder.is_symlink():
        return True
    try:
        return any(folder.iterdir())
    except FileNotFoundError:
        return False
    except NotADirectoryError:
        return True


def ask(question: str) -> bool:
    if not sys.stdin.isatty():
        raise SystemExit("setup-hyprland: not asking without a terminal; run it in one, or add --yes.")
    try:
        return input(question + " [y/N] ").strip().lower() in ("y", "yes", "e", "evet")
    except EOFError:
        return False


def main() -> None:
    args = sys.argv[1:]
    unknown = [a for a in args if a not in ("--yes", "--dry-run", "--force")]
    if unknown:
        raise SystemExit("usage: yakushi setup-hyprland [--yes] [--dry-run]")
    yes, dry, force = "--yes" in args, "--dry-run" in args, "--force" in args

    missing = [f for f in FILES if not (STARTER / f).is_file()]
    if missing:
        raise SystemExit(f"setup-hyprland: the starter is incomplete in {STARTER} (missing {', '.join(missing)}).")

    target = paths.HYPR
    if already_yakushi(target) and not force:
        say(f"{target} already has the Yakushi config. Nothing to do.")
        return

    values = detected()
    backup = None
    if has_content(target):
        backup = target.with_name(f"hypr.before-yakushi-{time.strftime('%Y%m%d-%H%M%S')}")

    say("Yakushi's starter Hyprland config")
    say(f"  into:          {target}")
    if backup:
        say(f"  your current:  moved to {backup} (nothing is deleted)")
    say(f"  terminal:      {values['TERMINAL']}")
    say(f"  file manager:  {values['FILE_MANAGER']}")
    say(f"  browser:       {values['BROWSER']}")
    say(f"  keyboard:      {values['KB_LAYOUT']}")
    say("  (Settings -> Programs -> Default Apps / Input change these later)")

    if dry:
        say("\n--dry-run: nothing was changed.")
        return
    if not yes and not ask("\nGo ahead?"):
        say("Nothing was changed.")
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    if backup:
        os.rename(target, backup)              # one rename: the whole folder, or just the link

    # build it next to the target, then one rename: Hyprland (which reloads
    # on changes) never sees a half-written config
    staging = target.with_name(f".hypr.yakushi-{os.getpid()}")
    staging.mkdir(mode=0o755)
    try:
        for name in FILES:
            text = (STARTER / name).read_text(encoding="utf-8")
            for key, value in values.items():
                text = text.replace(f"@{key}@", value)
            (staging / name).write_text(text, encoding="utf-8")
            os.chmod(staging / name, 0o644)
        os.rename(staging, target)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        if backup and not target.exists():
            os.rename(backup, target)          # put yours back as it was
        raise

    say(f"\nDone. Hyprland reloads it by itself.")
    if backup:
        say(f"Your old config: {backup}")
    say("Log out and back in once so the startup programs (yakushi login, ...) run.")
    say("Shortcuts: SUPER + Space apps, SUPER + I Settings, SUPER + Q terminal, SUPER + Tab lock.")


if __name__ == "__main__":
    main()
