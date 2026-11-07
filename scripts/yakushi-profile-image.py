#!/usr/bin/env python3
"""Save the picture chosen in Settings -> System as the profile picture
(~/.config/yakushi/profile-picture). Usage: yakushi-profile-image.py <image>"""
from pathlib import Path
import shutil
import sys

import yakushi_config as config

if len(sys.argv) != 2:
    raise SystemExit("Usage: yakushi-profile-image.py <image>")

src = Path(sys.argv[1]).expanduser()

if not src.is_file():
    raise SystemExit(f"Not a file: {src}")

dst = config.PROFILE_PICTURE
dst.parent.mkdir(mode=0o700, parents=True, exist_ok=True)

tmp = dst.with_name(dst.name + ".tmp")
shutil.copyfile(src, tmp)
tmp.replace(dst)

print(dst)
