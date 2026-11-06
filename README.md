# Yakushi Shell

A Quickshell (QML) desktop shell for Hyprland — the island top bar, Settings,
OSD, wallpaper picker and screen-share picker from
[yakushidotfiles](https://github.com/KayamiYakushi/yakushidotfiles), growing
into a single installable shell.

**Status:** early. This first commit is the current live config imported as-is;
the restructuring into one shell follows step by step.

## Roadmap

1. Single entry point (`shell.qml`) with one IPC surface
2. One versioned config (`~/.config/yakushi/config.json`) behind a `Config` singleton
3. Code read-only, user state in `~/.config/yakushi` / `~/.local/state/yakushi`
4. Own notifications, launcher, power menu and lock screen (replacing swaync, rofi, wlogout, hyprlock)
5. Compositor abstraction (Niri later), PKGBUILD and a `yakushi` CLI
