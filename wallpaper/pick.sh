#!/usr/bin/env bash
# Pick a wallpaper with fuzzel, with thumbnails.
#
# This is Mod+Alt+B put back. The old bind was "next wallpaper" and went through
# DMS's picker; when DMS went, the bind went with it rather than be left pointing
# at a missing binary. What replaces it lists rather than cycles — four
# wallpapers have no order worth stepping through, and two of the filenames are
# download hashes, so a list you can see is worth more than a key you press
# repeatedly.
#
# The selection is applied by handing off to wallpaper-apply.sh, not by calling
# swww here. That script already knows to use the Nearest filter on GIFs and to
# retry while the daemon is still coming up, and having two callers of swww with
# two ideas about the flags is how those two drift apart.
set -euo pipefail

WALLPAPERS="$HOME/Documents/Wallpapers"
ACTIVE="$HOME/.config/niri/wallpaper-active"
APPLY="$HOME/.config/niri/wallpaper-apply.sh"
PICKER_INI="$HOME/.config/fuzzel/wallpaper-picker.ini"
THUMBS="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-thumbs"

# fuzzel scales an icon to the row height, so this only has to be big enough not
# to be upscaled — see line-height in wallpaper-picker.ini.
THUMB_WIDTH=128

die() {
    echo "$*" >&2
    command -v notify-send &>/dev/null && notify-send "Wallpaper" "$*"
    exit 1
}

[ -d "$WALLPAPERS" ] || die "No wallpaper directory: $WALLPAPERS"
[ -x "$APPLY" ] || die "wallpaper-apply.sh missing or not executable — run configure.sh"

# ffmpeg rather than ImageMagick, which is not installed here and would be a new
# dependency for one call. ffmpeg also happens to be the right tool: -frames:v 1
# takes the first frame of an animated GIF, where a still-image converter needs
# telling which frame it is looking at.
#
# Missing ffmpeg is not fatal. The entries below fall back to bare filenames, and
# a picker with no previews is still better than a shortcut that does nothing —
# which is also what doctor.sh says about it.
HAVE_FFMPEG=yes
if ! command -v ffmpeg &>/dev/null; then
    HAVE_FFMPEG=no
    echo "ffmpeg not installed — listing wallpapers without thumbnails" >&2
fi

mkdir -p "$THUMBS"

# A glob straight into an array: bash sorts it, so the list does not reshuffle
# between invocations, and nullglob means an empty directory leaves an empty
# array rather than one entry that is the unmatched pattern itself.
shopt -s nullglob
WALLS=("$WALLPAPERS"/*)
shopt -u nullglob

[ "${#WALLS[@]}" -gt 0 ] || die "No wallpapers in $WALLPAPERS"

# The dmenu stream. Rofi's extended protocol, which fuzzel implements: the entry
# text, then a NUL, then "icon", then 0x1f, then the icon. fuzzel takes an
# absolute path there as well as an icon-theme name, which is the whole reason
# thumbnails are possible without installing anything into an icon theme.
#
# Emitted straight down a pipe into fuzzel rather than collected in a variable
# first, and that is not a style choice: bash cannot hold a NUL in a string, so
# building this with $(printf ...) silently drops the separator — "ignored null
# byte in input" — and every entry arrives as one long label with its own icon
# path printed in it.

# Keyed on the full filename, extension included: 205.png and a hypothetical
# 205.gif are different wallpapers and must not share a thumbnail.
thumb_for() { printf '%s/%s.png' "$THUMBS" "$1"; }

for wall in "${WALLS[@]}"; do
    [ "$HAVE_FFMPEG" = yes ] || break
    [ -f "$wall" ] || continue
    thumb="$(thumb_for "$(basename "$wall")")"

    # -nt is false when the thumb does not exist, which is the same answer we
    # want, so this covers both "never generated" and "source has changed".
    if [ ! -f "$thumb" ] || [ "$wall" -nt "$thumb" ]; then
        # A failure here is not fatal: a wallpaper with no thumbnail is still
        # worth listing, and fuzzel renders a blank icon rather than refusing.
        # Kept out of the emitting loop below so that nothing ffmpeg says can
        # end up in fuzzel's stdin.
        ffmpeg -y -loglevel error \
            -i "$wall" \
            -vf "scale=$THUMB_WIDTH:-1" \
            -frames:v 1 \
            "$thumb" </dev/null >/dev/null 2>&1 || true
    fi
done

emit_entries() {
    local wall name thumb
    for wall in "${WALLS[@]}"; do
        [ -f "$wall" ] || continue
        name="$(basename "$wall")"
        thumb="$(thumb_for "$name")"
        if [ -f "$thumb" ]; then
            printf '%s\0icon\x1f%s\n' "$name" "$thumb"
        else
            printf '%s\n' "$name"
        fi
    done
}

# --config is what makes this look like the project and task pickers rather than
# like the application launcher; see wallpaper-picker.ini. Passing it only when
# it exists means a machine that has not run configure.sh yet still gets a
# working picker, just an unstyled one.
#
# --lines is sized to the list so the popup is exactly as tall as it needs to
# be, capped at 8 — the same idea as niri-tasks' clamp_lines, a lower cap
# because these rows are thumbnail-height rather than text-height.
lines="${#WALLS[@]}"
[ "$lines" -gt 8 ] && lines=8

FUZZEL_ARGS=(--dmenu --lines "$lines")
[ -f "$PICKER_INI" ] && FUZZEL_ARGS+=(--config="$PICKER_INI")

# Cancelling fuzzel is a non-zero exit, which set -e would treat as a failure.
# It is not one: it is the answer "never mind".
selected="$(emit_entries | fuzzel "${FUZZEL_ARGS[@]}")" || selected=""
[ -n "$selected" ] || exit 0

# fuzzel echoes typed text verbatim when it matches no entry — that is what lets
# the project picker create new folders. There is nothing to create here, so an
# unmatched answer is a typo and the honest thing is to do nothing with it.
if [ ! -f "$WALLPAPERS/$selected" ]; then
    die "No such wallpaper: $selected"
fi

printf '%s\n' "$WALLPAPERS/$selected" > "$ACTIVE"

# exec, so the exit status you see is the paint's and not this script's.
exec "$APPLY"
