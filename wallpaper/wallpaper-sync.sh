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
# editing this file. Stop the unit first — pkill won't do, systemd would just
# restart the plain script over the top of yours:
#
#   systemctl --user stop wallpaper-sync.service
#   SWWW_TRANSITION=grow SWWW_TRANSITION_DURATION=1.5 ~/.config/niri/wallpaper-sync.sh &
#   # …change wallpaper a few times, then:
#   kill %1; systemctl --user start wallpaper-sync.service
#
# Settle on one and edit the defaults above: the environment version dies with
# the shell, and the unit runs the plain script. Anything more exotic
# (--transition-angle, --transition-pos, --transition-bezier, --transition-wave)
# is a flag in `swww img --help`; add it next to the others in apply().
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
    local output path filter transition outputs failed=0

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

        # These wallpapers are small pixel-art loops stretched to fill the
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
            --transition-fps "$TRANSITION_FPS" || failed=1
    done
    return "$failed"
}

last=""
last_pid=""

sync_now() {
    local spec pid
    spec="$(resolve)" || return 1
    pid="$(pgrep -x swww-daemon || true)"

    # DMS rewrites session.json for unrelated things — launcher history, night
    # mode, the notepad — so re-apply only when the wallpaper itself moved.
    # Without this every launcher search would replay a fade transition.
    #
    # A restarted daemon counts as a move even when the wallpaper didn't: it
    # comes back showing its own cached image, which is whatever it last drew
    # rather than whatever DMS has since selected. Comparing the pid catches
    # that; an empty pid (daemon down) never matches, so we keep trying.
    #
    # This only fires on the next session.json write, though, so it can't be the
    # whole answer — a daemon restart writes nothing. swww-daemon.service has an
    # ExecStartPost that restarts this script for exactly that reason. The pid
    # check is what keeps the script correct when run by hand, without systemd.
    [ "$spec" = "$last" ] && [ "$pid" = "$last_pid" ] && return 0

    # Only remember it as applied if it actually applied. Recording it up front
    # meant one failed paint — daemon still starting, daemon crashed — left the
    # screen and DMS permanently disagreeing, because every later check saw a
    # spec it thought was already on screen and skipped it.
    printf '%s\n' "$spec" | apply || return 1
    last="$spec"
    last_pid="$pid"
}

# swww-daemon is spawned alongside this script at niri startup, so the first
# paint usually loses a race with it. Retrying until one lands replaces waiting
# on `swww query`, and also covers a daemon that takes its time or dies once.
for _ in $(seq 1 30); do
    sync_now && break
    sleep 1
done

# The session file is replaced rather than written in place, so watch its
# directory: an atomic rename shows up as moved_to, and QML's FileView writes
# land as close_write.
inotifywait -q -m -e close_write,moved_to --format '%f' "$(dirname "$SESSION")" 2>/dev/null |
    while read -r changed; do
        [ "$changed" = "session.json" ] && sync_now
    done
