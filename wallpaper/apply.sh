#!/usr/bin/env bash
# Paint the selected wallpaper with swww.
#
# The choice is a path in a file this repo writes (configure.sh seeds it, see
# ~/.config/niri/wallpaper-active), so there is nothing to follow. This runs
# once, from swww-daemon.service's ExecStartPost, on every daemon start.
#
# To change wallpaper: point that file at another image in ~/Documents/Wallpapers
# and run this script, or `systemctl --user restart swww-daemon.service`.
set -uo pipefail

# swww is a `cargo install`, not an apt package, and niri's session env doesn't
# necessarily carry ~/.cargo/bin.
PATH="$HOME/.cargo/bin:$PATH"

ACTIVE="$HOME/.config/niri/wallpaper-active"

# A quick fade rather than swww's own 3s default, which is a long time to watch
# at login. "none" is the honest choice for the startup paint, but this script
# is also how you change wallpaper by hand, and a hard cut there looks like a
# glitch. The environment wins, for auditioning one without editing this file:
#
#   SWWW_TRANSITION=grow ~/.config/niri/wallpaper-apply.sh
#
# swww's transitions: none simple fade left right top bottom wipe wave grow
# center outer any random.
TRANSITION="${SWWW_TRANSITION:-fade}"
TRANSITION_DURATION="${SWWW_TRANSITION_DURATION:-0.5}"
TRANSITION_FPS="${SWWW_TRANSITION_FPS:-30}"

if [ ! -s "$ACTIVE" ]; then
    echo "No wallpaper selected: $ACTIVE is missing or empty" >&2
    exit 1
fi

WALLPAPER="$(head -n1 "$ACTIVE")"

if [ ! -f "$WALLPAPER" ]; then
    echo "Selected wallpaper does not exist: $WALLPAPER" >&2
    exit 1
fi

# These wallpapers are small pixel-art loops stretched to fill the screen, and
# Lanczos turns pixel art into mush. swww animates WebP as well as GIF, so both
# count as loops. PNG does not: the static PNGs here include photographs, which
# still get swww's default.
case "${WALLPAPER,,}" in
    *.gif|*.webp) FILTER=Nearest ;;
    *)            FILTER=Lanczos3 ;;
esac

# This runs as ExecStartPost, which fires while the daemon is still coming up,
# so the first attempt usually loses the race to the socket being created.
# Retrying is what replaces waiting on `swww query`, and also covers a daemon
# that takes its time or dies once on startup.
#
# --resize crop is swww's name for the "Fill" fill mode. No --outputs flag means
# every output: there is one wallpaper for the whole session.
PAINTED=no
for _ in $(seq 1 30); do
    if swww img "$WALLPAPER" \
        --resize crop \
        --filter "$FILTER" \
        --transition-type "$TRANSITION" \
        --transition-duration "$TRANSITION_DURATION" \
        --transition-fps "$TRANSITION_FPS" 2>/dev/null
    then
        PAINTED=yes
        break
    fi
    sleep 1
done

if [ "$PAINTED" != yes ]; then
    echo "Could not paint $WALLPAPER — is swww-daemon running?" >&2
    exit 1
fi

exit 0
