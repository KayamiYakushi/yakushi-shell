#!/usr/bin/env python3
"""Remove a program and what it left behind. Used by Settings -> Programs.

    yakushi-removectl.py catalog            everything installed, in one answer: every
                                            pacman package (with its app name and icon
                                            when it has one) and every Flatpak app, and
                                            what the Yakushi trash holds. The page
                                            searches, sorts and counts this itself.
    yakushi-removectl.py search <text> [mine|all|unused] [name|size]
                                            installed packages matching the text: the
                                            ones you installed (default), all, or the
                                            unused ones (dependencies nothing needs now)
    yakushi-removectl.py plan <json>        what removing would do, changes nothing
    yakushi-removectl.py remove <json>      do it
    yakushi-removectl.py removed            what was removed before (the Yakushi trash)
    yakushi-removectl.py undo <id>          put it back: reinstall, restore files, re-enable
    yakushi-removectl.py empty <id>         delete those saved files for good
    yakushi-removectl.py empty-all          empty the whole Yakushi trash

<json> is {"target": ["name", "flatpak:<app id>", ...], "cascade": false, "files": ["~/.config/x", ...]}
(a target that starts with "flatpak:" is a Flatpak app: flatpak uninstall, its
data folder ~/.var/app/<id> to the Yakushi trash, and UNDO installs it again
from the same remote)
("cascade": also remove the programs that need it; "files": which of the
found files in your home folder go - for `remove` only).

What `plan` looks at:
  * the packages that go: the target, and its dependencies nothing else
    needs (pacman -Rns), or with "cascade" the programs that need it too
  * programs that need it (then nothing goes until you allow "cascade")
  * protected packages: the base system, kernels, boot and keyrings, and
    what Yakushi itself runs on - these are never removed here
  * running processes of those packages (closed after the removal)
  * services they ship that are enabled or running (disabled and stopped)
  * files in your home folder with the program's name (~/.config,
    ~/.local/share, ~/.local/state, ~/.cache, ~/.<name>, autostart entries):
    they are moved to ~/.local/share/yakushi-trash, not deleted, so UNDO
    can bring everything back until you empty it
  * lines in your Hyprland config that start it (shown, not edited)

The removal itself is one call as root: stop and disable the services, then
pacman -Rns (-n also deletes the system config files instead of leaving
.pacsave copies). With --password-stdin your password (first line of stdin,
from the field in Settings) goes to sudo through a pipe; without it pkexec
asks. A wrong or missing password changes nothing.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import yakushi_paths as paths

HERE = paths.SCRIPTS
HOME = paths.HOME
TRASH = paths.TRASH
NAME_RE = re.compile(r"^[A-Za-z0-9@._+-]+$")
UNIT_RE = re.compile(r"^[A-Za-z0-9@._:+\-]+\.(service|socket|timer|path)$")
FLATPAK = "flatpak:"
APP_ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)+$")
WORD_RE = re.compile(r"^[A-Za-z0-9._-]+$")
C_LOCALE = {"LC_ALL": "C"}             # pacman and flatpak answer in English for the parsers

sys.dont_write_bytecode = True            # no __pycache__ next to your config
_spec = importlib.util.spec_from_file_location("yakushi_taskctl", HERE / "yakushi-taskctl.py")
tasks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tasks)

# never removed here: Linux, booting, package keys, and what Yakushi runs on
HARD = {
    "base", "filesystem", "glibc", "gcc-libs", "bash", "coreutils", "util-linux", "systemd", "systemd-libs",
    "systemd-sysvcompat", "pacman", "pacman-mirrorlist", "archlinux-keyring", "sudo", "shadow", "pam",
    "dbus", "dbus-broker", "dbus-broker-units", "polkit", "mkinitcpio", "dracut", "linux-firmware",
    "grub", "efibootmgr", "limine", "refind", "os-prober", "amd-ucode", "intel-ucode",
    "mesa", "vulkan-radeon", "vulkan-intel", "nvidia", "nvidia-open", "nvidia-utils",
    "hyprland", "quickshell", "python", "fish", "sddm", "networkmanager", "pipewire", "wireplumber",
    "xdg-desktop-portal-hyprland", "hyprpolkitagent", "ttf-jetbrains-mono-nerd", "noto-fonts-cjk", "qt6ct",
}
HARD_PATTERNS = [re.compile(p) for p in (
    r"^linux(-[a-z0-9]+)*$",              # kernels (linux, linux-lts, linux-cachyos, ...)
    r".*-keyring$", r".*-mirrorlist$", r"^cachyos-(settings|hooks|kernel-manager)$",
)]
KERNEL_EXTRA = re.compile(r"^linux.*-(headers|docs)$")      # these may go

# Yakushi uses these for one feature each: allowed, with a warning
SOFT = {
    "kitty": "the default terminal (SUPER + Q)", "nautilus": "the default file manager (SUPER + E)",
    "firefox": "the default browser (SUPER + B)", "wl-clipboard": "copy and paste in scripts",
    "cliphist": "clipboard history (SUPER + V)", "libnotify": "test notifications (Settings)", "grim": "screenshots", "slurp": "area screenshots",
    "brightnessctl": "screen brightness keys", "hyprsunset": "night light",
    "playerctl": "now playing in the top bar", "pavucontrol": "advanced sound settings", "cava": "the visualizer",
    "awww": "wallpapers", "jq": "a few scripts", "imagemagick": "picture previews", "bluez": "Bluetooth",
    "bluez-utils": "Bluetooth", "pipewire-pulse": "sound for most apps", "noto-fonts": "the interface font",
    "xdg-desktop-portal-gtk": "file pickers and light/dark apps", "dconf": "light/dark apps",
    "gsettings-desktop-schemas": "light/dark apps", "pciutils": "the GPU name in System", "xdg-utils": "opening links",
    "qt6-imageformats": "picture formats", "hyprtoolkit": "Hyprland dialogs",
}

# where some well-known apps keep their data (paths under your home folder)
KNOWN_DATA = {
    "firefox": [".mozilla/firefox", ".cache/mozilla/firefox"],
    "thunderbird": [".thunderbird", ".cache/thunderbird"],
    "chromium": [".config/chromium", ".cache/chromium"],
    "google-chrome": [".config/google-chrome", ".cache/google-chrome"],
    "brave-bin": [".config/BraveSoftware", ".cache/BraveSoftware"],
    "code": [".vscode-oss", ".config/Code - OSS"],
    "visual-studio-code-bin": [".vscode", ".config/Code"],
    "steam": [".steam", ".local/share/Steam"],
    "obs-studio": [".config/obs-studio"],
    "gimp": [".config/GIMP", ".cache/gimp"],
    "libreoffice-fresh": [".config/libreoffice"], "libreoffice-still": [".config/libreoffice"],
    "telegram-desktop": [".local/share/TelegramDesktop"],
    "spotify-launcher": [".local/share/spotify-launcher", ".config/spotify", ".cache/spotify"],
}
# big folders that hold your own things: found, but not ticked by default
PERSONAL = {".local/share/Steam": "your installed Steam games are in here", ".steam": "Steam's links to your games",
            ".mozilla/firefox": "bookmarks, passwords and history", ".thunderbird": "your mail",
            ".local/share/TelegramDesktop": "your Telegram session"}
# Flatpak apps whose data folder holds your own things: found, not ticked
FLATPAK_PERSONAL = {
    "com.valvesoftware.Steam": "your installed Steam games may be in here",
    "org.prismlauncher.PrismLauncher": "your Minecraft instances and worlds",
    "app.zen_browser.zen": "bookmarks, passwords and history",
    "org.mozilla.firefox": "bookmarks, passwords and history",
    "io.gitlab.librewolf-community": "bookmarks, passwords and history",
    "com.google.Chrome": "bookmarks, passwords and history",
    "com.brave.Browser": "bookmarks, passwords and history",
    "org.mozilla.Thunderbird": "your mail",
    "org.telegram.desktop": "your Telegram session",
}
XDG_BASES = (paths.CONFIG_HOME, paths.DATA_HOME, paths.STATE_HOME, paths.CACHE_HOME)


def known_path(rel: str) -> Path:
    """A KNOWN_DATA entry (written relative to a default home) where it really
    is: .config/, .cache/, .local/share/ and .local/state/ follow the XDG
    folders, as the programs themselves do."""
    for prefix, base in ((".config/", paths.CONFIG_HOME), (".cache/", paths.CACHE_HOME),
                         (".local/share/", paths.DATA_HOME), (".local/state/", paths.STATE_HOME)):
        if rel.startswith(prefix):
            return base / rel[len(prefix):]
    return HOME / rel


# folders Yakushi itself manages or writes to
YAKUSHI_DIRS = {"hypr", "quickshell", "hyprpolkitagent", "qt6ct", "fish", "kitty", "yakushi",
                "yakushi-trash", "yakushi-shell", "gtk-3.0", "gtk-4.0", "systemd", "autostart", "applications", "icons", "fonts"}
GENERIC = {"python", "lib", "share", "config", "data", "cache", "bin", "gtk", "qt", "x11", "fonts", "icons", "themes",
           "sounds", "applications", "systemd", "dbus", "pulse", "pipewire", "mime", "user", "default", "common",
           "local", "state", "tmp", "log", "logs", "run", "env", "utils", "tools", "core", "base", "desktop"}


def emit(obj: dict) -> None:
    print(json.dumps(obj))


def run(cmd: list[str], timeout: int = 60, env: dict | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                              env={**os.environ, **env} if env else None)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]} is not installed")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", f"{cmd[0]} took too long")


# ---- protection ----------------------------------------------------------------------
def running_kernel_pkg() -> str:
    res = run(["pacman", "-Qqo", f"/usr/lib/modules/{os.uname().release}/vmlinuz"], 10)
    return res.stdout.strip() if res.returncode == 0 else ""


def protected(name: str, kernel: str) -> str:
    """'' or why this package is never removed here"""
    if name == kernel:
        return "the kernel you are running"
    if KERNEL_EXTRA.match(name):
        return ""
    if name in HARD or any(p.match(name) for p in HARD_PATTERNS):
        if name in ("hyprland", "quickshell", "python", "fish", "sddm", "xdg-desktop-portal-hyprland",
                    "hyprpolkitagent", "ttf-jetbrains-mono-nerd", "noto-fonts-cjk", "qt6ct"):
            return "Yakushi runs on it"
        if name.startswith("linux"):
            return "a kernel: your computer boots with it"
        return "the base system needs it"
    return ""


# ---- what goes ------------------------------------------------------------------------
def pacman_plan(targets: list[str], cascade: bool) -> tuple[list[str], dict[str, list[str]], str]:
    """(packages that go, {package: [needed by]} when blocked, error)"""
    # (-n cannot go with --print; the list is the same without it)
    flags = "-Rscp" if cascade else "-Rsp"
    res = run(["pacman", flags, "--print-format", "%n", *targets], 60, C_LOCALE)
    if res.returncode == 0:
        return [l.strip() for l in res.stdout.splitlines() if l.strip() and not l.startswith(("::", "warning"))], {}, ""
    blocked: dict[str, list[str]] = {}
    for line in (res.stderr + res.stdout).splitlines():
        m = re.search(r"removing (\S+) breaks dependency '([^']+)' required by (\S+)", line)
        if m:
            blocked.setdefault(m.group(1), []).append(m.group(3))
    if blocked:
        return [], blocked, ""
    err = [l for l in res.stderr.splitlines() if l.strip()]
    return [], {}, (err[-1].removeprefix("error: ") if err else "pacman could not plan this.")


def package_files(names: list[str]) -> list[str]:
    res = run(["pacman", "-Qlq", *names], 60)
    return [l.strip() for l in res.stdout.splitlines() if l.strip()]


def unit_state(unit: str, user: bool) -> tuple[bool, bool]:
    base = ["systemctl"] + (["--user"] if user else [])
    enabled = run(base + ["is-enabled", unit], 10).stdout.strip() in ("enabled", "enabled-runtime", "linked")
    active = run(base + ["is-active", unit], 10).stdout.strip() in ("active", "activating", "reloading")
    return enabled, active


def units_of(files: list[str]) -> dict[str, list[str]]:
    """the services they ship that are enabled or running: one systemctl call
    per scope for all of them (it was two per unit)"""
    want: dict[str, list[str]] = {"system": [], "user": []}
    for f in files:
        m = re.match(r"^/usr/lib/systemd/(system|user)/([^/]+\.(service|socket|timer|path))$", f)
        if m and "@." not in m.group(2):              # templates are never enabled as such
            want[m.group(1)].append(m.group(2))
    out: dict[str, list[str]] = {"system": [], "user": []}
    for scope, units in want.items():
        if not units:
            continue
        base = ["systemctl"] + (["--user"] if scope == "user" else [])
        res = run(base + ["show", "-p", "UnitFileState,ActiveState", "--", *units], 20)
        blocks = [b for b in res.stdout.strip().split("\n\n")] if res.returncode == 0 else []
        if len(blocks) != len(units):                   # an odd answer: ask one by one
            for u in units:
                enabled, active = unit_state(u, scope == "user")
                if enabled or active:
                    out[scope].append(u)
            continue
        for unit, block in zip(units, blocks):
            kv = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
            if (kv.get("UnitFileState") in ("enabled", "enabled-runtime", "linked")
                    or kv.get("ActiveState") in ("active", "activating", "reloading")):
                out[scope].append(unit)
    return out


def processes_of(files: list[str]) -> list[dict]:
    wanted = {f for f in files if f.startswith(("/usr/bin/", "/usr/lib/", "/opt/", "/usr/share/"))}
    out = []
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            exe = os.readlink(f"/proc/{pid}/exe").removesuffix(" (deleted)")
        except OSError:
            continue
        argv = tasks.cmdline(pid)
        script = tasks.script_of(argv)
        if exe in wanted or (script and script in wanted):
            st = tasks.stat(pid)
            if st:
                uid = tasks.uid_of(pid)
                out.append({"pid": pid, "start": st["start"], "name": tasks.display_name(st["comm"], argv),
                            "user": tasks.user_name(uid), "mine": uid == os.getuid()})
    return out


def candidate_names(targets: list[str], files: list[str]) -> set[str]:
    names = set()
    for t in targets:
        names.add(t.lower())
        for suffix in ("-bin", "-git", "-desktop", "-launcher", "-studio", "-fresh", "-still"):
            if t.lower().endswith(suffix):
                names.add(t.lower()[: -len(suffix)])
    for f in files:
        if f.startswith("/usr/bin/") and not f.endswith("/"):
            names.add(os.path.basename(f).lower())
        m = re.match(r"^/usr/share/applications/(.+)\.desktop$", f)
        if m:
            app_id = m.group(1)
            names.add(app_id.lower())
            names.add(app_id.split(".")[-1].lower())
            text = tasks.read(f)
            wm = re.search(r"^StartupWMClass=(.+)$", text, re.M)
            if wm:
                names.add(wm.group(1).strip().lower())
    return {n for n in names if len(n) >= 3 and n not in GENERIC}


def folder_size(path: Path, budget: float = 1.5) -> tuple[int, bool]:
    """bytes, and whether counting stopped early (huge folders)"""
    if path.is_symlink() or path.is_file():
        try:
            return path.lstat().st_size, False
        except OSError:
            return 0, False
    total, deadline = 0, time.monotonic() + budget
    for root, dirs, files in os.walk(path, onerror=lambda e: None):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
        if time.monotonic() > deadline:
            return total, True
    return total, False


def leftovers(targets: list[str], files: list[str]) -> list[dict]:
    names = candidate_names(targets, files)
    found: dict[str, dict] = {}

    def add(path: Path, note: str = "", checked: bool = True) -> None:
        if not path.is_relative_to(HOME):     # only files in your home are offered
            return
        rel = str(path.relative_to(HOME))
        if rel in found or not (path.exists() or path.is_symlink()):
            return
        # never Yakushi's own folders, wherever the XDG folders point
        if path.name.lower() in YAKUSHI_DIRS and path.parent in XDG_BASES:
            return
        size, partial = folder_size(path)
        if rel in PERSONAL:
            note, checked = PERSONAL[rel], False
        found[rel] = {"path": "~/" + rel, "size": size, "partial": partial, "checked": checked, "note": note}

    for t in targets:
        for rel in KNOWN_DATA.get(t, []):
            add(known_path(rel))

    def matches(entry: str) -> bool:
        e = entry.lower().lstrip(".")
        for ext in (".conf", ".json", ".toml", ".ini", ".yml", ".yaml", ".desktop", ".lock", ".log", "rc"):
            if e.endswith(ext) and e[: -len(ext)] in names:
                return True
        return e in names

    for base in XDG_BASES:
        try:
            entries = list(os.scandir(base))
        except OSError:
            continue
        for entry in entries:
            if entry.name.lower() in YAKUSHI_DIRS:
                continue
            if matches(entry.name):
                add(Path(entry.path))
    try:
        for entry in os.scandir(HOME):
            if entry.name.startswith(".") and entry.name not in (".config", ".local", ".cache") and matches(entry.name):
                add(Path(entry.path))
    except OSError:
        pass
    for folder in (paths.CONFIG_HOME / "autostart", paths.DATA_HOME / "applications", paths.CONFIG_HOME / "systemd/user"):
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        for entry in entries:
            stem = entry.name.rsplit(".", 1)[0].lower()
            if stem in names or stem.split(".")[-1] in names:
                add(Path(entry.path), "starts it or shows it in the app list")
    return sorted(found.values(), key=lambda f: f["path"])


def mentions(files: list[str]) -> list[str]:
    bins = sorted({os.path.basename(f) for f in files if f.startswith("/usr/bin/") and len(os.path.basename(f)) > 2})
    if not bins:
        return []
    out = []
    pats = [re.compile(r'(^|[\s/"\'(])' + re.escape(b) + r'($|[\s"\')])') for b in bins]
    for path in (paths.HYPR / "hyprland.lua", paths.HYPR / "keybinds.lua"):
        rel = str(path.relative_to(HOME)) if path.is_relative_to(HOME) else str(path)
        lines = tasks.read(path).splitlines()
        for i, line in enumerate(lines):
            code = line.split("--", 1)[0]
            if any(p.search(code) for p in pats):
                label = ""
                if rel.endswith("keybinds.lua") and i and "YAKUSHI_BIND" in lines[i - 1] and lines[i - 1].count("|") >= 2:
                    label = lines[i - 1].split("|")[2].strip()
                keys = re.match(r'\s*yakushi_bind\("[^"]+",\s*"([^"]+)"', line)
                if keys:
                    out.append(f"The shortcut {keys.group(1)}" + (f" ({label})" if label else "")
                               + " runs it: it will do nothing afterwards.")
                else:
                    out.append(f"~/{rel} line {i + 1} starts it: that line will fail quietly.")
    return out


def not_in_repos(names: list[str]) -> list[str]:
    """UNDO reinstalls from the official repositories: the ones it cannot
    (one pacman call for all of them; it was one per package)"""
    if not names:
        return []
    res = run(["pacman", "-Si", "--", *names], 30, C_LOCALE)
    found = set(re.findall(r"^Name\s*:\s*(\S+)", res.stdout, re.M))
    return [n for n in names if n not in found]


# ---- Flatpak apps ----------------------------------------------------------------------
SIZE_UNITS = {"B": 1, "bytes": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}


def parse_size(text: str) -> int:
    m = re.match(r"^\s*([\d.]+)\s*(\S+)", text or "")
    return int(float(m.group(1)) * SIZE_UNITS.get(m.group(2), 1)) if m else 0


def flatpak_apps() -> dict[str, dict]:
    """installed Flatpak apps by id (one `flatpak list`, ~15 ms)"""
    if not shutil.which("flatpak"):
        return {}
    res = run(["flatpak", "list", "--app",
               "--columns=application,name,description,version,branch,origin,installation,size"], 20, C_LOCALE)
    out: dict[str, dict] = {}
    for line in res.stdout.splitlines():
        f = line.split("\t")
        if len(f) < 8 or not APP_ID_RE.match(f[0]):
            continue
        app_id, title, desc, version, branch, origin, inst, size = f[:8]
        base = Path("/var/lib/flatpak") if inst == "system" else paths.DATA_HOME / "flatpak"
        try:
            installed = int((base / "app" / app_id / "current" / "active").stat().st_mtime)
        except OSError:
            installed = 0
        out[app_id] = {"id": app_id, "title": title or app_id, "desc": desc, "version": version, "branch": branch,
                       "origin": origin, "installation": inst, "size": parse_size(size), "installed": installed}
    return out


def install_flag(installation: str) -> list[str]:
    if installation == "system":
        return ["--system"]
    if installation == "user":
        return ["--user"]
    return [f"--installation={installation}"] if WORD_RE.match(installation) else ["--system"]


def flatpak_leftovers(app_id: str) -> list[dict]:
    found = []

    def add(path: Path, note: str, checked: bool = True) -> None:
        if path.exists() or path.is_symlink():
            size, partial = folder_size(path)
            found.append({"path": "~/" + str(path.relative_to(HOME)), "size": size, "partial": partial,
                          "checked": checked, "note": note})

    personal = FLATPAK_PERSONAL.get(app_id, "")
    add(HOME / ".var/app" / app_id, personal or "its settings, logins and cache", not personal)
    for folder in (paths.CONFIG_HOME / "autostart", paths.DATA_HOME / "applications"):
        add(folder / f"{app_id}.desktop", "starts it or shows it in the app list")
    return found


def flatpak_processes(ids: list[str]) -> list[dict]:
    """everything running in those apps' sandboxes (app-flatpak-<id>-<n>.scope)"""
    marks = [f"app-flatpak-{i}-" for i in ids]
    out = []
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if not any(m in tasks.read(f"/proc/{pid}/cgroup") for m in marks):
            continue
        st = tasks.stat(pid)
        if st:
            uid = tasks.uid_of(pid)
            out.append({"pid": pid, "start": st["start"], "name": tasks.display_name(st["comm"], tasks.cmdline(pid)),
                        "user": tasks.user_name(uid), "mine": uid == os.getuid()})
    return out


# ---- the catalog -----------------------------------------------------------------------
def read_desktop(path: str) -> dict | None:
    """Name and Icon of an app entry that shows in the app list"""
    fields: dict[str, str] = {}
    section = ""
    for line in tasks.read(path).splitlines():
        line = line.strip()
        if line.startswith("["):
            section = line
            continue
        if section == "[Desktop Entry]" and "=" in line:
            k, _, v = line.partition("=")
            fields.setdefault(k.strip(), v.strip())
    if fields.get("Type", "Application") != "Application":
        return None
    if fields.get("NoDisplay", "").lower() == "true" or fields.get("Hidden", "").lower() == "true":
        return None
    return {"title": fields.get("Name", ""), "icon": fields.get("Icon", "")} if fields.get("Name") else None


def package_apps() -> dict[str, dict]:
    """package -> the app it shows in the app list {title, icon}; read from
    pacman's file lists once per database state (cached)"""
    def build() -> dict[str, dict]:
        out: dict[str, dict] = {}
        try:
            entries = list(os.scandir(tasks.LOCAL_DB))
        except OSError:
            return out
        for e in entries:
            files = tasks.read(e.path + "/files")
            if "usr/share/applications/" not in files:
                continue
            name = (re.search(r"%NAME%\n(\S+)", tasks.read(e.path + "/desc")) or [None, ""])[1]
            if not name:
                continue
            for line in files.splitlines():
                if line.startswith("usr/share/applications/") and line.endswith(".desktop"):
                    d = read_desktop("/" + line)
                    if d:
                        out[name] = d
                        break
        return out
    return tasks.cached("apps-v1.json", tasks.db_key(), build)


def catalog() -> dict:
    """everything installed, once: the page filters, sorts and counts it
    itself, so typing in the search does not start a program per key"""
    with ThreadPoolExecutor(3) as pool:
        f_flatpaks = pool.submit(flatpak_apps)
        f_kernel = pool.submit(running_kernel_pkg)
        f_apps = pool.submit(package_apps)
        pkgs = tasks.load_packages()
        required_by, _ = tasks.reverse_deps(pkgs)
        apps, flatpaks, kernel = f_apps.result(), f_flatpaks.result(), f_kernel.result()
    items = []
    for p in pkgs.values():
        needed = sorted(required_by.get(p["name"], []))
        app = apps.get(p["name"])
        items.append({"id": p["name"], "kind": "pkg", "name": p["name"], "title": app["title"] if app else "",
                      "icon": app["icon"] if app else "", "app": app is not None, "desc": p["desc"],
                      "version": p["version"], "size": p["size"], "installed": p["installed"],
                      "explicit": p["explicit"], "unused": not p["explicit"] and not needed,
                      "protected": protected(p["name"], kernel), "neededBy": needed[:3], "neededCount": len(needed)})
    for f in flatpaks.values():
        items.append({"id": FLATPAK + f["id"], "kind": "flatpak", "name": f["id"], "title": f["title"],
                      "icon": f["id"], "app": True, "desc": f["desc"], "version": f["version"], "size": f["size"],
                      "installed": f["installed"], "explicit": True, "unused": False, "protected": "",
                      "neededBy": [], "neededCount": 0, "origin": f["origin"], "installation": f["installation"]})
    boxes = manifests()
    return {"ok": True, "items": items,
            "trash": {"count": len(boxes), "size": sum(b.get("keptSize", 0) for b in boxes)}}


def empty_plan(target: list[str], cascade: bool) -> dict:
    return {"ok": True, "target": target, "cascade": cascade, "blocked": {}, "protected": [], "remove": [],
            "running": [], "units": {"system": [], "user": []}, "files": [], "mentions": [], "soft": [],
            "freed": 0, "canRemove": False, "notInRepos": [], "flatpaks": [], "needsRoot": False, "titles": []}


def plan(request: dict) -> dict:
    raw = [t for t in request.get("target", []) if isinstance(t, str)]
    fp_ids = [t[len(FLATPAK):] for t in raw if t.startswith(FLATPAK) and APP_ID_RE.match(t[len(FLATPAK):])]
    targets = [t for t in raw if not t.startswith(FLATPAK) and NAME_RE.match(t)]
    if not targets and not fp_ids:
        return {"ok": False, "message": "Nothing given to remove."}
    cascade = request.get("cascade") is True
    out = empty_plan(targets + [FLATPAK + i for i in fp_ids], cascade)
    titles = []

    if targets:
        pkgs = tasks.load_packages()
        missing = [t for t in targets if pkgs and t not in pkgs]
        if missing:
            return {"ok": False, "message": "Not installed: " + ", ".join(missing)}
        apps = package_apps()
        titles += [apps[t]["title"] if t in apps else t for t in targets]
        with ThreadPoolExecutor(2) as pool:          # the slow parts run side by side
            f_kernel = pool.submit(running_kernel_pkg)
            names, blocked, err = pacman_plan(targets, cascade)
            kernel = f_kernel.result()
        if err:
            return {"ok": False, "message": err}
        if blocked:
            needed = {k: sorted(set(v)) for k, v in blocked.items()}
            out["blocked"] = needed
            out["protected"] = [{"name": n, "reason": protected(n, kernel)}
                                for by in needed.values() for n in by if protected(n, kernel)]
            out["titles"] = titles
            return out
        with ThreadPoolExecutor(2) as pool:
            f_norepo = pool.submit(not_in_repos, names)
            files = package_files(names) if names else []
            norepo = f_norepo.result()
        with ThreadPoolExecutor(3) as pool:
            f_units = pool.submit(units_of, files)
            f_left = pool.submit(leftovers, targets, files)
            f_running = pool.submit(processes_of, files)
            found_mentions = mentions(files)
            units, found, running = f_units.result(), f_left.result(), f_running.result()
        for n in names:
            info = pkgs.get(n, {})
            out["remove"].append({"name": n, "version": info.get("version", ""), "size": info.get("size", 0),
                                  "explicit": info.get("explicit", False), "desc": info.get("desc", ""),
                                  "why": "you chose it" if n in targets else ("installed by you" if info.get("explicit") else "a dependency nothing else needs")})
        out["protected"] = [{"name": n, "reason": protected(n, kernel)} for n in names if protected(n, kernel)]
        out["soft"] = [{"name": n, "reason": SOFT[n]} for n in names if n in SOFT]
        out.update(units=units, files=found, running=running, mentions=found_mentions, notInRepos=norepo,
                   freed=sum(r["size"] for r in out["remove"]), needsRoot=bool(names))

    if fp_ids:
        installed = flatpak_apps()
        missing = [i for i in fp_ids if i not in installed]
        if missing:
            return {"ok": False, "message": "Not installed: " + ", ".join(missing)}
        for i in fp_ids:
            f = installed[i]
            titles.append(f["title"])
            out["remove"].append({"name": f["title"], "id": FLATPAK + i, "version": f["version"], "size": f["size"],
                                  "explicit": True, "desc": f["desc"], "flatpak": True,
                                  "why": "you chose it · Flatpak from " + f["origin"]})
            out["flatpaks"].append({k: f[k] for k in ("id", "title", "origin", "installation", "branch", "version")})
            out["files"] += flatpak_leftovers(i)
            out["freed"] += f["size"]
            if f["installation"] != "user":
                out["needsRoot"] = True
        out["running"] += flatpak_processes(fp_ids)

    out["titles"] = titles
    out["canRemove"] = bool(out["remove"]) and not out["protected"]
    return out


# ---- doing it ------------------------------------------------------------------------
def end_processes(procs: list[dict]) -> None:
    mine = [p for p in procs if p["mine"]]
    for p in mine:
        tasks.send(p["pid"], p["start"], signal.SIGTERM)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and any(tasks.alive(p["pid"], p["start"]) for p in mine):
        time.sleep(0.1)
    for p in mine:
        if tasks.alive(p["pid"], p["start"]):
            tasks.send(p["pid"], p["start"], signal.SIGKILL)


def stamp_dir(target: str) -> Path:
    TRASH.mkdir(parents=True, exist_ok=True)
    base = time.strftime("%Y-%m-%d_%H-%M-%S") + "_" + target
    d, n = TRASH / base, 1
    while d.exists():
        n += 1
        d = TRASH / f"{base}-{n}"
    return d


def move_out(path: Path, store: Path) -> None:
    store.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(store))


def remove(request: dict) -> dict:
    p = plan(request)
    if not p.get("ok"):
        return p
    if p["blocked"]:
        return {"ok": False, "message": "Other programs need it. Allow removing them too, or keep it."}
    if p["protected"]:
        return {"ok": False, "message": "Protected: " + ", ".join(f"{g['name']} ({g['reason']})" for g in p["protected"])}
    if not p["remove"]:
        return {"ok": False, "message": "Nothing to remove."}
    names = [r["name"] for r in p["remove"] if not r.get("flatpak")]
    fps = [f for f in p["flatpaks"] if APP_ID_RE.match(f["id"])]
    chosen = {f.removeprefix("~/") for f in request.get("files", []) if isinstance(f, str)}
    files = [f for f in p["files"] if f["path"].removeprefix("~/") in chosen]       # only what plan found
    sys_units = [u for u in p["units"]["system"] if UNIT_RE.match(u)]
    user_units = [u for u in p["units"]["user"] if UNIT_RE.match(u)]
    if not all(NAME_RE.match(n) for n in names):
        return {"ok": False, "message": "Unexpected package name."}

    # 1. one password prompt: services off, then pacman (nothing changes if cancelled)
    gone, still, problems = [], [], []
    asked = False
    if names:
        script = ('while [ $# -gt 0 ] && [ "$1" != "--" ]; do systemctl disable --now "$1" >/dev/null 2>&1; shift; done; shift; '
                  'exec pacman ' + ("-Rnsc" if p["cascade"] else "-Rns") + ' --noconfirm "$@"')
        result, err = tasks.as_root(["/bin/sh", "-c", script, "yakushi-remove", *sys_units, "--", *names], 900)
        if result in ("wrong", "cancel", "notallowed"):
            return {"ok": False, "wrongPassword": result == "wrong", "message": tasks.ROOT_MESSAGES[result]}
        asked = True
        res = run(["pacman", "-Qq", "--", *names], 10)
        still = [n for n in names if n in set(res.stdout.split())]
        gone = [n for n in names if n not in still]
        if result != "ok" and not gone:
            problems.append("pacman did not remove it: " + (err or "unknown error"))

    # 1b. Flatpak apps (the system ones with the same password)
    for f in fps:
        cmd = ["flatpak", "uninstall", *install_flag(f["installation"]), "-y", "--noninteractive", "--force-remove", f["id"]]
        if f["installation"] == "user":
            res = run(cmd, 600)
            if res.returncode != 0:
                problems.append(f"{f['title']}: " + ((res.stderr or res.stdout).strip().splitlines() or ["flatpak failed"])[-1])
            continue
        result, err = tasks.as_root(cmd, 600)
        if result in ("wrong", "cancel", "notallowed") and not asked:
            return {"ok": False, "wrongPassword": result == "wrong", "message": tasks.ROOT_MESSAGES[result]}
        asked = True
        if result != "ok":
            problems.append(f"{f['title']}: " + (err or "flatpak could not remove it"))
    left = flatpak_apps() if fps else {}
    fp_gone = [f for f in fps if f["id"] not in left]
    if not gone and not fp_gone:
        return {"ok": False, "message": "; ".join(problems) or "Nothing was removed."}
    pkgs_info = {r["name"]: r for r in p["remove"] if not r.get("flatpak")}

    # 2. what kept running, your services
    end_processes(p["running"])
    for u in user_units:
        run(["systemctl", "--user", "disable", "--now", u], 30)

    # 3. your files -> the Yakushi trash, with a note on how to put it all back
    box = stamp_dir(re.sub(r"[^\w.@+-]", "_", (gone + [f["id"] for f in fp_gone])[0]))
    moved = []
    for f in files:
        src = HOME / f["path"].removeprefix("~/")
        if not (src.exists() or src.is_symlink()):
            continue
        store = box / "files" / f["path"].removeprefix("~/")
        try:
            move_out(src, store)
            moved.append({"path": f["path"], "size": f["size"]})
        except OSError:
            pass
    box.mkdir(parents=True, exist_ok=True)
    fp_sizes = {r["id"]: r["size"] for r in p["remove"] if r.get("flatpak")}
    titles = gone + [f["title"] for f in fp_gone]
    manifest = {
        "id": box.name, "time": int(time.time()), "target": p["target"], "cascade": p["cascade"], "titles": titles,
        "packages": [{"name": n, "explicit": pkgs_info[n]["explicit"], "version": pkgs_info[n]["version"]} for n in gone],
        "flatpaks": fp_gone, "needsRoot": bool(gone) or any(f["installation"] != "user" for f in fp_gone),
        "unitsSystem": sys_units, "unitsUser": user_units, "files": moved,
        "freed": sum(pkgs_info[n]["size"] for n in gone) + sum(fp_sizes.get(FLATPAK + f["id"], 0) for f in fp_gone)
                 + sum(m["size"] for m in moved),
    }
    (box / "manifest.json").write_text(json.dumps(manifest, indent=2))
    msg = f"Removed {', '.join(titles)}."
    if moved:
        msg += f" {len(moved)} of your files are in the Yakushi trash: UNDO puts everything back."
    if still:
        msg += f" Still installed: {', '.join(still)}."
    if problems:
        msg += " But: " + "; ".join(problems) + "."
    return {"ok": True, "message": msg, "id": box.name, "removed": titles, "moved": moved}


# ---- the trash -----------------------------------------------------------------------
def manifests() -> list[dict]:
    out = []
    try:
        boxes = sorted(TRASH.iterdir(), reverse=True)
    except OSError:
        return out
    for box in boxes:
        try:
            m = json.loads((box / "manifest.json").read_text())
        except (OSError, ValueError):
            continue
        m["id"] = box.name
        m["keptSize"] = sum(f.get("size", 0) for f in m.get("files", []))
        m.setdefault("titles", [p["name"] for p in m.get("packages", [])] or m.get("target", []))
        m.setdefault("flatpaks", [])
        m.setdefault("needsRoot", bool(m.get("packages")))
        out.append(m)
    return out


def find_box(box_id: str) -> Path | None:
    if not re.fullmatch(r"[\w.@+-]+", box_id):
        return None
    box = TRASH / box_id
    return box if (box / "manifest.json").exists() else None


def undo(box_id: str) -> dict:
    box = find_box(box_id)
    if box is None:
        return {"ok": False, "message": "Not in the Yakushi trash any more."}
    m = json.loads((box / "manifest.json").read_text())
    pkgs = [p["name"] for p in m.get("packages", []) if NAME_RE.match(p["name"])]
    deps = [p["name"] for p in m.get("packages", []) if not p.get("explicit") and NAME_RE.match(p["name"])]
    units = [u for u in m.get("unitsSystem", []) if UNIT_RE.match(u)]
    problems = []
    failed_steps = 0                       # reinstalls that did not work
    if pkgs:
        script = ('p=""; while [ $# -gt 0 ] && [ "$1" != "--" ]; do p="$p $1"; shift; done; shift; '
                  'pacman -S --needed --noconfirm $p || exit 3; '
                  'd=""; while [ $# -gt 0 ] && [ "$1" != "--" ]; do d="$d $1"; shift; done; shift; '
                  '[ -n "$d" ] && pacman -D --asdeps $d >/dev/null; '
                  'for u in "$@"; do systemctl enable --now "$u" >/dev/null 2>&1; done; exit 0')
        result, err = tasks.as_root(["/bin/sh", "-c", script, "yakushi-undo", *pkgs, "--", *deps, "--", *units], 1800)
        if result in ("wrong", "cancel", "notallowed"):
            return {"ok": False, "wrongPassword": result == "wrong", "message": tasks.ROOT_MESSAGES[result]}
        if result != "ok":
            failed_steps += 1
            problems.append("reinstalling failed (" + (err or "no internet, or not in the repositories") + ")")
    for f in m.get("flatpaks", []):
        if not (APP_ID_RE.match(f.get("id", "")) and WORD_RE.match(f.get("origin", ""))):
            continue
        ref = f["id"] + (f"//{f['branch']}" if WORD_RE.match(f.get("branch", "")) else "")
        cmd = ["flatpak", "install", *install_flag(f.get("installation", "system")), "-y", "--noninteractive",
               f["origin"], ref]
        if f.get("installation") == "user":
            res = run(cmd, 1800)
            ok, err = res.returncode == 0, (res.stderr or "").strip()
        else:
            result, err = tasks.as_root(cmd, 1800)
            if result in ("wrong", "cancel", "notallowed") and not pkgs:
                return {"ok": False, "wrongPassword": result == "wrong", "message": tasks.ROOT_MESSAGES[result]}
            ok = result == "ok"
        if not ok:
            failed_steps += 1
            problems.append(f"reinstalling {f.get('title', f['id'])} failed (" + (err.splitlines()[-1] if err else "no internet?") + ")")
    reinstalled = bool(pkgs) or bool(m.get("flatpaks"))
    restored = 0
    for f in m.get("files", []):
        rel = f["path"].removeprefix("~/")
        src, dst = box / "files" / rel, HOME / rel
        if not (src.exists() or src.is_symlink()):
            continue
        if dst.exists() or dst.is_symlink():
            dst = dst.with_name(dst.name + ".restored")
        try:
            move_out(src, dst)
            restored += 1
        except OSError:
            problems.append(f"could not restore {f['path']}")
    for u in m.get("unitsUser", []):
        if UNIT_RE.match(u):
            run(["systemctl", "--user", "enable", "--now", u], 30)
    steps = (1 if pkgs else 0) + len(m.get("flatpaks", []))
    if steps and failed_steps == steps and not restored:      # nothing came back: keep the box
        return {"ok": False, "message": "Could not put it back: " + "; ".join(problems)}
    shutil.rmtree(box, ignore_errors=True)
    what = m.get("titles") or pkgs
    msg = "Put back: " + (", ".join(what) if reinstalled else "your files") + (f" and {restored} files." if restored and reinstalled else ".")
    if problems:
        msg += " But: " + "; ".join(problems) + "."
    return {"ok": True, "message": msg}


def empty(box_id: str) -> dict:
    box = find_box(box_id)
    if box is None:
        return {"ok": False, "message": "Not in the Yakushi trash any more."}
    shutil.rmtree(box, ignore_errors=True)
    return {"ok": True, "message": "Deleted for good."}


def empty_all() -> dict:
    boxes = manifests()
    for m in boxes:
        box = find_box(m["id"])
        if box is not None:
            shutil.rmtree(box, ignore_errors=True)
    return {"ok": True, "message": f"Emptied the Yakushi trash ({len(boxes)} removal{'s' if len(boxes) != 1 else ''})."}


def search(text: str, scope: str = "mine", order: str = "name") -> dict:
    """scope: mine (installed by you), all, unused (dependencies nothing needs any more)
    order: name | size (largest first; sorted before the list is cut short)"""
    q = text.strip().lower()
    pkgs = tasks.load_packages()
    required_by, optional_for = tasks.reverse_deps(pkgs)
    kernel = running_kernel_pkg()
    unused = {n for n, p in pkgs.items() if not p["explicit"] and not required_by.get(n)}
    hits = []
    for p in pkgs.values():
        if scope == "mine" and not p["explicit"]:
            continue
        if scope == "unused" and p["name"] not in unused:
            continue
        if q and q not in p["name"].lower() and q not in p["desc"].lower():
            continue
        needed = sorted(required_by.get(p["name"], []))
        hits.append({"name": p["name"], "desc": p["desc"], "size": p["size"], "explicit": p["explicit"],
                     "protected": protected(p["name"], kernel), "neededBy": needed[:3], "neededCount": len(needed),
                     "optionalFor": sorted(optional_for.get(p["name"], []))[:3]})
    if order == "size":
        hits.sort(key=lambda h: (-h["size"], h["name"]))
    else:
        hits.sort(key=lambda h: (not h["name"].lower().startswith(q), h["name"]) if q else (h["name"],))
    limit = 400 if scope == "unused" else 120
    return {"ok": True, "scope": scope, "order": order, "packages": hits[:limit], "total": len(hits),
            "counts": {"mine": sum(1 for p in pkgs.values() if p["explicit"]), "all": len(pkgs), "unused": len(unused)}}


def main() -> None:
    a = tasks.take_password(sys.argv[1:])
    try:
        if len(a) in (2, 3, 4) and a[0] == "search":
            emit(search(a[1], a[2] if len(a) >= 3 and a[2] in ("mine", "all", "unused") else "mine",
                        a[3] if len(a) == 4 and a[3] in ("name", "size") else "name"))
        elif len(a) == 2 and a[0] in ("plan", "remove"):
            try:
                request = json.loads(a[1])
            except ValueError:
                request = None
            if not isinstance(request, dict):
                emit({"ok": False, "message": "Bad request."})
                return
            emit(plan(request) if a[0] == "plan" else remove(request))
        elif a == ["catalog"]:
            emit(catalog())
        elif a == ["empty-all"]:
            emit(empty_all())
        elif a == ["removed"]:
            emit({"ok": True, "removed": manifests()})
        elif len(a) == 2 and a[0] == "undo":
            emit(undo(a[1]))
        elif len(a) == 2 and a[0] == "empty":
            emit(empty(a[1]))
        else:
            emit({"ok": False, "message": "usage: catalog | search <text> [mine|all|unused] [name|size] | plan <json> | remove <json> | removed | undo <id> | empty <id> | empty-all"})
    except Exception as e:                       # always answer the page
        emit({"ok": False, "message": f"Unexpected error: {e}"})


if __name__ == "__main__":
    main()
