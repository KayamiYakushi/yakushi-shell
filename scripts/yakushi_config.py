"""The Yakushi config file: one place for every user setting.

    ~/.config/yakushi/config.json   ($XDG_CONFIG_HOME is honoured)

    {
      "version": 1,
      "topbar":     { ... },   owned by yakushi-topbarctl.py
      "appearance": { ... },   owned by yakushi-uistatectl.py
      "terminal":   { ... }    owned by yakushi-termctl.py
    }

Each section is validated by the helper that owns it; this module only keeps
the file whole and safe:

* Writes are atomic (temp file + fsync + rename), so a reader such as the
  shell's file watcher never sees half a file.
* Read-modify-write runs under an exclusive lock, so two helpers saving at
  the same moment cannot drop each other's change.
* The file and its folder are private to you (0600 / 0700).
* A broken file is never silently overwritten: it is kept as
  config.json.broken-<time> and the defaults are used.
* A file written by a newer Yakushi (higher version) is read as far as
  possible but never written, so a downgrade cannot destroy it.
* The first time, settings from the old ~/.config/quickshell/*.local.json
  files are carried over (those files are left untouched).

Standard library only.
"""
from __future__ import annotations

import fcntl
import json
import os
import shutil
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Callable, Iterator

VERSION = 1
SECTIONS = ("topbar", "appearance", "terminal")

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
DIR = CONFIG_HOME / "yakushi"
FILE = DIR / "config.json"
LOCK = DIR / ".config.lock"
PROFILE_PICTURE = DIR / "profile-picture"

LEGACY_DIR = CONFIG_HOME / "quickshell"


class NewerConfig(Exception):
    """config.json was written by a newer Yakushi; it must not be written."""


# ---------------------------------------------------------------------------
# Low level
# ---------------------------------------------------------------------------

def _ensure_dir() -> None:
    DIR.mkdir(mode=0o700, parents=True, exist_ok=True)


@contextmanager
def _locked() -> Iterator[None]:
    _ensure_dir()
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)                      # closing the fd releases the lock


def _write(data: dict) -> None:
    _ensure_dir()
    payload = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(dir=DIR, prefix=".config-", suffix=".tmp")   # 0600
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, FILE)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _set_aside(reason: str) -> None:
    """Keep a broken file for the user instead of overwriting it."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    try:
        os.replace(FILE, FILE.with_name(f"{FILE.name}.{reason}-{stamp}"))
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Shape, migration
# ---------------------------------------------------------------------------

def _blank() -> dict:
    return {"version": VERSION, **{name: {} for name in SECTIONS}}


def _normalise(data: dict) -> dict:
    """Every known section present and a dict; unknown keys are kept."""
    for name in SECTIONS:
        if not isinstance(data.get(name), dict):
            data[name] = {}
    return data


def _from_legacy() -> dict:
    """Version 0: the separate *.local.json files of the old setup."""
    data = _blank()

    topbar = _read_json(LEGACY_DIR / "yakushi-topbar.local.json")
    if isinstance(topbar, dict):
        topbar.pop("style", None)                  # Waybar is gone
        data["topbar"] = topbar

    ui = _read_json(LEGACY_DIR / "yakushi-ui.local.json")
    appearance: dict = {}
    if isinstance(ui, dict):
        for key in ("panelOpacity", "accent"):
            if key in ui:
                appearance[key] = ui[key]
    if "panelOpacity" not in appearance:
        old = _read_json(LEGACY_DIR / "yakushi-panel-opacity.local.json")
        if isinstance(old, dict) and isinstance(old.get("opacity"), (int, float)):
            appearance["panelOpacity"] = old["opacity"]
    data["appearance"] = appearance

    term = _read_json(LEGACY_DIR / "yakushi-term.local.json")
    if isinstance(term, dict):
        data["terminal"] = term

    old_picture = LEGACY_DIR / "assets/system-profile"
    if old_picture.is_file() and not PROFILE_PICTURE.exists():
        try:
            _ensure_dir()
            shutil.copyfile(old_picture, PROFILE_PICTURE)     # copy: hyprlock still uses the old one
        except OSError:
            pass

    return data


# Future format changes go here: MIGRATIONS[n] turns version n into n + 1.
MIGRATIONS: dict[int, Callable[[dict], dict]] = {}


def _upgrade(data: dict) -> dict:
    version = data.get("version")
    while version < VERSION:
        data = MIGRATIONS[version](data)
        version += 1
        data["version"] = version
    return data


def _load_unlocked() -> tuple[dict, bool]:
    """(config, writable). Creates or repairs the file when needed."""
    if not FILE.exists():
        data = _from_legacy()
        _write(data)
        return data, True

    data = _read_json(FILE)
    version = data.get("version") if isinstance(data, dict) else None

    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        _set_aside("broken")
        data = _blank()
        _write(data)
        return data, True

    if version > VERSION:
        return _normalise(data), False

    if version < VERSION:
        data = _upgrade(data)
        _write(_normalise(data))

    return _normalise(data), True


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def load() -> dict:
    """The whole config (creating / migrating it on first use)."""
    with _locked():
        data, _ = _load_unlocked()
    return data


def section(name: str) -> dict:
    """A copy of one section (always a dict)."""
    if name not in SECTIONS:
        raise KeyError(name)
    return dict(load()[name])


def update(name: str, change: Callable[[dict], dict | None]) -> dict:
    """Read-modify-write one section under the lock.

    `change` gets a copy of the section and either edits it in place or
    returns a replacement. Returns the saved section.
    """
    if name not in SECTIONS:
        raise KeyError(name)
    with _locked():
        data, writable = _load_unlocked()
        if not writable:
            raise NewerConfig(
                f"{FILE} was written by a newer Yakushi (version {data.get('version')}); "
                "not changing it."
            )
        current = dict(data[name])
        result = change(current)
        data[name] = current if result is None else result
        _write(data)
        return dict(data[name])


def replace(name: str, value: dict) -> dict:
    """Replace one section as a whole."""
    return update(name, lambda _old: dict(value))
