#!/usr/bin/env python3
"""The login screen (SDDM), for Settings -> Environment -> Login Screen.

    yakushi-sddmctl.py status
    yakushi-sddmctl.py set <image> [--password-stdin]
    yakushi-sddmctl.py reset [--password-stdin]
    yakushi-sddmctl.py sync [--password-stdin]

set / reset: the background. sync: the shell's accent, 12/24 h clock, your
profile picture and your mouse cursor, copied for the login screen (the
greeter runs as the sddm user and cannot read your home; the cursor becomes
the system theme Yakushi-Login).

Every picture is turned into a clean PNG here, as you: an image from the
internet is never opened as root. Only that PNG goes to the small root
helper (the package's /usr/lib/yakushi-shell/yakushi-sddmctl, else an older
/usr/local/libexec/yakushi-sddmctl), which checks it is a PNG and copies it
into the theme. With --password-stdin your password is the
first line of stdin (Settings asks for it in the page) and goes to sudo
through a pipe; without it pkexec asks.
"""
import importlib.util
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yakushi_config as config
import yakushi_paths as paths
from urllib.parse import unquote, urlparse

THEME_DIR = Path("/usr/share/sddm/themes/yakushi")
BACKGROUND = THEME_DIR / "background.png"
AVATAR = THEME_DIR / "avatar.png"
LOOK = THEME_DIR / "theme.conf.user"
# the package's helper first; an older manual install knows only the background
HELPERS = (Path("/usr/lib/yakushi-shell/yakushi-sddmctl"), Path("/usr/local/libexec/yakushi-sddmctl"))
ROOT_HELPER = next((h for h in HELPERS if h.is_file()), HELPERS[0])
CAN_SYNC = ROOT_HELPER == HELPERS[0] and ROOT_HELPER.is_file()
CURSOR_CONF = Path("/etc/sddm.conf.d/yakushi-cursor.conf")
ALLOWED = {".png", ".jpg", ".jpeg", ".webp"}
MAX_BYTES = 100 * 1024 * 1024
HERE = paths.SCRIPTS

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location("yakushi_taskctl", HERE / "yakushi-taskctl.py")
tasks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tasks)


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def helper_copies_cursor():
    """an installed helper from before the cursor was copied takes no cursor"""
    try:
        return b"Yakushi-Login" in ROOT_HELPER.read_bytes()
    except OSError:
        return False


def shell_cursor():
    """(the XCursor folder of the cursor in use or None, its size, its name)"""
    cur = load("yakushi-cursorctl")
    theme = cur.theme_by_id(cur.current())
    folder = Path(theme["path"]) / "cursors" if theme else None
    if folder is None or not folder.is_dir():
        return None, 24, ""
    return folder.resolve(), min(128, max(8, cur.size())), theme["name"]


def emit(ok=True, **values):
    data = {"ok": ok}
    data.update(values)
    print(json.dumps(data, ensure_ascii=False))


def stop(message, code=1, **values):
    emit(False, message=message, **values)
    raise SystemExit(code)


def source_path(raw):
    parsed = urlparse(raw)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return Path(raw).expanduser()


def run_root(*args):
    result, err = tasks.as_root([str(ROOT_HELPER), *map(str, args)], 120)
    if result == "ok":
        return
    if result == "wrong":
        stop(tasks.ROOT_MESSAGES["wrong"], wrongPassword=True)
    stop(tasks.ROOT_MESSAGES.get(result) or err or "Could not update SDDM.")


def clean_png(src: Path, name="sddm-background.png", box="3840x3840") -> Path:
    """the picture as a plain PNG, made without root (at most box, no metadata)"""
    magick = shutil.which("magick") or shutil.which("convert")
    if magick is None:
        stop("ImageMagick (magick) is not installed.")
    folder = paths.runtime()
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    out = folder / name
    out.unlink(missing_ok=True)
    try:
        proc = subprocess.run(
            [magick, "-limit", "memory", "512MiB", "-limit", "map", "1GiB",
             f"{src}[0]", "-auto-orient", "-strip", "-resize", f"{box}>", f"PNG24:{out}"],
            capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        stop("The picture took too long to convert.")
    if proc.returncode != 0 or not out.is_file():
        out.unlink(missing_ok=True)
        stop("Could not read that picture (it may be damaged, or not really an image).")
    os.chmod(out, 0o644)
    return out


def look():
    """what the theme has now: accent, clock24, avatar user ('' when unset)"""
    found = {"accent": "", "clock24": False, "avatarUser": ""}
    try:
        text = LOOK.read_text(errors="replace")
    except OSError:
        return found
    for line in text.splitlines():
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if key == "accent" and re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            found["accent"] = value
        elif key == "clock24":
            found["clock24"] = value == "true"
        elif key == "avatarUser":
            found["avatarUser"] = value
    return found


def status():
    installed = THEME_DIR.is_dir() and ROOT_HELPER.is_file()
    background = BACKGROUND.is_file()
    current = look()
    avatar = AVATAR.is_file() and current["avatarUser"] == pwd.getpwuid(os.getuid()).pw_name
    emit(
        True,
        installed=installed,
        canSync=CAN_SYNC,
        background=background,
        preview=BACKGROUND.as_uri() if background else "",
        accent=current["accent"],
        clock24=current["clock24"],
        avatar=AVATAR.as_uri() if avatar else "",
        cursor=CURSOR_CONF.is_file(),
        message="Yakushi SDDM theme is ready." if installed else "Yakushi SDDM theme is not installed.",
    )


def main():
    args = tasks.take_password(sys.argv[1:])
    if not args:
        stop("Missing command.", 2)

    cmd = args[0]

    if cmd == "status":
        status()
        return

    if not ROOT_HELPER.is_file():
        stop("SDDM helper is not installed.")

    if cmd == "set" and len(args) == 2:
        src = source_path(args[1]).resolve()
        if not src.is_file():
            stop("Selected image does not exist.")
        if src.suffix.lower() not in ALLOWED:
            stop("Use PNG, JPG, JPEG or WEBP.")
        if src.stat().st_size > MAX_BYTES:
            stop("The picture is larger than 100 MB.")

        png = clean_png(src)
        try:
            run_root("set-background", png)
        finally:
            png.unlink(missing_ok=True)
        emit(
            True,
            background=True,
            preview=BACKGROUND.as_uri(),
            message="Login background updated. It will appear on the next SDDM login.",
        )
        return

    if cmd == "reset" and len(args) == 1:
        run_root("reset-background")
        emit(
            True,
            background=False,
            preview="",
            message="Login background reset to the default dark Yakushi screen.",
        )
        return

    if cmd == "sync" and len(args) == 1:
        if not CAN_SYNC:
            stop("The installed login theme is older: update the yakushi-shell package first.")
        accent = config.section("appearance").get("accent")
        if not isinstance(accent, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", accent):
            accent = "#ffffff"
        clock = "24" if config.section("topbar").get("clock24") is True else "12"
        user = pwd.getpwuid(os.getuid()).pw_name

        picture = config.PROFILE_PICTURE
        png = clean_png(picture, "sddm-avatar.png", "512x512") if picture.is_file() else None
        look_args = ["set-look", accent, clock, user, png or "-"]
        note = ""
        cursor = False
        if helper_copies_cursor():
            folder, size, name = shell_cursor()
            look_args += [folder or "-", size]
            cursor = folder is not None
            if not cursor:
                note = " Your cursor theme has no XCursor files, so the login screen keeps the system cursor."
        else:
            note = " Update the yakushi-shell package to copy your cursor too."
        try:
            run_root(*look_args)
        finally:
            if png:
                png.unlink(missing_ok=True)
        emit(
            True,
            accent=accent,
            clock24=clock == "24",
            avatar=AVATAR.as_uri() if png else "",
            cursor=cursor,
            message="The login screen now matches the shell. It shows on the next SDDM login." + note,
        )
        return

    stop("Invalid command.", 2)


if __name__ == "__main__":
    main()
