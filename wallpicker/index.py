#!/usr/bin/env python3
"""Index the wallpapers for the picker and print its settings as JSON.

The pictures come from the "wallpaper" section of the config:

    "wallpaper": {
      "folder": "~/Pictures/Walls",   default: Pictures/Wallpapers when it has
                                      pictures, else your XDG Documents folder
      "visibleCount": 10,             tiles across the strip
      "thumbJobs": 4,                 thumbnails made at once
      "current": "/path/to/picture"   the wallpaper (yakushi-wallpaperctl.py)
    }

Every picture under the folder gets a stable symlink in
~/.cache/yakushi/wallpaper/index (so the picker can list one flat folder);
links and thumbnails of pictures that are gone are removed. "current" is
the index name of the wallpaper now (yakushi-wallpaperctl.py), so the
picker opens there.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import yakushi_config as config  # noqa: E402
import yakushi_paths as paths    # noqa: E402

EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def number(value, default: int, low: int, high: int) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        return max(low, min(high, value))
    return default


def has_pictures(folder: Path) -> bool:
    """at least one picture right in the folder (stops at the first)"""
    try:
        with os.scandir(folder) as entries:
            return any(e.is_file() and Path(e.name).suffix.lower() in EXTS for e in entries)
    except OSError:
        return False


def default_folder() -> Path:
    # (no XDG Pictures folder set: user_dir gives ~, so also look in ~/Pictures)
    for walls in (paths.user_dir("PICTURES") / "Wallpapers", paths.HOME / "Pictures" / "Wallpapers"):
        if has_pictures(walls):
            return walls
    return paths.user_dir("DOCUMENTS")


def settings() -> dict:
    saved = config.section("wallpaper")
    folder = saved.get("folder")
    folder = Path(folder).expanduser() if isinstance(folder, str) and folder.strip() else default_folder()
    return {
        "folder": str(folder),
        "index": str(paths.CACHE / "wallpaper/index"),
        "thumbs": str(paths.CACHE / "wallpaper/thumbs"),
        "visibleCount": number(saved.get("visibleCount"), 10, 3, 30),
        "thumbJobs": number(saved.get("thumbJobs"), 4, 1, 64),
    }


def on_screen() -> set[Path]:
    """the wallpaper now, as remembered by yakushi-wallpaperctl.py"""
    spec = importlib.util.spec_from_file_location("yakushi_wallpaperctl", paths.SCRIPTS / "yakushi-wallpaperctl.py")
    ctl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ctl)
    picture = ctl.current()
    try:
        return {Path(picture).resolve()} if picture else set()
    except OSError:
        return set()


def main() -> None:
    cfg = settings()
    root, index, thumbs = Path(cfg["folder"]), Path(cfg["index"]), Path(cfg["thumbs"])
    index.mkdir(parents=True, exist_ok=True)

    wanted: dict[str, Path] = {}
    if root.is_dir():
        for p in root.rglob("*"):
            try:
                if not p.is_file() or p.suffix.lower() not in EXTS:
                    continue
            except OSError:
                continue
            digest = hashlib.sha1(str(p).encode()).hexdigest()[:12]
            safe_stem = p.stem[:80].replace("/", "_")
            wanted[f"{safe_stem}-{digest}{p.suffix.lower()}"] = p

    # Remove stale links, and the thumbnails of pictures that are gone (they
    # would only fill the disk).
    for folder in (index, thumbs):
        try:
            entries = list(folder.iterdir())
        except OSError:
            continue
        for entry in entries:
            if entry.name not in wanted:
                try:
                    entry.unlink()
                except OSError:
                    pass

    # Stable symlinks to the real files.
    for name, src in wanted.items():
        dst = index / name
        if dst.is_symlink():
            try:
                if dst.resolve() == src.resolve():
                    continue
            except OSError:
                pass
            dst.unlink(missing_ok=True)
        elif dst.exists():
            dst.unlink()
        try:
            dst.symlink_to(src)
        except OSError:
            pass

    shown = on_screen()
    current = ""
    for name, src in wanted.items():
        try:
            if src.resolve() in shown:
                current = name
                break
        except OSError:
            pass

    print(json.dumps({**cfg, "count": len(wanted), "current": current}))


if __name__ == "__main__":
    main()
