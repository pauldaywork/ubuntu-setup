#!/usr/bin/env bash
# Feeds DMS's chosen wallpaper to swww, so animated wallpapers actually animate.
#
# DMS paints wallpapers with a plain QML Image (Modules/WallpaperBackground.qml
# in /usr/share/quickshell/dms), which decodes only the first frame of a GIF.
# Upstream declined to animate it in-shell — DankMaterialShell#793 was closed
# with "we do not intend to add swww as a dependency within the shell itself" —
# and points at the escape hatch instead: Settings → Wallpaper → Disable
# Built-in Wallpapers, which is the empty screenPreferences.wallpaper array in
# our settings.json. That stops DMS creating the wallpaper layer surface at all,
# leaving the background to swww.
#
# Everything else about DMS stays: the picker, wallpaper cycling, and matugen
# theming all key off session.json, and matugen reads a GIF's first frame
# happily. session.json is also the picker's only outward signal, so that file
# is what we watch, forwarding each change to swww.
set -uo pipefail

# swww is a `cargo install`, not an apt package, and niri's session env doesn't
# necessarily carry ~/.cargo/bin.
PATH="$HOME/.cargo/bin:$PATH"

SESSION="$HOME/.local/state/DankMaterialShell/session.json"

# ─── Transition ───────────────────────────────────────────────────────────────
# How the change from one wallpaper to the next is animated. This is swww's job
# now, not DMS's: the Transition dropdown in DMS's wallpaper tab drives QML
# shaders on a surface that no longer exists, so most of its names have nothing
# behind them here.
#
# swww's transitions: none simple fade left right top bottom wipe wave grow
# center outer any random. Set TRANSITION to one of those to pin it.
#
# "dms" (the default) follows the picker's dropdown as far as it goes — fade and
# wipe are the two names both sides share, and everything else lands on fade.
#
# The environment wins over both, which is the quick way to audition one without
# editing this file:
#   SWWW_TRANSITION=grow SWWW_TRANSITION_DURATION=1.5 ~/.config/niri/wallpaper-sync.sh
TRANSITION="${SWWW_TRANSITION:-dms}"
TRANSITION_DURATION="${SWWW_TRANSITION_DURATION:-0.5}"   # seconds; swww's own default is 3
TRANSITION_FPS="${SWWW_TRANSITION_FPS:-30}"

# Resolves session.json the way DMS does, printing one "output<TAB>path" line
# per surface to paint. "*" means every output; those lines come first so a
# per-monitor line can override the global one underneath it.
resolve() {
    python3 - "$SESSION" <<'PYEOF' 2>/dev/null
import json, sys

try:
    with open(sys.argv[1]) as f:
        s = json.load(f)
except (OSError, ValueError):
    sys.exit(1)

# Light/dark mode each get their own wallpaper only when perModeWallpaper is on;
# otherwise both modes share the plain wallpaperPath. Mirrors SessionData.qml.
suffix = ("Light" if s.get("isLightMode") else "Dark") if s.get("perModeWallpaper") else ""

glob = s.get("wallpaperPath" + suffix) or s.get("wallpaperPath") or ""
if glob:
    print("*\t" + glob)

if s.get("perMonitorWallpaper"):
    for name, path in (s.get("monitorWallpapers" + suffix) or s.get("monitorWallpapers") or {}).items():
        if path:
            print(name + "\t" + path)
PYEOF
}

apply() {
    local output path filter transition outputs

    if [ "$TRANSITION" = "dms" ]; then
        case "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("wallpaperTransition",""))' "$SESSION" 2>/dev/null)" in
            wipe) transition=wipe ;;
            *)    transition=fade ;;
        esac
    else
        transition="$TRANSITION"
    fi

    while IFS=$'\t' read -r output path; do
        [ -f "$path" ] || continue

        # These wallpapers are small pixel-art loops stretched across a 1440p
        # screen, and Lanczos turns pixel art into mush. Photographs still get
        # swww's default filter.
        case "${path,,}" in
            *.gif) filter=Nearest ;;
            *)     filter=Lanczos3 ;;
        esac

        # --resize crop is swww's name for the "Fill" fill mode set in DMS.
        # --outputs takes no "all" value; leaving it off is what means every output.
        outputs=()
        [ "$output" = "*" ] || outputs=(--outputs "$output")

        swww img "$path" "${outputs[@]}" --resize crop --filter "$filter" \
            --transition-type "$transition" \
            --transition-duration "$TRANSITION_DURATION" \
            --transition-fps "$TRANSITION_FPS"
    done
}

# swww-daemon is spawned alongside this script at niri startup, so it may not
# have its socket up yet.
for _ in $(seq 1 50); do
    swww query &>/dev/null && break
    sleep 0.2
done

last=""

sync_now() {
    local spec
    spec="$(resolve)" || return 0
    # DMS rewrites session.json for unrelated things — launcher history, night
    # mode, the notepad — so re-apply only when the wallpaper itself moved.
    # Without this every launcher search would replay a fade transition.
    [ "$spec" = "$last" ] && return 0
    last="$spec"
    printf '%s\n' "$spec" | apply
}

sync_now

# The session file is replaced rather than written in place, so watch its
# directory: an atomic rename shows up as moved_to, and QML's FileView writes
# land as close_write.
inotifywait -q -m -e close_write,moved_to --format '%f' "$(dirname "$SESSION")" 2>/dev/null |
    while read -r changed; do
        [ "$changed" = "session.json" ] && sync_now
    done
