#!/usr/bin/python3 -I
"""Root helper for the Yakushi login screen (SDDM theme).

    yakushi-sddmctl set-background <png>
    yakushi-sddmctl reset-background
    yakushi-sddmctl set-look <#rrggbb> <12|24> <user> <png|-> [<cursors|-> <size>]

set-look writes theme.conf.user (SDDM reads it over theme.conf): the
accent, the clock and whose picture avatar.png is; "-" as the picture
removes it.

With <cursors> (a theme's cursors/ folder) the mouse cursor is copied too,
as the system theme Yakushi-Login, and SDDM is told to use it at <size>:
the greeter cannot read a theme in your home. "-" takes it away again. Only
XCursor files and links between them are copied, nothing else in the folder.

It never opens a picture with an image library: Settings has already turned
your picture into a plain PNG (as you, without root). Here it is only checked
to really be a PNG of a sane size, then copied into the SDDM theme.
"""
from pathlib import Path
import os
import re
import shutil
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
CURSOR_THEME = "Yakushi-Login"
CURSOR_DIR = Path("/usr/share/icons") / CURSOR_THEME
CURSOR_CONF = Path("/etc/sddm.conf.d/yakushi-cursor.conf")
CURSOR_NAME_RE = re.compile(r"[A-Za-z0-9_+-][A-Za-z0-9_+.-]{0,63}")
CURSOR_MAGIC = b"Xcur"
MAX_CURSORS = 1000
MAX_CURSOR_BYTES = 16 * 1024 * 1024
MAX_THEME_BYTES = 128 * 1024 * 1024


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
    """data into target, atomically, mode 644"""
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.parent / f".{target.name}.tmp"
    out = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
    with os.fdopen(out, "wb") as dst:
        dst.write(data)
        dst.flush()
        os.fsync(dst.fileno())
    os.chmod(tmp, 0o644)
    os.replace(tmp, target)


def read_cursors(path):
    """({name: bytes}, {name: link target}) of the XCursor folder at path"""
    try:
        folder = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        fail("The cursor theme is missing.")
    files, links, total = {}, {}, 0
    try:
        names = os.listdir(folder)
        if len(names) > MAX_CURSORS:
            fail("The cursor theme has too many files.")
        for name in names:
            if not CURSOR_NAME_RE.fullmatch(name):
                continue
            try:
                info = os.lstat(name, dir_fd=folder)
                if stat.S_ISLNK(info.st_mode):
                    # only a link to another cursor right here, never a path
                    target = os.readlink(name, dir_fd=folder)
                    if CURSOR_NAME_RE.fullmatch(target):
                        links[name] = target
                    continue
                if not stat.S_ISREG(info.st_mode):
                    continue
                fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=folder)
            except OSError:
                continue
            with os.fdopen(fd, "rb") as src:
                info = os.fstat(src.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_CURSOR_BYTES:
                    continue
                data = src.read(MAX_CURSOR_BYTES + 1)
            if len(data) > MAX_CURSOR_BYTES or not data.startswith(CURSOR_MAGIC):
                continue
            total += len(data)
            if total > MAX_THEME_BYTES:
                fail("The cursor theme is too large.")
            files[name] = data
    finally:
        os.close(folder)
    if not files:
        fail("That cursor theme has no XCursor files.")
    # a link may point at a link; keep the ones that end at a copied file
    def lands(name, hops=8):
        while hops and name in links:
            name, hops = links[name], hops - 1
        return name in files
    return files, {n: t for n, t in links.items() if n not in files and lands(n)}


def set_cursor(path, size):
    """the cursors at path as the system theme Yakushi-Login, used by SDDM"""
    files, links = read_cursors(path)
    new = CURSOR_DIR.with_name(f".{CURSOR_THEME}.new")
    old = CURSOR_DIR.with_name(f".{CURSOR_THEME}.old")
    for leftover in (new, old):
        shutil.rmtree(leftover, ignore_errors=True)
    cursors = new / "cursors"
    cursors.mkdir(parents=True, mode=0o755)
    for name, data in files.items():
        out = os.open(cursors / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
        with os.fdopen(out, "wb") as dst:
            dst.write(data)
            os.fchmod(dst.fileno(), 0o644)
    for name, target in links.items():
        os.symlink(target, cursors / name)
    index = "[Icon Theme]\nName=Yakushi Login\nComment=Your cursor, copied for the login screen by Yakushi Settings\n"
    (new / "index.theme").write_text(index)
    os.chmod(new / "index.theme", 0o644)
    for folder in (new, cursors):
        os.chmod(folder, 0o755)
    if CURSOR_DIR.is_symlink() or CURSOR_DIR.is_file():
        CURSOR_DIR.unlink()
    elif CURSOR_DIR.is_dir():
        CURSOR_DIR.rename(old)
    new.rename(CURSOR_DIR)
    shutil.rmtree(old, ignore_errors=True)
    conf = (
        "# Written by Yakushi Settings -> Environment -> Login Screen -> MATCH THE SHELL.\n"
        "[Theme]\n"
        f"CursorTheme={CURSOR_THEME}\n"
        f"CursorSize={size}\n"
    )
    write(CURSOR_CONF, conf.encode())


def reset_cursor():
    CURSOR_CONF.unlink(missing_ok=True)
    if CURSOR_DIR.is_symlink() or CURSOR_DIR.is_file():
        CURSOR_DIR.unlink()
    else:
        shutil.rmtree(CURSOR_DIR, ignore_errors=True)


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
    if len(sys.argv) not in (6, 8):
        fail("Usage: set-look <#rrggbb> <12|24> <user> <png|-> [<cursors|-> <size>]", 2)
    accent, clock, user, picture = sys.argv[2:6]
    cursors, cursor_size = sys.argv[6:8] if len(sys.argv) == 8 else (None, "24")
    if not ACCENT_RE.fullmatch(accent):
        fail("The accent must be #rrggbb.", 2)
    if clock not in ("12", "24"):
        fail("The clock must be 12 or 24.", 2)
    if not USER_RE.fullmatch(user):
        fail("Not a user name.", 2)
    if not (cursor_size.isascii() and cursor_size.isdigit() and 8 <= int(cursor_size) <= 128):
        fail("The cursor size must be 8 to 128.", 2)

    if picture == "-":
        AVATAR.unlink(missing_ok=True)
        owner = ""
    else:
        write(AVATAR, read_png(picture))
        owner = user

    look = (
        "# Written by Yakushi Settings -> Environment -> Login Screen -> MATCH THE SHELL.\n"
        "[General]\n"
        f"accent={accent.lower()}\n"
        f"clock24={'true' if clock == '24' else 'false'}\n"
        f"avatarUser={owner}\n"
    )
    write(LOOK, look.encode())
    if cursors == "-":
        reset_cursor()
    elif cursors is not None:
        set_cursor(cursors, int(cursor_size))
    print(LOOK)

else:
    fail("Invalid command.", 2)
