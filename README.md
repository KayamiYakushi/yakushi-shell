# Yakushi Shell

A Quickshell (QML) desktop shell for Hyprland: the island top bar, Settings,
launcher with clipboard history, notifications, volume pill, lock screen,
wallpaper picker and screen-share picker, in one installable package. It
grew out of [yakushidotfiles](https://github.com/KayamiYakushi/yakushidotfiles).

**Status:** early, but used every day. Hyprland only, on purpose.

## Install

You need Arch Linux (or an Arch-based system) and Hyprland 0.56 or newer
with its Lua config (`~/.config/hypr/hyprland.lua`). Every package comes
from the official repositories.

```sh
sudo pacman -S --needed git base-devel
git clone https://github.com/KayamiYakushi/yakushi-shell.git
cd yakushi-shell/packaging
makepkg -si                 # builds the package; pacman brings what it needs
```

The extras most people want (wallpapers, clipboard history, media keys,
screenshots, password prompts, screen sharing):

```sh
sudo pacman -S --needed awww cliphist wl-clipboard playerctl grim slurp \
    hyprpolkitagent xdg-desktop-portal-hyprland imagemagick qt6-imageformats \
    networkmanager pavucontrol brightnessctl hyprsunset cava
```

Then give Hyprland the config the shell expects, and log out and back in:

```sh
yakushi setup-hyprland      # asks first; shows what it will do
```

It moves your current `~/.config/hypr` aside as a whole (to
`~/.config/hypr.before-yakushi-<date>`; nothing is changed or deleted) and
puts the starter from [`hypr/`](hypr/) in its place, with the terminal,
file manager, browser and keyboard layout this computer already has.
`yakushi setup-hyprland --dry-run` only shows what it would do.

**Keeping your own Hyprland config?** Add the lines from
[Hyprland](#hyprland) below instead. The bar, launcher, lock, notifications
and most of Settings work; the Settings pages that edit Hyprland itself
(Keybinds, Monitors, Input, window look) need the starter's layout.

**Update:** `git pull`, then `cd packaging && makepkg -si`, then `yakushi restart`.

**Remove:** `sudo pacman -Rns yakushi-shell`. Your settings stay in
`~/.config/yakushi`; to get your old Hyprland config back, delete
`~/.config/hypr` and rename the `hypr.before-yakushi-*` folder.

### First steps

| Keys | |
|---|---|
| SUPER + Space | Apps (Tab: clipboard history) |
| SUPER + SHIFT + V | Clipboard history (can be turned off in Settings -> Default Apps) |
| SUPER + I | Settings |
| SUPER + Q / E / B | Terminal / files / browser |
| SUPER + W | Wallpapers (put your pictures in `~/Pictures/Wallpapers`) |
| SUPER + SHIFT + S | Screenshot of an area (CTRL instead of SHIFT: the window; SUPER + Delete: the screen). Clipboard only, unless Settings -> Default Apps saves them too |
| SUPER + Tab | Lock |
| SUPER + ` | Power menu |
| SUPER + Escape | What is running, and why |
| SUPER + CTRL + Escape | Restart a frozen bar or Settings |

Settings opens with the cursor in its search field: type what you are
looking for, in English or Turkish, typos and all ("curosr", "mouse imlecini
değiştir"), and Enter takes you to the setting and lights it up. Settings ->
Programs -> CLEAN UP finds leftovers of removed programs, old backups,
broken links, caches and old packages; your files go to an undo-able trash.

Every shortcut can be changed in Settings -> Keybinds. Put a square
picture in Settings -> System to see yourself on the lock screen.

The login screen is the lock screen's twin: the package installs it as the
SDDM theme `yakushi` (`sddm/` here). Turn it on once with
`printf '[Theme]\nCurrent=yakushi\n' | sudo tee /etc/sddm.conf.d/yakushi-theme.conf`,
then press MATCH THE SHELL in Settings -> Login Screen: it copies your
accent, 12/24 h clock and profile picture into the theme (the login screen
runs as the `sddm` user and cannot read your home). The background is chosen
on the same page. Try the theme without logging out:
`sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/yakushi`.

### For development

A user install without root, from your checkout:

```sh
./install.sh              # copies this checkout to ~/.local/share/yakushi-shell
                          # and links `yakushi` into ~/.local/bin
yakushi restart           # load a new version into a running shell
./install.sh --uninstall  # your settings in ~/.config/yakushi are kept
```

Only files tracked by git are installed, and the new copy is swapped in
with one rename. Use one of the two installs, not both: coming from this
one to the package, run `~/.local/share/yakushi-shell/install.sh
--uninstall` once, then `yakushi start`.

## Hyprland

What the shell needs from Hyprland (the starter in [`hypr/`](hypr/) has
all of it):

```lua
-- startup
"yakushi login",

-- keybinds
"yakushi settings"            -- SUPER + I
"yakushi settings tasks"      -- SUPER + Escape
"yakushi volume up|down|mute" -- volume keys
"yakushi bar toggle"
"yakushi wallpaper"           -- SUPER + W
"yakushi launcher"            -- SUPER + Space
"yakushi launcher clipboard"  -- SUPER + SHIFT + V
"yakushi power"               -- SUPER + `  (the island's power menu)
"yakushi lock"                -- SUPER + Tab
"yakushi notifications off"   -- or on | toggle | test
"yakushi unfreeze"            -- SUPER + CTRL + Escape
```

The launcher animates itself (Settings -> Appearance -> Launcher), so
Hyprland's fade is turned off for its layer, with a blur behind the card:

```lua
hl.layer_rule({ match = { namespace = "yakushi-launcher" }, blur = true, ignore_alpha = 0.15, no_anim = true })
```

The wallpaper picker (SUPER + W) is the same kind of card:

```lua
hl.layer_rule({ match = { namespace = "yakushi-wallpaper" }, blur = true, ignore_alpha = 0.15, no_anim = true })
```

Windows get the same cut corners from Hyprland itself:

```lua
decoration = { rounding = 14, rounding_power = 1.0 }  -- power 1 = straight 45-degree cut
```

Let a restarted lock take over (see [Lock screen](#lock-screen)):

```lua
misc = { allow_session_lock_restore = true }
```

`~/.config/hypr/xdph.conf`: `screencopy { custom_picker_binary = yakushi-share-picker }`.

## Lock screen

`yakushi lock` (SUPER + Tab, Power -> Lock, auto lock) runs `lock.qml` as its
own process, so a crash or restart of the bar never touches it. It uses the
ext-session-lock protocol: the compositor itself keeps the session locked,
and only a password PAM accepts (the `login` stack, so faillock and any
other module apply) ends the lock.

- If the lock process dies, the screen stays locked and `yakushi lock`
  starts it again (with `misc.allow_session_lock_restore`, see above).

- `yakushi lock preview` shows the same screen in a window and locks
  nothing: try the look and your password safely (Esc closes it).
- `yakushi suspend` locks, waits until every screen is covered, then sleeps
  (Power -> Suspend uses it).
- Lock before sleep: the lid, a `systemctl suspend` typed anywhere or
  hibernate also wake up locked. While the shell runs, a small guard holds
  a logind delay inhibitor (`systemd-inhibit --list` shows "Yakushi"),
  locks when logind announces the sleep, and lets go once every screen is
  covered. It waits on D-Bus (gdbus), nothing polls.
- Auto lock: Settings -> Security (config `lock.idleMinutes`, 0 = off, 10
  when never set). The shell asks the compositor for idle time, so nothing
  polls, and a playing video keeps the screen open. hypridle is not needed.
- It shows the wallpaper each screen has (dimmed), the clock, your
  `~/.config/yakushi/profile-picture` and name, and the song that is
  playing. The typed text is shown only as marks and cleared as soon as it
  has gone to PAM. A quiet CAPS tag shows in the field while Caps Lock is
  on (the LEDs in /sys when the lock opens, then the keys themselves).

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
  "wallpaper":  { "folder": "~/Pictures/Wallpapers", "visibleCount": 10, ... },
  "lock":       { "idleMinutes": 10 },
  "screenshots": { "save": false },
  "apps":       { "colours": true, "filesOpacity": 0.85 }
}
```

- Settings writes it through the helpers in `scripts/` (`yakushi_config.py`):
  atomically, under a lock, private to you (0600). The shell watches it, so
  a change applies at once with no polling and no restart.
- Coming from the older Quickshell setup in yakushidotfiles? On first start
  its `~/.config/quickshell/*.local.json` settings and profile picture are
  carried over (the old files are left alone).
- A broken file is kept as `config.json.broken-<time>` and the defaults are
  used; a file from a newer Yakushi is never overwritten.
- `yakushi config init | path | get [section]`.
- `wallpaper.folder` defaults to `Pictures/Wallpapers` when it has pictures,
  else your XDG Documents folder.

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
4. ✅ Power menu (the island's card) and ✅ notifications (built-in server, can be turned off completely);
   ✅ launcher with clipboard history (replacing rofi); ✅ lock screen and auto lock
   (replacing hyprlock and hypridle)
5. ✅ PKGBUILD (`packaging/`), next to the user install
6. ✅ Ready for others: a starter Hyprland config and `yakushi setup-hyprland`
