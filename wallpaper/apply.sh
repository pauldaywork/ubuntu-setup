#!/usr/bin/env bash
# Paint the selected wallpaper with swww.
#
# Replaces wallpaper-sync.sh, which was a watch loop: DMS owned the wallpaper
# choice and only ever announced a change by rewriting session.json, so the only
# way to follow it was to sit on that file with inotify and re-derive the
# selection each time it moved. All of that — the watch, the JSON resolution,
# the per-mode and per-monitor handling, the pid comparison that noticed a
# restarted daemon showing its own stale cache — existed to track someone else's
# state.
#
# The choice is now a path in a file this repo writes (configure.sh seeds it,
# see ~/.config/niri/wallpaper-active), so there is nothing to follow. This runs
# once, from swww-daemon.service's ExecStartPost, on every daemon start.
#
# To change wallpaper: point that file at another image in ~/Documents/Wallpapers
# and run this script, or `systemctl --user restart swww-daemon.service`.
#
# It also picks the wallpaper's accent colour for the bar, below. Every change
# of wallpaper comes through here, so this is the one place that can.
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
# Lanczos turns pixel art into mush. Photographs still get swww's default.
case "${WALLPAPER,,}" in
    *.gif) FILTER=Nearest ;;
    *)     FILTER=Lanczos3 ;;
esac

# This runs as ExecStartPost, which fires while the daemon is still coming up,
# so the first attempt usually loses the race to the socket being created.
# Retrying is what replaces waiting on `swww query`, and also covers a daemon
# that takes its time or dies once on startup.
#
# --resize crop is swww's name for the "Fill" fill mode. No --outputs flag means
# every output: there is one wallpaper for the whole session now, where DMS
# could set one per monitor and per light/dark mode.
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

# ─── Accent colour for the bar ────────────────────────────────────────────────
# The focused workspace button is filled with the wallpaper's brightest, most
# colourful colour, under black text. This is the retint matugen used to do for
# the whole desktop, cut down to the one thing that uses it.
#
# ffmpeg's palettegen boils the first frame down to 24 colours; the one scoring
# highest on saturation² × brightness wins, so a vivid patch beats a large dull
# one and a grey never wins while there is any colour at all. It is then pushed
# to full brightness, and if that is still too dark for black text (a deep blue,
# say) mixed toward white until black on it has at least 9:1 contrast. A
# wallpaper with no colour in it comes out white.
#
# Failure here is not fatal and leaves the previous colour in place: the
# wallpaper is already painted, and an out-of-date bar colour is not worth an
# error at login.
ACCENT_CSS="$HOME/.config/waybar/wallpaper-colors.css"

accent_for() {
    ffmpeg -loglevel error -i "$1" -frames:v 1 \
        -vf "scale=160:-1:flags=area,palettegen=max_colors=24:reserve_transparent=0:stats_mode=full" \
        -f image2pipe -vcodec png - </dev/null \
    | ffmpeg -loglevel error -f png_pipe -i - -f rawvideo -pix_fmt rgb24 - \
    | od -An -v -tu1 -w3 \
    | awk '
        function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
        function lum(r, g, b) { return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
        NF == 3 {
            mx = $1; if ($2 > mx) mx = $2; if ($3 > mx) mx = $3
            mn = $1; if ($2 < mn) mn = $2; if ($3 < mn) mn = $3
            if (mx == 0) next
            s = (mx - mn) / mx
            score = s * s * mx / 255
            if (!seen || score > best) { best = score; r = $1; g = $2; b = $3; seen = 1 }
        }
        END {
            if (!seen) exit 1
            mx = r; if (g > mx) mx = g; if (b > mx) mx = b
            k = 255 / mx; r *= k; g *= k; b *= k
            while (lum(r, g, b) < 0.4) { r += (255 - r) * 0.08; g += (255 - g) * 0.08; b += (255 - b) * 0.08 }
            printf "#%02x%02x%02x\n", int(r + 0.5), int(g + 0.5), int(b + 0.5)
        }'
}

if command -v ffmpeg >/dev/null && ACCENT="$(accent_for "$WALLPAPER")" && [ -n "$ACCENT" ]; then
    # Written aside and renamed into place: waybar exits over an import it
    # cannot read, so it must never catch this file missing or half-written.
    mkdir -p "$(dirname "$ACCENT_CSS")"
    printf '/* Written by wallpaper-apply.sh from %s. */\n@define-color wallpaper_accent %s;\n' \
        "$(basename "$WALLPAPER")" "$ACCENT" > "$ACCENT_CSS.tmp" \
        && mv -f "$ACCENT_CSS.tmp" "$ACCENT_CSS"
    # A restart, not SIGUSR2: a SIGUSR2 reload has aborted waybar before, and
    # the unit is how waybar is run (see configure.sh). try-restart leaves a
    # stopped bar stopped; its next start reads the file anyway.
    systemctl --user try-restart waybar.service 2>/dev/null || true
else
    echo "Could not pick an accent colour from $WALLPAPER — keeping the last one" >&2
fi

exit 0
