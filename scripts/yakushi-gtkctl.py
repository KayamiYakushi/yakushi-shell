#!/usr/bin/env python3
"""GTK apps in the shell's colours, for Settings -> Appearance -> Apps.

Commands:
    get                     Print the settings as JSON.
    set colours on|off      GTK 3 / GTK 4 (libadwaita) apps use the shell's
                            surfaces, ink and accent. Off: plain Adwaita dark.
    set opacity <0.30..1>   File manager background opacity (Files/Nautilus,
                            Nemo, Thunar). Only the background: text and icons
                            stay solid; Hyprland blurs what shows through.
    sync                    Write the files again (after the accent changed;
                            called by yakushi-themesync.py).
    reopen                  Restart Files (Nautilus) on the folders it shows:
                            GTK reads its style only when an app starts, so
                            open windows keep the old look until then. Never
                            done on its own, as it would cut a running copy.

What it writes, only while colours are on:
    ~/.config/gtk-4.0/yakushi.css, ~/.config/gtk-3.0/yakushi.css
    and one @import line, between yakushi markers, at the top of gtk.css
    in both folders. Whatever else you keep in gtk.css is left alone; off
    removes exactly what was added.
    ~/.local/share/icons/Yakushi-Folders: Adwaita's folder icons in the
    accent colour (Adwaita draws them blue, and CSS cannot reach into an
    icon), everything else inherited from Adwaita; made the GTK icon theme
    (gsettings) while colours are on. Off puts the earlier icon theme back. Open apps pick it up when reopened
(`reopen` does that for Files).

Settings live in the "apps" section of ~/.config/yakushi/config.json.
Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time

import colorsys
from pathlib import Path

import yakushi_config as config
import yakushi_paths as paths

DEFAULTS = {"colours": False, "filesOpacity": 1.0}
OPACITY_MIN, OPACITY_MAX = 0.30, 1.0

GTK_DIRS = (paths.CONFIG_HOME / "gtk-4.0", paths.CONFIG_HOME / "gtk-3.0")
BEGIN = "/* yakushi:begin (Settings -> Appearance -> Apps; do not edit between the markers) */"
END = "/* yakushi:end */"
IMPORT = '@import url("yakushi.css");'
BLOCK_RE = re.compile(r"/\* yakushi:begin.*?/\* yakushi:end \*/\n?", re.S)
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")

# the shell's own tokens (Theme.qml)
SURFACE = "#060606"
CARD = "#0e0e0e"
GROOVE = "#171717"
LINE = "#1f1f1f"
INK = "#ffffff"
ALERT = "#ff2e4d"
GOOD = "#2ee6a0"
WARN = "#ffc857"

# window classes of the GTK file managers the opacity applies to
FILE_MANAGERS_GTK4 = (".nautilus-window",)
FILE_MANAGERS_GTK3 = (".nemo-window", ".thunar")


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def sanitize(saved: dict) -> dict:
    state = dict(DEFAULTS)
    if isinstance(saved.get("colours"), bool):
        state["colours"] = saved["colours"]
    value = saved.get("filesOpacity")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        state["filesOpacity"] = round(max(OPACITY_MIN, min(OPACITY_MAX, float(value))), 2)
    return state


def accent() -> str:
    try:
        value = config.section("appearance").get("accent")
        if isinstance(value, str) and HEX.match(value):
            return value.lower()
    except (OSError, ValueError, AttributeError):
        pass
    return "#ffffff"


def readable_on(colour: str) -> str:
    """Black or white, whichever reads better on `colour` (WCAG luminance)."""
    def channel(c: int) -> float:
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(colour[i:i + 2], 16) for i in (1, 3, 5))
    lum = 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    return "#000000" if lum > 0.179 else "#ffffff"


def rgba(colour: str, alpha: float) -> str:
    r, g, b = (int(colour[i:i + 2], 16) for i in (1, 3, 5))
    return f"rgba({r}, {g}, {b}, {alpha:.2f})"


# ---------------------------------------------------------------------------
# The stylesheets
# ---------------------------------------------------------------------------

HEADER = """/* Yakushi colours, written by yakushi-gtkctl.py
   (Settings -> Appearance -> Apps). Rewritten on every change: edits here
   do not last. Put your own rules in gtk.css instead. */
"""


def gtk4_css(acc: str, opacity: float) -> str:
    fg = readable_on(acc)
    colours = {
        "accent_color": acc, "accent_bg_color": acc, "accent_fg_color": fg,
        "destructive_color": ALERT, "destructive_bg_color": ALERT, "destructive_fg_color": "#ffffff",
        "success_color": GOOD, "success_bg_color": GOOD, "success_fg_color": "#000000",
        "warning_color": WARN, "warning_bg_color": WARN, "warning_fg_color": "#000000",
        "error_color": ALERT, "error_bg_color": ALERT, "error_fg_color": "#ffffff",
        "window_bg_color": SURFACE, "window_fg_color": INK,
        "view_bg_color": SURFACE, "view_fg_color": INK,
        "headerbar_bg_color": SURFACE, "headerbar_fg_color": INK,
        "headerbar_border_color": LINE, "headerbar_backdrop_color": SURFACE,
        "headerbar_shade_color": "rgba(0, 0, 0, 0.36)",
        "sidebar_bg_color": CARD, "sidebar_fg_color": INK,
        "sidebar_backdrop_color": CARD, "sidebar_border_color": LINE,
        "sidebar_shade_color": "rgba(0, 0, 0, 0.36)",
        "secondary_sidebar_bg_color": CARD, "secondary_sidebar_fg_color": INK,
        "secondary_sidebar_backdrop_color": CARD, "secondary_sidebar_border_color": LINE,
        "secondary_sidebar_shade_color": "rgba(0, 0, 0, 0.36)",
        "card_bg_color": CARD, "card_fg_color": INK, "card_shade_color": "rgba(0, 0, 0, 0.36)",
        "dialog_bg_color": CARD, "dialog_fg_color": INK,
        "popover_bg_color": CARD, "popover_fg_color": INK, "popover_shade_color": "rgba(0, 0, 0, 0.36)",
        "thumbnail_bg_color": GROOVE, "thumbnail_fg_color": INK,
        "overview_bg_color": CARD, "overview_fg_color": INK,
        "shade_color": "rgba(0, 0, 0, 0.36)",
        "scrollbar_outline_color": "rgba(0, 0, 0, 0.5)",
    }
    out = [HEADER]
    # libadwaita 1.6 and newer draw with CSS variables and fill the accent in
    # from the system setting; the named colours are for older apps only
    out += [":root {"] + [f"  --{name.replace('_', '-')}: {value};" for name, value in colours.items()] + ["}", ""]
    out += [f"@define-color {name} {value};" for name, value in colours.items()]

    if opacity < 1.0:
        # Custom properties are inherited, so these reach every part of the
        # file manager window and nothing outside it. Only the window itself
        # is tinted; the layers on top of it are made clear, or their alphas
        # would add up. Popovers and dialogs keep their solid colours.
        sel = ", ".join(f"window{c}" for c in FILE_MANAGERS_GTK4)
        out += ["", f"{sel} {{",
                f"  --window-bg-color: {rgba(SURFACE, opacity)};",
                "  --view-bg-color: transparent;",
                "  --headerbar-bg-color: transparent;",
                "  --headerbar-backdrop-color: transparent;",
                f"  --sidebar-bg-color: {rgba('#ffffff', 0.03)};",
                f"  --sidebar-backdrop-color: {rgba('#ffffff', 0.03)};",
                "  background-color: var(--window-bg-color);",
                "}"]
    return "\n".join(out) + "\n"


def gtk3_css(acc: str, opacity: float) -> str:
    fg = readable_on(acc)
    colours = {
        "theme_bg_color": SURFACE, "theme_fg_color": INK,
        "theme_base_color": SURFACE, "theme_text_color": INK,
        "theme_selected_bg_color": acc, "theme_selected_fg_color": fg,
        "insensitive_bg_color": CARD, "insensitive_fg_color": "#707070",
        "insensitive_base_color": CARD,
        "theme_unfocused_bg_color": SURFACE, "theme_unfocused_fg_color": INK,
        "theme_unfocused_base_color": SURFACE, "theme_unfocused_text_color": INK,
        "theme_unfocused_selected_bg_color": acc, "theme_unfocused_selected_fg_color": fg,
        "borders": LINE, "unfocused_borders": LINE,
        "warning_color": WARN, "error_color": ALERT, "success_color": GOOD,
        # the libadwaita names too, for GTK 3 themes that follow them
        "accent_color": acc, "accent_bg_color": acc, "accent_fg_color": fg,
        "window_bg_color": SURFACE, "window_fg_color": INK,
        "view_bg_color": SURFACE, "view_fg_color": INK,
        "headerbar_bg_color": SURFACE, "headerbar_fg_color": INK,
        "sidebar_bg_color": CARD, "popover_bg_color": CARD,
        "card_bg_color": CARD, "dialog_bg_color": CARD,
    }
    out = [HEADER]
    out += [f"@define-color {name} {value};" for name, value in colours.items()]

    if opacity < 1.0:
        tint = rgba(SURFACE, opacity)
        win = ", ".join(f"window{c}" for c in FILE_MANAGERS_GTK3)
        inner = ", ".join(f"{c} {part}" for c in FILE_MANAGERS_GTK3
                          for part in (".view", "treeview", "iconview", "scrolledwindow", "viewport",
                                       ".sidebar", "placessidebar", "headerbar", "toolbar",
                                       "statusbar", "paned"))
        out += ["", f"{win} {{ background-color: {tint}; }}",
                f"{inner} {{ background-color: transparent; }}"]
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def write_atomic(path, text: str) -> None:
    """Temp file + fsync + rename; through a symlink to its real file."""
    real = os.path.realpath(path)
    tmp = f"{real}.yakushi-new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC, 0o644)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, real)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def set_import(folder, wanted: bool) -> None:
    gtk_css = folder / "gtk.css"
    try:
        text = gtk_css.read_text(encoding="utf-8")
    except FileNotFoundError:
        text = ""
    rest = BLOCK_RE.sub("", text)
    updated = (f"{BEGIN}\n{IMPORT}\n{END}\n" + rest) if wanted else rest
    if updated == text:
        return
    if not updated.strip() and not wanted:
        try:
            gtk_css.unlink()                    # it held only our line
        except FileNotFoundError:
            pass
        return
    folder.mkdir(parents=True, exist_ok=True)
    write_atomic(gtk_css, updated)


# ---------------------------------------------------------------------------
# Folder icons in the accent colour
# ---------------------------------------------------------------------------

ICON_THEME = "Yakushi-Folders"
ICON_DIR = paths.DATA_HOME / "icons" / ICON_THEME
ICON_SOURCE = Path("/usr/share/icons/Adwaita/scalable")
PREVIOUS_ICONS = paths.STATE / "gtk-icon-theme.previous"
# the icons Adwaita draws as blue folders
FOLDER_ICONS = (("places", "folder*.svg"), ("places", "user-home.svg"), ("places", "user-desktop.svg"),
                ("mimetypes", "inode-directory.svg"))
SVG_HEX = re.compile(r"#([0-9a-fA-F]{6})\b")


def tint(svg: str, acc: str) -> str:
    """Every blue of the icon turned to the accent's hue; light and shade stay as drawn,
    so the folder keeps its depth. A grey accent gives grey folders."""
    ar, ag, ab = (int(acc[i:i + 2], 16) / 255 for i in (1, 3, 5))
    ah, _al, asat = colorsys.rgb_to_hls(ar, ag, ab)

    def swap(m: re.Match) -> str:
        r, g, b = (int(m.group(1)[i:i + 2], 16) / 255 for i in (0, 2, 4))
        h, l, sat = colorsys.rgb_to_hls(r, g, b)
        if not (0.50 <= h <= 0.70 and sat >= 0.25):      # not one of the blues
            return m.group(0)
        nr, ng, nb = colorsys.hls_to_rgb(ah, l, sat * min(1.0, asat / 0.6))
        return "#%02x%02x%02x" % (round(nr * 255), round(ng * 255), round(nb * 255))
    return SVG_HEX.sub(swap, svg)


def gsettings(*args: str) -> str:
    try:
        out = subprocess.run(["gsettings", *args], capture_output=True, text=True, timeout=5)
        return out.stdout.strip().strip("'") if out.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def write_icons(acc: str) -> None:
    tmp = ICON_DIR.with_name(ICON_THEME + ".yakushi-new")
    shutil.rmtree(tmp, ignore_errors=True)
    dirs = []
    for context, pattern in FOLDER_ICONS:
        (tmp / context).mkdir(parents=True, exist_ok=True)
        if context not in dirs:
            dirs.append(context)
        for icon in sorted((ICON_SOURCE / context).glob(pattern)):
            (tmp / context / icon.name).write_text(tint(icon.read_text(encoding="utf-8"), acc), encoding="utf-8")
    index = ["[Icon Theme]", f"Name={ICON_THEME}",
             "Comment=Adwaita, with folders in the Yakushi accent (Settings -> Appearance -> Apps)",
             "Inherits=Adwaita,AdwaitaLegacy,hicolor", "Hidden=true",
             "Directories=" + ",".join(dirs), ""]
    for context in dirs:
        index += [f"[{context}]", f"Context={context.capitalize()}", "Size=128",
                  "MinSize=8", "MaxSize=512", "Type=Scalable", ""]
    (tmp / "index.theme").write_text("\n".join(index), encoding="utf-8")
    (tmp / "accent").write_text(acc + "\n", encoding="utf-8")
    shutil.rmtree(ICON_DIR, ignore_errors=True)
    tmp.rename(ICON_DIR)


def set_icons(acc: str, wanted: bool) -> None:
    current = gsettings("get", "org.gnome.desktop.interface", "icon-theme")
    if wanted:
        if not ICON_SOURCE.is_dir():
            return                              # no Adwaita: nothing to tint
        try:
            same = (ICON_DIR / "accent").read_text(encoding="utf-8").strip() == acc
        except OSError:
            same = False
        if same and current == ICON_THEME:
            return                              # e.g. only the opacity moved
        write_icons(acc)
        if current and current != ICON_THEME:
            PREVIOUS_ICONS.parent.mkdir(parents=True, exist_ok=True)
            write_atomic(PREVIOUS_ICONS, current + "\n")
            gsettings("set", "org.gnome.desktop.interface", "icon-theme", ICON_THEME)
        elif current == ICON_THEME:
            # the same name again: GTK only reloads a theme when the name changes
            gsettings("set", "org.gnome.desktop.interface", "icon-theme", "Adwaita")
            gsettings("set", "org.gnome.desktop.interface", "icon-theme", ICON_THEME)
    else:
        if current == ICON_THEME:
            try:
                previous = PREVIOUS_ICONS.read_text(encoding="utf-8").strip() or "Adwaita"
            except OSError:
                previous = "Adwaita"
            gsettings("set", "org.gnome.desktop.interface", "icon-theme", previous)
        shutil.rmtree(ICON_DIR, ignore_errors=True)
        try:
            PREVIOUS_ICONS.unlink()
        except FileNotFoundError:
            pass


def apply(state: dict) -> None:
    acc = accent()
    for folder, build in zip(GTK_DIRS, (gtk4_css, gtk3_css)):
        own = folder / "yakushi.css"
        if state["colours"]:
            folder.mkdir(parents=True, exist_ok=True)
            write_atomic(own, build(acc, state["filesOpacity"]))
            set_import(folder, True)
        else:
            set_import(folder, False)
            try:
                own.unlink()
            except FileNotFoundError:
                pass
    set_icons(acc, state["colours"])


def files_running() -> bool:
    try:
        return subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "nautilus"],
                              capture_output=True, timeout=3).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def files_locations() -> list[str]:
    """The folder each open Files window shows (its first tab)."""
    try:
        out = subprocess.run(
            ["busctl", "--user", "--json=short", "get-property", "org.freedesktop.FileManager1",
             "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", "OpenWindowsWithLocations"],
            capture_output=True, text=True, timeout=3)
        windows = json.loads(out.stdout).get("data", {})
    except (OSError, ValueError, AttributeError, subprocess.TimeoutExpired):
        return []
    places = []
    for _window, uris in sorted(windows.items()):
        if isinstance(uris, list) and uris and isinstance(uris[0], str) and uris[0] not in places:
            places.append(uris[0])
    return places


def reopen_files() -> str:
    if not shutil.which("nautilus"):
        return "Files (Nautilus) is not installed."
    if not files_running():
        return "Files is not open; it will use the new look when you open it."
    places = files_locations()
    subprocess.run(["nautilus", "-q"], capture_output=True, timeout=10)
    for _ in range(50):                     # up to 5 s to close
        if not files_running():
            break
        time.sleep(0.1)
    else:
        return "Files did not close (busy?). Close it yourself and open it again."
    for place in places or [None]:
        command = ["nautilus", "--new-window"] + ([place] if place else [])
        subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    return "Files reopened with the new look."


def save(change) -> dict:
    def edit(saved: dict) -> dict:
        state = sanitize(saved)
        change(state)
        return state

    try:
        return config.update("apps", edit)
    except config.NewerConfig as error:
        fail(str(error))
        return {}


def main() -> None:
    args = sys.argv[1:]

    try:
        if args == ["get"]:
            emit({"ok": True, **sanitize(config.section("apps")), "filesOpen": files_running()})

        elif len(args) == 3 and args[:2] == ["set", "colours"]:
            if args[2] not in ("on", "off"):
                fail("Use on or off.")
            value = args[2] == "on"
            state = save(lambda s: s.update(colours=value))
            apply(state)
            emit({"ok": True, **state, "filesOpen": files_running(),
                  "message": "GTK apps use the shell's colours; apps that are open change when reopened."
                  if value else "GTK apps are back to plain Adwaita dark (open apps: when reopened)."})

        elif len(args) == 3 and args[:2] == ["set", "opacity"]:
            try:
                value = round(max(OPACITY_MIN, min(OPACITY_MAX, float(args[2]))), 2)
            except ValueError:
                fail("Opacity must be a number between 0.30 and 1.")
                return
            state = save(lambda s: s.update(filesOpacity=value))
            apply(state)
            emit({"ok": True, **state, "filesOpen": files_running(),
                  "message": f"File manager opacity {round(value * 100)}%."})

        elif args == ["sync"]:
            state = sanitize(config.section("apps"))
            if state["colours"]:
                apply(state)
            emit({"ok": True, **state})

        elif args == ["reopen"]:
            emit({"ok": True, "message": reopen_files(), "filesOpen": files_running()})

        else:
            fail("Usage: get | set colours on|off | set opacity <0.30..1> | sync | reopen")
    except OSError as error:
        fail(f"Could not write the GTK files: {error.strerror or error}")


if __name__ == "__main__":
    main()
