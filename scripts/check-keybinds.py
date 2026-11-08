#!/usr/bin/env python3
"""Every shortcut belongs in Settings -> Keybinds, findable in words.

Run by the package build (PKGBUILD check()); fails when:
  * hypr/keybinds.lua binds keys without a "-- YAKUSHI_BIND" marker line
    (Settings would not list it), or with a marker but no WORDS entry in
    KeybindsSearch.js (it would be listed but not found by "how do I ...")
  * a QML window handles keys (Keys.on..., Shortcut {}) but KeybindsSearch.js
    APPS names no file for it (its keys would be missing from the list)

Usage: check-keybinds.py [repo dir]   (default: this script's repo)
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

# key handling that is part of editing a field inside a Settings page, not a
# shortcut of its own
IGNORED_DIRS = ("SettingsPages/",)


def qml_files(root: Path) -> list[str]:
    """The repo's QML files (git's list: no build copies, no test files)."""
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", "*.qml"],
                             capture_output=True, text=True, check=True).stdout
        return sorted(f for f in out.split("\0") if f)
    except (OSError, subprocess.CalledProcessError):
        return sorted(q.relative_to(root).as_posix() for q in root.rglob("*.qml")
                      if not q.relative_to(root).as_posix().startswith(("packaging/", "zz-")))


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    problems: list[str] = []

    search_js = (root / "KeybindsSearch.js").read_text()
    words_block = search_js[search_js.index("var WORDS = {"):search_js.index("// ---- keys inside")]
    word_ids = set(re.findall(r"^    (\w+):", words_block, re.M))
    word_ids |= {f"{p}_{d}" for p in ("move", "focus", "resize") for d in ("left", "right", "up", "down")}
    word_ids |= {f"ws_{n}" for n in range(1, 11)} | {f"move_ws_{n}" for n in range(1, 11)}

    lines = (root / "hypr" / "keybinds.lua").read_text().splitlines()
    marker = None
    for no, line in enumerate(lines, 1):
        m = re.match(r"\s*--\s*YAKUSHI_BIND\s+([^|]+)\|", line)
        if m:
            marker = m.group(1).strip()
            continue
        bind = re.match(r'\s*yakushi_bind\("([^"]+)"', line)
        if bind:
            if bind.group(1) != marker:
                problems.append(f"hypr/keybinds.lua:{no}: {bind.group(1)} has no '-- YAKUSHI_BIND' line above it")
            elif bind.group(1) not in word_ids:
                problems.append(f"KeybindsSearch.js: WORDS has no entry for bind '{bind.group(1)}'")
            marker = None
        elif re.match(r'\s*hl\.bind\(\s*"', line):
            problems.append(f"hypr/keybinds.lua:{no}: plain hl.bind — use a marked yakushi_bind")

    app_files = set(re.findall(r'file:\s*"([^"]+)"', search_js))
    for rel in qml_files(root):
        if rel.startswith(IGNORED_DIRS):
            continue
        text = (root / rel).read_text(errors="replace")
        if re.search(r"\bKeys\.on\w+|\bShortcut\s*\{", text) and rel not in app_files:
            problems.append(f"{rel}: handles keys, but KeybindsSearch.js APPS has no entry with file: \"{rel}\"")
    for rel in sorted(app_files):
        if not (root / rel).exists():
            problems.append(f"KeybindsSearch.js: APPS names {rel}, which does not exist")

    for p in problems:
        print("check-keybinds: " + p, file=sys.stderr)
    if not problems:
        print(f"check-keybinds: ok ({len(word_ids)} bind words, {len(app_files)} windows with keys)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
