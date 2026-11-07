"""Every place Yakushi reads or writes, worked out in one spot.

Nothing here is a fixed path: user folders come from the XDG Base Directory
variables (with the spec's defaults), and the shell's own files are found
relative to this file, so the shell runs the same from a git checkout, a
user install (~/.local/share/yakushi-shell) or a system package.

Standard library only.
"""
from __future__ import annotations

import os
from pathlib import Path

HOME = Path.home()


def _xdg(variable: str, default: str) -> Path:
    """$variable if it is an absolute path (the spec says to ignore
    relative ones), else ~/<default>."""
    value = os.environ.get(variable, "")
    return Path(value) if os.path.isabs(value) else HOME / default


CONFIG_HOME = _xdg("XDG_CONFIG_HOME", ".config")
DATA_HOME = _xdg("XDG_DATA_HOME", ".local/share")
STATE_HOME = _xdg("XDG_STATE_HOME", ".local/state")
CACHE_HOME = _xdg("XDG_CACHE_HOME", ".cache")

# The shell itself (this file is <shell>/scripts/yakushi_paths.py).
SCRIPTS = Path(__file__).resolve().parent
SHELL = SCRIPTS.parent

# Yakushi's own folders.
CONFIG = CONFIG_HOME / "yakushi"           # settings (config.json, profile picture)
STATE = STATE_HOME / "yakushi"             # history, logs-of-record
CACHE = CACHE_HOME / "yakushi"             # anything that can be rebuilt
TRASH = DATA_HOME / "yakushi-trash"        # Programs: removed files, for undo

# Other programs' config folders that Settings edits.
HYPR = CONFIG_HOME / "hypr"


def runtime() -> Path:
    """$XDG_RUNTIME_DIR/yakushi (private, wiped at logout).

    There is no /tmp fallback on purpose: a guessable folder in /tmp could be
    created by another user first. systemd always sets the variable.
    """
    base = os.environ.get("XDG_RUNTIME_DIR", "")
    if not os.path.isabs(base):
        raise RuntimeError("XDG_RUNTIME_DIR is not set; log in through a systemd session.")
    folder = Path(base) / "yakushi"
    folder.mkdir(mode=0o700, exist_ok=True)
    return folder


def user_dir(name: str) -> Path:
    """An XDG user folder (DOCUMENTS, PICTURES, ...) from user-dirs.dirs,
    in whatever language it was set up; ~ itself if it is not set."""
    key = f"XDG_{name.upper()}_DIR"
    if os.path.isabs(os.environ.get(key, "")):
        return Path(os.environ[key])
    try:
        for line in (CONFIG_HOME / "user-dirs.dirs").read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith(key + "="):
                value = line.split("=", 1)[1].strip().strip('"')
                value = value.replace("$HOME", str(HOME), 1)
                if os.path.isabs(value):
                    return Path(value)
    except OSError:
        pass
    return HOME
