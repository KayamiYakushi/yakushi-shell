# Yakushi Shell

A Quickshell (QML) desktop shell for Hyprland — the island top bar, Settings,
OSD, wallpaper picker and screen-share picker from
[yakushidotfiles](https://github.com/KayamiYakushi/yakushidotfiles), growing
into a single installable shell.

**Status:** early, Hyprland only.

## Running

```sh
scripts/yakushi-shell.sh start                 # start the shell
scripts/yakushi-shell.sh ipc settings toggle   # SUPER + I
scripts/yakushi-shell.sh ipc settings open tasks
scripts/volume-osd.sh up|down|mute             # volume keys
scripts/yakushi-bar.sh toggle                  # show / hide the top bar
```

`toggle-settings.sh`, `volume-osd.sh` and `yakushi-bar.sh` are thin
wrappers kept so existing keybinds keep working. The screen-share picker
(`share-picker-shell.qml`) and the wallpaper picker stay separate
processes for now.

## Principles

1. **Arch official repositories only.** Every dependency comes from `core`,
   `extra` or `multilib` — no AUR, no pip/npm/cargo, no bundled binaries.
2. **Security first.** Least privilege, secrets only through pipes, root
   actions only through polkit, no needless network access.
3. **As optimized as we can make it.** Load on demand, react to events
   instead of polling, keep idle CPU and memory low.
4. **One whole.** Every module shares the same theme, components and
   behavior, so the shell looks and feels like one thing.

## Roadmap

1. ✅ Single entry point (`shell.qml`) with one IPC surface — Settings runs
   as the shell's child process so it frees all its memory when closed
2. One versioned config (`~/.config/yakushi/config.json`) behind a `Config` singleton
3. Code read-only, user state in `~/.config/yakushi` / `~/.local/state/yakushi`
4. Own notifications, launcher, power menu and lock screen (replacing swaync, rofi, wlogout, hyprlock)
5. Compositor abstraction (Niri later), PKGBUILD and a `yakushi` CLI
