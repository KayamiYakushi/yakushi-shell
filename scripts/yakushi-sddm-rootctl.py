#!/usr/bin/python3 -I
"""Root helper for the Yakushi login screen (SDDM theme).

    yakushi-sddmctl set-background <png>
    yakushi-sddmctl reset-background
    yakushi-sddmctl set-look <#rrggbb> <12|24> <user> <png|->

set-look writes theme.conf.user (SDDM reads it over theme.conf): the
accent, the clock and whose picture avatar.png is; "-" as the picture
removes it.

It never opens a picture with an image library: Settings has already turned
your picture into a plain PNG (as you, without root). Here it is only checked
to really be a PNG of a sane size, then copied into the SDDM theme.
"""
from pathlib import Path
import os
import re
import stat
import sys

THEME_DIR = Path("/usr/share/sddm/themes/yakushi")
BACKGROUND = THEME_DIR / "background.png"
AVATAR = THEME_DIR / "avatar.png"
LOOK = THEME_DIR / "theme.conf.user"
MAX_BYTES = 100 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ACCENT_RE = re.compile(r"#[0-9a-fA-F]{6}")
USER_RE = re.compile(r"[a-z_][a-z0-9_-]{0,31}")


def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def read_png(path):
    """the bytes of a regular, not too large PNG file at path"""
    # open it once, without following a symlink, and use only that handle
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        fail("The prepared picture is missing.")
    with os.fdopen(fd, "rb") as src:
        info = os.fstat(src.fileno())
        if not stat.S_ISREG(info.st_mode):
            fail("Not a regular file.")
        if info.st_size > MAX_BYTES:
            fail("Image is larger than 100 MB.")
        data = src.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        fail("Image is larger than 100 MB.")
    if not data.startswith(PNG_SIGNATURE):
        fail("Not a PNG picture.")
    return data


def write(target, data):
    """data into target (in the theme), atomically, mode 644"""
    THEME_DIR.mkdir(parents=True, exist_ok=True)
    tmp = THEME_DIR / f".{target.name}.tmp"
    out = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
    with os.fdopen(out, "wb") as dst:
        dst.write(data)
        dst.flush()
        os.fsync(dst.fileno())
    os.chmod(tmp, 0o644)
    os.replace(tmp, target)


if os.geteuid() != 0:
    fail("This helper must run as root.")

if len(sys.argv) < 2:
    fail("Missing command.", 2)

cmd = sys.argv[1]

if cmd == "set-background":
    if len(sys.argv) != 3:
        fail("Missing image path.", 2)
    write(BACKGROUND, read_png(sys.argv[2]))
    print(BACKGROUND)

elif cmd == "reset-background":
    BACKGROUND.unlink(missing_ok=True)
    print("reset")

elif cmd == "set-look":
    if len(sys.argv) != 6:
        fail("Usage: set-look <#rrggbb> <12|24> <user> <png|->", 2)
    accent, clock, user, picture = sys.argv[2:6]
    if not ACCENT_RE.fullmatch(accent):
        fail("The accent must be #rrggbb.", 2)
    if clock not in ("12", "24"):
        fail("The clock must be 12 or 24.", 2)
    if not USER_RE.fullmatch(user):
        fail("Not a user name.", 2)

    if picture == "-":
        AVATAR.unlink(missing_ok=True)
        owner = ""
    else:
        write(AVATAR, read_png(picture))
        owner = user

    look = (
        "# Written by Yakushi Settings -> Login Screen -> MATCH THE SHELL.\n"
        "[General]\n"
        f"accent={accent.lower()}\n"
        f"clock24={'true' if clock == '24' else 'false'}\n"
        f"avatarUser={owner}\n"
    )
    write(LOOK, look.encode())
    print(LOOK)

else:
    fail("Invalid command.", 2)
