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

# The three numbers that decide what the picker looks like. They are coupled, so
# they live together; changing one alone will not do what you want.
#
# Measured behaviour, none of it documented by fuzzel: a row is two line-heights
# tall, an icon is scaled to fit that height keeping its aspect, and anything
# wider than the window is cropped rather than shrunk. So if a thumbnail's aspect
# is exactly THUMB_W:THUMB_H and THUMB_H is two line-heights, the image fills its
# row edge to edge — which is the whole trick here.
#
#   THUMB_H = 2 * line-height   (90 in wallpaper-picker.ini)
#   FUZZEL_WIDTH is in characters, not pixels, and 22 comes out at ~456px with
#   this theme's font. It was found by looking, and is the one number here you
#   cannot calculate.
#
# Wallpapers are centre-cropped to this aspect rather than letterboxed. That
# throws away the top and bottom of a 16:9 image, which is the deal: a preview
# that fills its row tells you more at a glance than a smaller one that doesn't.
THUMB_W=456
THUMB_H=180
FUZZEL_WIDTH=22

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

# Thumbnails carry their size in the name, so a previous geometry leaves a full
# set behind that will never be read again. Drop them rather than let the cache
# grow by one set every time the size is changed.
shopt -s nullglob
for stale in "$THUMBS"/*.png; do
    case "$stale" in
        *".${THUMB_W}x${THUMB_H}.png") ;;
        *) rm -f "$stale" ;;
    esac
done
shopt -u nullglob

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
#
# The entry text is a single space. There are no filenames in this picker: two of
# them are download hashes, and a label beside the image forced the image to be
# small enough to leave room for it. A blank label means fuzzel returns nothing
# useful on selection, which is what --index is for below — it answers with the
# row number instead, and PICKABLE maps that back to a path.
#
# What this costs: type-to-filter. Every label is the same single space, so
# typing matches nothing and empties the list. The picker is arrow keys and
# Enter. That is a fair trade at four wallpapers and a bad one at forty.

# Keyed on the full filename, extension included: 205.png and a hypothetical
# 205.gif are different wallpapers and must not share a thumbnail. The geometry
# is in the name too, so that changing it regenerates rather than leaving every
# existing thumbnail at the old size — the staleness check below compares mtimes,
# and editing this script does not make the wallpapers any newer.
thumb_for() { printf '%s/%s.%sx%s.png' "$THUMBS" "$1" "$THUMB_W" "$THUMB_H"; }

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
        # crop before scale, and crop to whichever of the two the source can
        # actually supply, so a portrait wallpaper is cut down rather than
        # stretched. ffmpeg centres a crop when no x/y is given.
        ffmpeg -y -loglevel error \
            -i "$wall" \
            -vf "crop='min(iw,ih*$THUMB_W/$THUMB_H)':'min(ih,iw*$THUMB_H/$THUMB_W)',scale=$THUMB_W:$THUMB_H" \
            -frames:v 1 \
            "$thumb" </dev/null >/dev/null 2>&1 || true
    fi
done

# What fuzzel is actually shown, in the order it is shown. --index answers with
# a position in this list, so it has to be built once and not re-derived: any
# entry skipped here that was not skipped there would shift every index after it
# and silently select the wrong wallpaper.
PICKABLE=()
for wall in "${WALLS[@]}"; do
    [ -f "$wall" ] || continue
    PICKABLE+=("$wall")
done

[ "${#PICKABLE[@]}" -gt 0 ] || die "No wallpapers in $WALLPAPERS"

emit_entries() {
    local wall thumb
    for wall in "${PICKABLE[@]}"; do
        thumb="$(thumb_for "$(basename "$wall")")"
        if [ -f "$thumb" ]; then
            printf ' \0icon\x1f%s\n' "$thumb"
        else
            # No thumbnail means no icon, and a blank label would leave a row
            # with nothing in it at all. Name it, so it is still selectable.
            printf '%s\n' "$(basename "$wall")"
        fi
    done
}

# --config is what makes this look like the project and task pickers rather than
# like the application launcher; see wallpaper-picker.ini. Passing it only when
# it exists means a machine that has not run configure.sh yet still gets a
# working picker, just an unstyled one.
#
# --lines is sized to the list so the popup is exactly as tall as it needs to be,
# capped so it cannot run off the screen: each row is a THUMB_H-tall image, so
# four of them plus the input row is already most of a 1080p screen. Past the cap
# fuzzel scrolls.
lines="${#PICKABLE[@]}"
[ "$lines" -gt 4 ] && lines=4

# --index because the labels are blank; see emit_entries. --width here rather
# than in the ini so that it sits next to the geometry it has to agree with.
FUZZEL_ARGS=(--dmenu --index --lines "$lines" --width "$FUZZEL_WIDTH")
[ -f "$PICKER_INI" ] && FUZZEL_ARGS+=(--config="$PICKER_INI")

# Cancelling fuzzel is a non-zero exit, which set -e would treat as a failure.
# It is not one: it is the answer "never mind".
index="$(emit_entries | fuzzel "${FUZZEL_ARGS[@]}")" || index=""
[ -n "$index" ] || exit 0

# --index is documented to count from zero, but this is the one thing standing
# between a keypress and overwriting the wallpaper selection, so check rather
# than trust: anything that is not a number, or is off the end of the list, is a
# bug here and not something to act on.
case "$index" in
    ''|*[!0-9]*) die "fuzzel returned something that is not an index: $index" ;;
esac
[ "$index" -lt "${#PICKABLE[@]}" ] || die "fuzzel returned index $index, out of ${#PICKABLE[@]}"

chosen="${PICKABLE[$index]}"
[ -f "$chosen" ] || die "No such wallpaper: $chosen"

printf '%s\n' "$chosen" > "$ACTIVE"

# exec, so the exit status you see is the paint's and not this script's.
exec "$APPLY"
