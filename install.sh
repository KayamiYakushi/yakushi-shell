#!/bin/sh
# Install (or update) Yakushi Shell for your user.
#
#   ./install.sh            copy this checkout to $XDG_DATA_HOME/yakushi-shell
#                           and link the `yakushi` command into ~/.local/bin
#   ./install.sh --uninstall
#
# Only files tracked by git are copied (no caches, no stray test files). The
# new copy is built next to the old one and swapped in with one rename, so a
# running shell never sees half an update; restart it afterwards with
# `yakushi restart`.
#
# Your settings (~/.config/yakushi) are never touched.

set -eu

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

case "${HOME:-}" in /*) ;; *) die "HOME is not set" ;; esac
case "${XDG_DATA_HOME:-}" in /*) data_home="$XDG_DATA_HOME" ;; *) data_home="$HOME/.local/share" ;; esac
# ~/.local/bin, the place systemd puts on PATH for user programs
bin_dir="$(systemd-path user-binaries 2>/dev/null)" || bin_dir="$HOME/.local/bin"
case "$bin_dir" in /*) ;; *) bin_dir="$HOME/.local/bin" ;; esac

dest="$data_home/yakushi-shell"
src="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"

if [ "${1:-}" = "--uninstall" ]; then
    # stop the shell this copy runs, so the next `yakushi start` (e.g. the
    # package's) never finds a second bar still up
    [ -x "$dest/bin/yakushi" ] && "$dest/bin/yakushi" stop 2>/dev/null
    for link in "$bin_dir/yakushi" "$bin_dir/yakushi-share-picker"; do
        # only our own links
        case "$(readlink -- "$link" 2>/dev/null)" in "$dest"/*) rm -f -- "$link" ;; esac
    done
    rm -rf -- "$dest"
    say "Removed $dest (your settings in ~/.config/yakushi are kept)."
    exit 0
fi

[ "$src" != "$dest" ] || die "run it from a checkout, not from the installed copy"
command -v git >/dev/null || die "git is needed (pacman -S git)"
git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$src is not a git checkout"

for dep in qs python3 jq wpctl hyprctl timeout setsid; do
    command -v "$dep" >/dev/null || say "warning: '$dep' is not installed; part of the shell will not work."
done

if pacman -Qq yakushi-shell >/dev/null 2>&1; then
    say "note: the yakushi-shell package is installed too; this copy in $bin_dir comes first on PATH."
fi

mkdir -p -- "$data_home" "$bin_dir"
new="$(mktemp -d -- "$data_home/.yakushi-shell.new.XXXXXX")"
trap 'rm -rf -- "$new"' EXIT INT TERM

# tracked files only, permissions kept
git -C "$src" ls-files -z | (cd -- "$src" && tar --null -T - -cf -) | tar -xf - -C "$new"
printf '%s\n' "$(git -C "$src" describe --always --dirty 2>/dev/null)" > "$new/VERSION"

# swap: old copy aside, new one in, old one gone
if [ -e "$dest" ]; then
    old="$data_home/.yakushi-shell.old.$$"
    mv -- "$dest" "$old"
    mv -- "$new" "$dest"
    rm -rf -- "$old"
else
    mv -- "$new" "$dest"
fi
trap - EXIT INT TERM

ln -sfn -- "$dest/bin/yakushi" "$bin_dir/yakushi"
ln -sfn -- "$dest/scripts/share-picker.sh" "$bin_dir/yakushi-share-picker"

say "Installed Yakushi Shell $(cat "$dest/VERSION") to $dest"
say "Command: $bin_dir/yakushi"
case ":$PATH:" in *":$bin_dir:"*) ;; *) say "note: $bin_dir is not on your PATH" ;; esac
if yakushi_running="$("$dest/bin/yakushi" status 2>/dev/null && echo yes)"; [ "$yakushi_running" = yes ]; then
    say "The shell is running: 'yakushi restart' loads the new version."
fi
