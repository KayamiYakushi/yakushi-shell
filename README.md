# Yakushi Shell

A Quickshell (QML) desktop shell for Hyprland — the island top bar, Settings,
OSD, wallpaper picker and screen-share picker from
[yakushidotfiles](https://github.com/KayamiYakushi/yakushidotfiles), growing
into a single installable shell.

**Status:** early, Hyprland only.

## Install

```sh
./install.sh              # copies this checkout to ~/.local/share/yakushi-shell
                          # and links `yakushi` into ~/.local/bin
yakushi restart           # load a new version into a running shell
./install.sh --uninstall  # your settings in ~/.config/yakushi are kept
```

Only files tracked by git are installed, and the new copy is swapped in with
one rename. Edits in the checkout never reach the running desktop until you
install them.

## Hyprland

```lua
-- startup
"yakushi login",

-- keybinds
"yakushi settings"            -- SUPER + I
"yakushi settings tasks"      -- SUPER + Escape
"yakushi volume up|down|mute" -- volume keys
"yakushi bar toggle"
"yakushi wallpaper"           -- SUPER + W
"yakushi power"               -- SUPER + `  (the island's power menu)
"yakushi unfreeze"            -- SUPER + CTRL + Escape
```

Windows get the same cut corners from Hyprland itself:

```lua
decoration = { rounding = 14, rounding_power = 1.0 }  -- power 1 = straight 45-degree cut
```

`hypr/xdph.conf`: `custom_picker_binary = yakushi-share-picker`.
`hyprlock.conf` can show `~/.config/yakushi/profile-picture`.

`yakushi` with no arguments lists every command. Nothing in the shell is a
fixed path: user folders come from the XDG variables (and `user-dirs.dirs`,
so they are right in any language), the shell finds its own files from
where it runs, and runtime files go to `$XDG_RUNTIME_DIR` (there is no
`/tmp` fallback, on purpose).

## Design

One shape rule for every part of the shell:

- Outlines (anything that stands on the screen by itself: the island, its
  cards, pop-ups, the Settings card) get **45-degree cut corners**,
  `Theme.cut` = 14 px (`Theme.cutLarge` = 18 px for the Settings card).
- Inside a surface everything is square, or **slanted along the same
  diagonal** (top-right and bottom-left cut): level bars, progress bars,
  workspace marks (`SlantBar`, `CutBox`).
- No rounded corners anywhere.
- Settings opens from its two corner notches: they cross in the middle,
  slide apart along the diagonal and land on the card's cut corners.
- A tile inside a cut outline is inset evenly with cuts parallel to the
  outline's (a 45-degree cut moved in by d shrinks by d * (2 - sqrt 2)).
- Windows: Hyprland `rounding_power = 1.0` turns its rounding into the
  same straight cut.

## Configuration

Every setting lives in one file, `~/.config/yakushi/config.json`
(`$XDG_CONFIG_HOME` is honoured), next to `profile-picture`:

```json
{
  "version": 1,
  "topbar":     { "seconds": true, "clock24": true, "opacity": 0.9, ... },
  "appearance": { "panelOpacity": 0.9, "accent": "#ff7a9d" },
  "terminal":   { "enabled": true, "opacity": 0.7, ... },
  "wallpaper":  { "folder": "~/Pictures/Walls", "visibleCount": 10, ... }
}
```

- Settings writes it through the helpers in `scripts/` (`yakushi_config.py`):
  atomically, under a lock, private to you (0600). The shell watches it, so
  a change applies at once with no polling and no restart.
- On first start the old `~/.config/quickshell/*.local.json` settings and
  profile picture are carried over (the old files are left alone).
- A broken file is kept as `config.json.broken-<time>` and the defaults are
  used; a file from a newer Yakushi is never overwritten.
- `yakushi config init | path | get [section]`.
- `wallpaper.folder` defaults to your XDG Documents folder.

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
2. ✅ One versioned config (`~/.config/yakushi/config.json`) behind a `Config` singleton
3. ✅ Code read-only, user state in `~/.config/yakushi` / `~/.local/state/yakushi`
4. Own notifications, launcher, power menu and lock screen (replacing swaync, rofi, wlogout, hyprlock)
5. Compositor abstraction (Niri later), PKGBUILD (the `yakushi` CLI and user install are done)
