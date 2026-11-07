#!/usr/bin/env python3
"""Index the wallpapers for the picker and print its settings as JSON.

The pictures come from the "wallpaper" section of the config:

    "wallpaper": {
      "folder": "~/Pictures/Walls",   default: your XDG Documents folder
      "visibleCount": 10,             tiles across the screen
      "frameColor": "#80FFFFFF",      #RRGGBB or #AARRGGBB
      "thumbJobs": 4                  thumbnails made at once
    }

Every picture under the folder gets a stable symlink in
~/.cache/yakushi/wallpaper/index (so the picker can list one flat folder);
links and thumbnails of pictures that are gone are removed.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import yakushi_config as config  # noqa: E402
import yakushi_paths as paths    # noqa: E402

EXTS = {".jpg", ".jpeg", ".png", ".webp"}
COLOUR = re.compile(r"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")


def number(value, default: int, low: int, high: int) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        return max(low, min(high, value))
    return default


def settings() -> dict:
    saved = config.section("wallpaper")
    folder = saved.get("folder")
    folder = Path(folder).expanduser() if isinstance(folder, str) and folder.strip() else paths.user_dir("DOCUMENTS")
    colour = saved.get("frameColor")
    return {
        "folder": str(folder),
        "index": str(paths.CACHE / "wallpaper/index"),
        "thumbs": str(paths.CACHE / "wallpaper/thumbs"),
        "visibleCount": number(saved.get("visibleCount"), 10, 3, 30),
        "frameColor": colour if isinstance(colour, str) and COLOUR.match(colour) else "#80FFFFFF",
        "thumbJobs": number(saved.get("thumbJobs"), 4, 1, 64),
    }


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

    print(json.dumps({**cfg, "count": len(wanted)}))


if __name__ == "__main__":
    main()
