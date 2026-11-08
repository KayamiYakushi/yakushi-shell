#!/usr/bin/env python3
"""A general clean-up, for Settings -> Programs -> CLEAN UP.

    yakushi-cleanctl.py scan                 what could go, with sizes; changes nothing
    yakushi-cleanctl.py clean <json> [--dry-run] [--password-stdin]
                                             clean the chosen items: {"ids": ["...", ...]}

What `scan` looks for:
  * packages (root): old versions in the pacman cache (the installed one is
    kept), cached packages of programs that are gone, packages nothing needs
    any more (orphans), system logs older than two weeks
  * leftovers of programs that are not installed (KDE, Niri, Waybar, Rofi,
    ...): their folders in ~/.config, ~/.local/share, ~/.local/state, ~/.cache
    and tool folders such as ~/.npm or ~/.cargo
  * old backups and copies: *.bak, *-before-*, *last-good*, "(copy 1)" files,
    backup folders in your home, and git clones that are clean, fully pushed
    copies of a repository you also have elsewhere
  * broken links and app-list entries whose program is gone
  * caches that rebuild themselves (thumbnails), and big app caches (not
    ticked: an app may forget things, e.g. Spotify's downloaded songs)
  * your Trash (never ticked: it is what you threw away, emptying is for good)

`clean` scans again and only touches what that fresh scan finds, so the
page can never make it delete a path of its own choosing. Your files (not
caches) are moved to the Yakushi trash, as Programs does: REMOVED BEFORE
shows them and UNDO puts them back. Caches and the Trash are deleted.
Package steps run as root with one password (--password-stdin: the first
line of stdin, piped to sudo; without it pkexec asks).

Nothing here touches Documents, Pictures, Music, Videos, Downloads, Desktop,
games, ~/.ssh, keyrings or Yakushi's own settings.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yakushi_paths as paths

sys.dont_write_bytecode = True


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, paths.SCRIPTS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tasks = _load("yakushi_taskctl", "yakushi-taskctl.py")
removectl = _load("yakushi_removectl", "yakushi-removectl.py")

HOME = paths.HOME
CONFIG, DATA, STATE, CACHE = paths.CONFIG_HOME, paths.DATA_HOME, paths.STATE_HOME, paths.CACHE_HOME
NAME_RE = removectl.NAME_RE

# ---------------------------------------------------------------------------
# What belongs to which program
# ---------------------------------------------------------------------------

# name in ~/.config, ~/.local/share, ~/.local/state or ~/.cache  ->  the
# packages (any one installed = still in use) and a label
KNOWN: list[tuple[str, tuple[str, ...], str]] = [
    # KDE / Plasma
    (r"^(kdeglobals|kdedefaults|kded\d*rc|kconf_updaterc|kglobalshortcutsrc|kwinrc|kwinrulesrc|plasma.*|"
     r"kactivitymanagerd.*|ksmserverrc|kscreenlockerrc|systemsettingsrc|systemsettingsstaterc|"
     r"powermanagementprofilesrc|baloofilerc|baloo|ksycoca\d*.*|kxkbrc|kcminputrc|khotkeysrc|"
     r"userfeedback\.org\.kde\..*|kdeconnect|kwalletrc|kwalletd|color-schemes|plasmashell.*|"
     r"user-places\.xbel.*|kservicemenus|kio.*rc)$",
     ("plasma-workspace", "plasma-desktop", "kwin", "dolphin", "kde-cli-tools"), "KDE / Plasma"),
    (r"^dolphin.*$", ("dolphin",), "Dolphin"),
    (r"^gwenview.*$", ("gwenview",), "Gwenview"),
    (r"^konsole.*$", ("konsole",), "Konsole"),
    (r"^kate.*$", ("kate",), "Kate"),
    (r"^okular.*$", ("okular",), "Okular"),
    (r"^spectacle.*$", ("spectacle",), "Spectacle"),
    (r"^ark(rc)?$", ("ark",), "Ark"),
    (r"^krita.*$", ("krita",), "Krita"),
    (r"^kdenlive.*$", ("kdenlive",), "Kdenlive"),
    # other desktops and their pieces
    (r"^niri$", ("niri",), "Niri"),
    (r"^noctalia$", ("noctalia-shell", "noctalia-shell-git"), "Noctalia"),
    (r"^waybar$", ("waybar",), "Waybar"),
    (r"^(rofi|rofi\d*\.druncache|rofi-entry-history\.txt)$", ("rofi", "rofi-wayland"), "Rofi"),
    (r"^wofi$", ("wofi",), "Wofi"),
    (r"^fuzzel$", ("fuzzel",), "Fuzzel"),
    (r"^wlogout$", ("wlogout",), "wlogout"),
    (r"^swaync$", ("swaync",), "SwayNC"),
    (r"^mako$", ("mako",), "Mako"),
    (r"^dunst$", ("dunst",), "Dunst"),
    (r"^sway$", ("sway",), "Sway"),
    (r"^i3$", ("i3-wm",), "i3"),
    (r"^uwsm$", ("uwsm",), "UWSM"),
    (r"^eww$", ("eww",), "Eww"),
    (r"^ags$", ("aylurs-gtk-shell", "ags"), "AGS"),
    (r"^(xfce4|xfconf)$", ("xfconf", "xfce4-session"), "Xfce"),
    (r"^thunar$", ("thunar",), "Thunar"),
    (r"^nemo$", ("nemo",), "Nemo"),
    (r"^qt5ct$", ("qt5ct",), "qt5ct"),
    (r"^xsettingsd$", ("xsettingsd",), "xsettingsd"),
    (r"^gnome-shell$", ("gnome-shell",), "GNOME Shell"),
    # apps
    (r"^vlc$", ("vlc", "vlc-gui-qt"), "VLC"),
    (r"^nvim$", ("neovim",), "Neovim"),
    (r"^discord$", ("discord",), "Discord (the package; the Flatpak keeps its data elsewhere)"),
    (r"^spotify$", ("spotify-launcher", "spotify"), "Spotify (the package)"),
    (r"^qalculate$", ("qalculate-gtk", "qalculate-qt"), "Qalculate"),
    (r"^meld$", ("meld",), "Meld"),
    (r"^obs-studio$", ("obs-studio",), "OBS"),
    (r"^(chromium)$", ("chromium",), "Chromium"),
    (r"^(code - oss|vscode-oss)$", ("code",), "Code - OSS"),
    (r"^(hyprpaper|hyprlock|hypridle)$", ("hyprpaper", "hyprlock", "hypridle"), "an old Hypr tool"),
]
KNOWN_RE = [(re.compile(p, re.I), pkgs, label) for p, pkgs, label in KNOWN]

# tool folders straight in your home
HOME_TOOLS: dict[str, tuple[tuple[str, ...], str]] = {
    ".npm": (("npm", "nodejs", "nodejs-lts-jod", "nodejs-lts-iron"), "npm cache"),
    ".cargo": (("rust", "rustup", "cargo"), "Rust / cargo downloads"),
    ".rustup": (("rustup",), "Rust toolchains"),
    ".yarn": (("yarn",), "Yarn cache"),
    ".gradle": (("gradle",), "Gradle cache"),
    ".m2": (("maven",), "Maven cache"),
    ".bun": (("bun",), "Bun"),
    ".deno": (("deno",), "Deno"),
    ".nv": (("nvidia-utils",), "NVIDIA shader cache"),
    ".oh-my-zsh": (("zsh",), "oh-my-zsh"),
}

# hypr files left by tools that are gone
HYPR_LEFT = {"hyprpaper.conf": "hyprpaper", "hyprlock.conf": "hyprlock", "hypridle.conf": "hypridle"}

# never offered, whatever the rules say
KEEP_NAMES = {
    "hypr", "quickshell", "yakushi", "yakushi-trash", "yakushi-shell", "fish", "kitty", "gtk-3.0", "gtk-4.0",
    "systemd", "autostart", "applications", "icons", "fonts", "themes", "dconf", "pulse", "pipewire",
    "wireplumber", "keyrings", "gnupg", "pki", "flatpak", "trash", "mime", "xdg-desktop-portal",
    "gvfs-metadata", "recently-used.xbel", "mimeapps.list", "user-dirs.dirs", "user-dirs.locale",
    "fontconfig", "qtproject", "qtproject.conf", "claude", "cachyos", "sddm", "nautilus", "tracker3",
}
PERSONAL_DIRS = ("DOCUMENTS", "PICTURES", "MUSIC", "VIDEOS", "DOWNLOAD", "DESKTOP", "PUBLICSHARE", "TEMPLATES")

BACKUP_FILE = re.compile(r"(\.bak\d*|\.backup|\.orig|\.old|~)$|[._-]before[-_.]|last-good|\(copy \d+\)|\.pacsave$",
                         re.I)
BACKUP_DIR = re.compile(r"(\.bak\d*$|[._-]backups?([-_.]|$)|^backups?[-_]|[-_]before[-_]|^yakushibackups$|"
                        r"rescue[-_]\d|[-_]bak\d*$)", re.I)

# big app caches: offered, not ticked (an app may forget things)
APP_CACHES = {
    "com.spotify.Client": ("cache/spotify/Data", "Spotify", "song cache; you stay signed in, downloaded songs download again"),
}
BIG_CACHE = 300 * 1024 * 1024


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def run(cmd: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    return removectl.run(cmd, timeout, removectl.C_LOCALE)


def rel(path: Path) -> str:
    return "~/" + str(path.relative_to(HOME))


def size_of(path: Path, budget: float = 0.8) -> tuple[int, bool]:
    return removectl.folder_size(path, budget)


def installed_packages() -> set[str]:
    return set(run(["pacman", "-Qq"], 20).stdout.split())


def in_path() -> set[str]:
    names: set[str] = set()
    for d in os.environ.get("PATH", "").split(":") + [str(HOME / ".local/bin")]:
        try:
            names.update(n.lower() for n in os.listdir(d))
        except OSError:
            pass
    return names


def flatpak_names() -> set[str]:
    out = run(["flatpak", "list", "--app", "--columns=application"], 20).stdout.split()
    names = set()
    for app in out:
        names.add(app.lower())
        names.add(app.split(".")[-1].lower())
    return names


def referenced() -> set[Path]:
    """Paths in your home that something still points at: services (system
    and yours) that read them, and links in your config that lead into them.
    Those are in use, whatever their name says."""
    found: set[Path] = set()
    home = re.escape(str(HOME))
    pattern = re.compile(home + r"/[^\s\"';:]+")
    for folder in (Path("/etc/systemd/system"), CONFIG / "systemd/user"):
        try:
            units = [u for u in folder.iterdir() if u.suffix in (".service", ".timer", ".path", ".socket")]
        except OSError:
            continue
        for unit in units:
            try:
                text = unit.read_text(errors="replace")
            except OSError:
                continue
            found.update(Path(m.group(0)) for m in pattern.finditer(text.replace("%h", str(HOME))))
    for folder in (HOME, CONFIG, DATA, HOME / ".local/bin"):
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        for entry in entries:
            if entry.is_symlink():
                try:
                    target = Path(os.path.realpath(entry.path))
                except OSError:
                    continue
                if target.is_relative_to(HOME) and target.exists():
                    found.add(target)
    return found


def personal_roots() -> set[Path]:
    roots = {HOME / ".ssh", HOME / ".gnupg", HOME / ".var", HOME / ".steam", HOME / "Projects" / "yakushi-shell",
             HOME / ".local/share/yakushi-trash", HOME / ".local/state/yakushi"}
    for key in PERSONAL_DIRS:
        p = paths.user_dir(key)
        if p != HOME:
            roots.add(p)
    return roots | referenced()


def untouchable(path: Path, personal: set[Path]) -> bool:
    if not path.is_relative_to(HOME) or path == HOME:
        return True
    if path.name.lower().lstrip(".") in KEEP_NAMES and path.parent in (CONFIG, DATA, STATE, CACHE, HOME):
        return True
    return any(path == p or path.is_relative_to(p) or p.is_relative_to(path) for p in personal)


# ---------------------------------------------------------------------------
# Scanning
# ---------------------------------------------------------------------------

class Found:
    def __init__(self) -> None:
        self.items: list[dict] = []
        self.ids: set[str] = set()

    def add(self, item: dict) -> None:
        if item["id"] in self.ids:
            return
        self.ids.add(item["id"])
        self.items.append(item)


def file_item(found: Found, group: str, path: Path, title: str, note: str, checked: bool,
              kind: str = "move", personal: set[Path] | None = None) -> None:
    """kind: move (to the Yakushi trash) | delete (caches)"""
    if not (path.exists() or path.is_symlink()):
        return
    if personal is not None and untouchable(path, personal):
        return
    size, partial = size_of(path)
    found.add({"id": f"{kind}:{rel(path)}", "group": group, "title": title, "path": rel(path),
               "note": note, "size": size, "partial": partial, "checked": checked, "root": False, "kind": kind})


def scan_packages(found: Found, pkgs: set[str]) -> None:
    if shutil.which("paccache"):
        for flag, key, title, note in (
                ("-dk1", "old", "Old package versions", "the version you have installed is kept"),
                ("-duk0", "removed", "Packages of removed programs", "cached downloads of programs that are gone")):
            out = run(["paccache", flag, "-q"], 60)
            m = re.search(r"(\d+) candidates? \(disk space saved: ([\d.]+) ([KMGT]?i?B)\)", out.stdout + out.stderr)
            if m and int(m.group(1)) > 0:
                found.add({"id": f"root:pkgcache-{key}", "group": "packages", "title": title,
                           "note": f"{m.group(1)} files in /var/cache/pacman/pkg; {note}",
                           "size": removectl.parse_size(m.group(2) + " " + m.group(3)), "partial": False,
                           "checked": True, "root": True, "kind": "root"})
    try:
        partial = [e.name for e in os.scandir("/var/cache/pacman/pkg")
                   if e.name.startswith("download-") and e.is_dir(follow_symlinks=False)]
    except OSError:
        partial = []
    if partial:
        found.add({"id": "root:downloads", "group": "packages", "title": "Unfinished package downloads",
                   "note": f"{len(partial)} folders left by interrupted updates", "size": 0, "partial": True,
                   "checked": True, "root": True, "kind": "root"})
    orphans = [n for n in run(["pacman", "-Qdtq"], 20).stdout.split() if NAME_RE.match(n)]
    kernel = removectl.running_kernel_pkg()
    orphans = [n for n in orphans if not removectl.protected(n, kernel)]
    if orphans:
        size = 0
        info = run(["pacman", "-Qi", "--", *orphans], 20).stdout
        for m in re.finditer(r"^Installed Size\s*:\s*(.+)$", info, re.M):
            size += removectl.parse_size(m.group(1))
        found.add({"id": "root:orphans", "group": "packages", "title": "Packages nothing needs",
                   "note": ", ".join(orphans[:12]) + (" ..." if len(orphans) > 12 else ""), "names": orphans,
                   "size": size, "partial": False, "checked": True, "root": True, "kind": "root"})
    usage = run(["journalctl", "--disk-usage"], 20).stdout
    m = re.search(r"take up ([\d.]+)([KMGT]?)(i?B)?", usage)
    if m:
        size = removectl.parse_size(f"{m.group(1)} {m.group(2) or ''}iB")
        if size > 200 * 1024 * 1024:
            found.add({"id": "root:journal", "group": "packages", "title": "System logs older than two weeks",
                       "note": f"the logs take {m.group(1)} {m.group(2)}B now", "size": 0, "partial": True,
                       "checked": True, "root": True, "kind": "root"})


def scan_leftovers(found: Found, pkgs: set[str], personal: set[Path]) -> None:
    owners = pkgs | in_path() | flatpak_names()
    for base, where in ((CONFIG, "settings"), (DATA, "data"), (STATE, "state"), (CACHE, "cache")):
        try:
            entries = sorted(os.scandir(base), key=lambda e: e.name.lower())
        except OSError:
            continue
        for entry in entries:
            name = entry.name
            for rx, owners_of, label in KNOWN_RE:
                if rx.match(name):
                    if not any(p in pkgs for p in owners_of):
                        file_item(found, "leftovers", Path(entry.path), label,
                                  f"{where} of a program that is not installed", True,
                                  "delete" if base == CACHE else "move", personal)
                    break
            else:
                # Yakushi-style backups of a whole folder: ~/.config/quickshell-before-x
                if entry.is_dir(follow_symlinks=False) and BACKUP_DIR.search(name) or \
                        re.search(r"-before-|\.bak\d*$", name, re.I):
                    file_item(found, "backups", Path(entry.path), "Old copy", "a backup of a folder", True,
                              "move", personal)
    # ~/.cache folders of programs that are gone (no package, command or Flatpak by that name)
    try:
        for entry in os.scandir(CACHE):
            name = entry.name.lower()
            if not entry.is_dir(follow_symlinks=False) or name in KEEP_NAMES or f"delete:{rel(Path(entry.path))}" in found.ids:
                continue
            stem = re.split(r"[-_. ]", name)[0]
            if name in owners or stem in owners or len(stem) < 4:
                continue
            if re.match(r"^(mesa|radv|nvidia|qtshadercache|thumbnails|fontconfig|gstreamer|glycin|gnome|gtk|"
                        r"event-sound|p10k|zcompdump|imagemagick|deno|yt-dlp|vim|cliphist|awww|hyprland)", name):
                continue
            file_item(found, "leftovers", Path(entry.path), entry.name,
                      "cache of a program that is not installed", True, "delete", personal)
    except OSError:
        pass
    for name, (owners_of, label) in HOME_TOOLS.items():
        if not any(p in pkgs for p in owners_of):
            file_item(found, "leftovers", HOME / name, label, "a tool folder; the tool is not installed", True,
                      "delete", personal)
    for name, owner in HYPR_LEFT.items():
        if owner not in pkgs:
            file_item(found, "leftovers", CONFIG / "hypr" / name, owner, f"config of {owner}, which is not installed",
                      True, "move", personal)


def scan_backups(found: Found, personal: set[Path]) -> None:
    def files_in(folder: Path, depth: int) -> None:
        try:
            entries = list(os.scandir(folder))
        except OSError:
            return
        for entry in entries:
            p = Path(entry.path)
            if entry.is_dir(follow_symlinks=False):
                if depth > 0 and entry.name.lower() not in ("yakushi", "yakushi-trash", "trash", "flatpak", "claude"):
                    files_in(p, depth - 1)
            elif BACKUP_FILE.search(entry.name):
                file_item(found, "backups", p, entry.name, "a backup copy of a file", True, "move", personal)

    files_in(CONFIG, 2)
    try:
        for entry in os.scandir(HOME):
            p = Path(entry.path)
            if entry.name.startswith(".") or untouchable(p, personal):
                continue
            if entry.is_dir(follow_symlinks=False) and BACKUP_DIR.search(entry.name):
                file_item(found, "backups", p, entry.name, "a backup folder", True, "move", personal)
            elif entry.is_file(follow_symlinks=False) and re.search(r"(backup|rescue|before|bak).*\.(tar(\.\w+)?|zip|tgz)$",
                                                                   entry.name, re.I):
                file_item(found, "backups", p, entry.name, "a backup archive", True, "move", personal)
    except OSError:
        pass


def git(path: Path, *args: str) -> str:
    res = run(["git", "-C", str(path), *args], 10)
    return res.stdout.strip() if res.returncode == 0 else ""


def scan_clones(found: Found, personal: set[Path]) -> None:
    """Git clones of the same repository: every clean, fully pushed one but the
    newest is just a copy (it can be cloned again)."""
    candidates: list[Path] = []
    for folder in (HOME, HOME / "Projects"):
        try:
            for entry in os.scandir(folder):
                p = Path(entry.path)
                if entry.is_dir(follow_symlinks=False) and not entry.name.startswith(".") and (p / ".git").exists():
                    candidates.append(p)
        except OSError:
            pass
    by_remote: dict[str, list[tuple[int, Path, bool]]] = {}
    for repo in candidates:
        remote = git(repo, "remote", "get-url", "origin")
        if not remote:
            continue
        clean = git(repo, "status", "--porcelain") == "" and run(["git", "-C", str(repo), "status", "--porcelain"], 10).returncode == 0
        pushed = git(repo, "rev-parse", "@{u}") != "" and git(repo, "log", "--oneline", "@{u}..") == ""
        when = int(git(repo, "log", "-1", "--format=%ct") or 0)
        by_remote.setdefault(remote.rstrip("/").removesuffix(".git").lower(), []).append((when, repo, clean and pushed))
    for remote, repos in by_remote.items():
        if len(repos) < 2:
            continue
        repos.sort(key=lambda r: r[0], reverse=True)
        for when, repo, safe in repos[1:]:
            if safe and not untouchable(repo, personal):
                file_item(found, "backups", repo, repo.name,
                          f"an older copy of {remote.split('/')[-1]}: clean, everything pushed, a newer copy exists",
                          True, "move", personal)


def scan_links(found: Found, personal: set[Path]) -> None:
    def walk(folder: Path, depth: int) -> None:
        try:
            entries = list(os.scandir(folder))
        except OSError:
            return
        for entry in entries:
            p = Path(entry.path)
            if entry.name in (".var", ".cache", ".git", "node_modules", ".steam", ".local", ".claude"):
                continue
            if entry.is_symlink():
                if not p.exists():
                    file_item(found, "links", p, entry.name, "a link to something that is gone", True, "move", personal)
            elif entry.is_dir(follow_symlinks=False) and depth > 0:
                walk(p, depth - 1)

    walk(HOME, 3)
    walk(DATA, 1)
    walk(paths.HOME / ".local/bin", 0)
    apps = DATA / "applications"
    try:
        entries = list(os.scandir(apps))
    except OSError:
        entries = []
    for entry in entries:
        if not entry.name.endswith(".desktop") or not entry.is_file():
            continue
        try:
            text = Path(entry.path).read_text(errors="replace")
        except OSError:
            continue
        m = re.search(r"^Exec\s*=\s*(.+)$", text, re.M)
        if not m:
            continue
        program = m.group(1).strip().split()[0].strip('"')
        if program in ("env", "flatpak", "sh", "bash"):
            continue
        exists = Path(os.path.expanduser(program)).exists() if "/" in program else shutil.which(program) is not None
        if not exists:
            file_item(found, "links", Path(entry.path), entry.name,
                      f"an app-list entry for {Path(program).name}, which is gone", True, "move", personal)


def scan_caches(found: Found) -> None:
    thumbs = CACHE / "thumbnails"
    file_item(found, "caches", thumbs, "Thumbnails", "picture previews; made again when needed", True, "delete")
    var = HOME / ".var/app"
    try:
        apps = sorted(os.scandir(var), key=lambda e: e.name)
    except OSError:
        apps = []
    for app in apps:
        known = APP_CACHES.get(app.name)
        if known:
            file_item(found, "caches", Path(app.path) / known[0], known[1], known[2], False, "delete")
            continue
        cache = Path(app.path) / "cache"
        size, partial = size_of(cache, 0.6)
        if size >= BIG_CACHE:
            found.add({"id": f"delete:{rel(cache)}", "group": "caches", "title": app.name.split(".")[-1],
                       "path": rel(cache), "note": "app cache; the app may sign you out or download things again",
                       "size": size, "partial": partial, "checked": False, "root": False, "kind": "delete"})


def scan_trash(found: Found) -> None:
    trash = DATA / "Trash"
    files = trash / "files"
    try:
        count = len(os.listdir(files))
    except OSError:
        return
    if count:
        size, partial = size_of(trash, 1.5)
        found.add({"id": "trash", "group": "trash", "title": "Your Trash",
                   "note": f"{count} things you threw away; emptying deletes them for good",
                   "path": rel(trash), "size": size, "partial": partial, "checked": False, "root": False,
                   "kind": "trash"})


GROUPS = [
    ("packages", "PACKAGES", "needs your password"),
    ("leftovers", "LEFTOVERS OF REMOVED PROGRAMS", ""),
    ("backups", "OLD BACKUPS AND COPIES", ""),
    ("links", "BROKEN LINKS", ""),
    ("caches", "CACHES", ""),
    ("trash", "TRASH", ""),
]


def scan() -> dict:
    started = time.monotonic()
    pkgs = installed_packages()
    personal = personal_roots()
    found = Found()
    scan_packages(found, pkgs)
    scan_leftovers(found, pkgs, personal)
    scan_backups(found, personal)
    scan_clones(found, personal)
    scan_links(found, personal)
    scan_caches(found)
    scan_trash(found)
    # one entry per path: a path found twice keeps the first (the clearer) reason
    seen, items = set(), []
    for item in found.items:
        key = item.get("path") or item["id"]
        if key in seen:
            continue
        # a folder inside one already listed would be counted twice
        if item.get("path") and any(item["path"].startswith(s + "/") for s in seen if s.startswith("~/")):
            continue
        seen.add(key)
        items.append(item)
    order = {g[0]: i for i, g in enumerate(GROUPS)}
    items.sort(key=lambda i: (order[i["group"]], -i["size"]))
    return {"ok": True, "items": items, "groups": [{"key": k, "title": t, "note": n} for k, t, n in GROUPS],
            "seconds": round(time.monotonic() - started, 1)}


# ---------------------------------------------------------------------------
# Cleaning
# ---------------------------------------------------------------------------

ROOT_SCRIPT = r'''
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in
        pkgcache-old)     paccache -rk1 -q >/dev/null 2>&1; echo "STEP pkgcache-old $?" ;;
        pkgcache-removed) paccache -ruk0 -q >/dev/null 2>&1; echo "STEP pkgcache-removed $?" ;;
        journal)          journalctl --vacuum-time=2weeks >/dev/null 2>&1; echo "STEP journal $?" ;;
        downloads)        find /var/cache/pacman/pkg -mindepth 1 -maxdepth 1 -type d -name 'download-*' \
                              -exec rm -rf -- {} + ; echo "STEP downloads $?" ;;
    esac
    shift
done
shift
if [ $# -gt 0 ]; then
    pacman -Rns --noconfirm -- "$@" >/dev/null 2>&1; echo "STEP orphans $?"
fi
exit 0
'''


def as_root_steps(steps: list[str], orphans: list[str]) -> tuple[str, dict[str, bool]]:
    """('ok'|'wrong'|'cancel'|'notallowed'|'failed', {step: worked})"""
    cmd = ["/bin/sh", "-c", ROOT_SCRIPT, "yakushi-clean", *steps, "--", *orphans]
    try:
        if tasks.PASSWORD is not None:
            res = subprocess.run(["sudo", "-S", "-k", "-p", "", "--", *cmd], input=tasks.PASSWORD + "\n",
                                 capture_output=True, text=True, timeout=1800)
            err = res.stderr or ""
            if "incorrect password" in err or "Sorry, try again" in err:
                return "wrong", {}
            if "not in the sudoers" in err or "not allowed to" in err or "may not run sudo" in err:
                return "notallowed", {}
        else:
            res = subprocess.run(["pkexec", *cmd], capture_output=True, text=True, timeout=1800)
            if res.returncode in (126, 127):
                return "cancel", {}
    except FileNotFoundError:
        return "failed", {}
    except subprocess.TimeoutExpired:
        return "failed", {}
    done = {m.group(1): m.group(2) == "0" for m in re.finditer(r"^STEP (\S+) (\d+)$", res.stdout, re.M)}
    return "ok", done


def delete(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def clean(request: dict, dry: bool) -> dict:
    wanted = request.get("ids")
    if not isinstance(wanted, list) or not all(isinstance(i, str) for i in wanted):
        return {"ok": False, "message": "Bad request."}
    fresh = {i["id"]: i for i in scan()["items"]}
    chosen = [fresh[i] for i in wanted if i in fresh]          # only what the fresh scan found
    if not chosen:
        return {"ok": False, "message": "Nothing to clean (it may be gone already)."}
    personal = personal_roots()
    report: list[str] = []
    problems: list[str] = []
    freed = 0

    # 1. root: one password for every package step
    root_items = [i for i in chosen if i["kind"] == "root"]
    if root_items:
        steps = [i["id"].removeprefix("root:") for i in root_items if i["id"] != "root:orphans"]
        orphans = next((i.get("names", []) for i in root_items if i["id"] == "root:orphans"), [])
        orphans = [n for n in orphans if NAME_RE.match(n)]
        if dry:
            report += [f"would run as root: {s}" for s in steps] + ([f"would remove: {' '.join(orphans)}"] if orphans else [])
        else:
            result, done = as_root_steps(steps, orphans)
            if result in ("wrong", "cancel", "notallowed"):
                return {"ok": False, "wrongPassword": result == "wrong", "message": tasks.ROOT_MESSAGES[result]}
            for item in root_items:
                step = item["id"].removeprefix("root:")
                if done.get(step):
                    freed += item["size"]
                else:
                    problems.append(f"{item['title']} did not work")

    # 2. your files: to the Yakushi trash (UNDO in REMOVED BEFORE)
    to_move = [i for i in chosen if i["kind"] == "move"]
    moved = []
    box = None
    for item in to_move:
        src = HOME / item["path"].removeprefix("~/")
        if untouchable(src, personal) or not (src.exists() or src.is_symlink()):
            continue
        if dry:
            report.append(f"would move to the Yakushi trash: {item['path']}")
            continue
        if box is None:
            box = removectl.stamp_dir("clean-up")
        try:
            removectl.move_out(src, box / "files" / item["path"].removeprefix("~/"))
            moved.append({"path": item["path"], "size": item["size"]})
            freed += item["size"]
        except OSError as error:
            problems.append(f"could not move {item['path']} ({error.strerror})")
    if box is not None:
        box.mkdir(parents=True, exist_ok=True)
        (box / "manifest.json").write_text(json.dumps({
            "id": box.name, "time": int(time.time()), "target": ["clean-up"], "cascade": False,
            "titles": ["Clean up"], "packages": [], "flatpaks": [], "needsRoot": False,
            "unitsSystem": [], "unitsUser": [], "files": moved, "freed": sum(m["size"] for m in moved),
        }, indent=2))

    # 3. caches and the Trash: deleted
    for item in chosen:
        if item["kind"] not in ("delete", "trash"):
            continue
        target = HOME / item["path"].removeprefix("~/")
        if item["kind"] == "delete" and untouchable(target, personal) and not target.is_relative_to(HOME / ".var/app"):
            continue
        if dry:
            report.append(f"would delete: {item['path']}")
            continue
        try:
            if item["kind"] == "trash":
                for part in ("files", "info", "expunged"):
                    folder = target / part
                    if folder.is_dir():
                        for child in folder.iterdir():
                            delete(child)
            else:
                delete(target)
            freed += item["size"]
        except OSError as error:
            problems.append(f"could not delete {item['path']} ({error.strerror})")

    if dry:
        return {"ok": True, "dryRun": True, "report": report, "message": f"Dry run: {len(report)} steps."}
    message = f"Cleaned {len(chosen) - len(problems)} of {len(chosen)}; about {human(freed)} freed."
    if moved:
        message += f" {len(moved)} of your files are in the Yakushi trash: REMOVED BEFORE -> UNDO brings them back."
    if problems:
        message += " But: " + "; ".join(problems) + "."
    return {"ok": True, "message": message, "freed": freed, "id": box.name if box else ""}


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit in ("B", "KB") else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def main() -> None:
    args = tasks.take_password(sys.argv[1:])
    dry = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    try:
        if args == ["scan"]:
            emit(scan())
        elif len(args) == 2 and args[0] == "clean":
            try:
                request = json.loads(args[1])
            except ValueError:
                request = None
            emit(clean(request, dry) if isinstance(request, dict) else {"ok": False, "message": "Bad request."})
        else:
            emit({"ok": False, "message": "usage: scan | clean <json> [--dry-run] [--password-stdin]"})
    except Exception as error:                   # always answer the page
        emit({"ok": False, "message": f"Unexpected error: {error}"})


if __name__ == "__main__":
    main()
