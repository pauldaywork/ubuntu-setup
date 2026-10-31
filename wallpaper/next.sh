#!/usr/bin/env bash
# The next wallpaper along: Mod+Alt+Ctrl+B.
#
# The companion to the picker on Mod+Alt+B (hyprquickpaper): no list, just the
# wallpaper after the current one, in filename order, wrapping round at the
# end. An order rather than a dice roll, so that pressing it N times always
# lands in the same place and every wallpaper comes round once per lap. A
# current one that is not in the folder (renamed, deleted, never set) starts
# from the first.
#
# Like the picker, it only writes the selection and hands off to
# wallpaper-apply.sh. That script owns every swww flag — the Nearest filter on
# GIFs, the retries while the daemon comes up — and two callers of swww with
# two ideas about the flags is how those drift apart.
set -euo pipefail

WALLPAPERS="$HOME/Documents/Wallpapers"
ACTIVE="$HOME/.config/niri/wallpaper-active"
APPLY="$HOME/.config/niri/wallpaper-apply.sh"

die() {
    echo "$*" >&2
    command -v notify-send &>/dev/null && notify-send "Wallpaper" "$*"
    exit 1
}

[ -d "$WALLPAPERS" ] || die "No wallpaper directory: $WALLPAPERS"
[ -x "$APPLY" ] || die "wallpaper-apply.sh missing or not executable — run configure.sh"

# bash sorts a glob, so the order holds from one press to the next; nullglob
# makes an empty folder an empty list rather than the unmatched pattern.
CYCLE=()
shopt -s nullglob
for wall in "$WALLPAPERS"/*; do
    [ -f "$wall" ] && CYCLE+=("$wall")
done
shopt -u nullglob
[ "${#CYCLE[@]}" -gt 0 ] || die "No wallpapers in $WALLPAPERS"

current="$(head -n1 "$ACTIVE" 2>/dev/null || true)"
next=0
for i in "${!CYCLE[@]}"; do
    if [ "${CYCLE[$i]}" = "$current" ]; then
        next=$(( (i + 1) % ${#CYCLE[@]} ))
        break
    fi
done

printf '%s\n' "${CYCLE[$next]}" > "$ACTIVE"

# exec, so the exit status you see is the paint's and not this script's.
exec "$APPLY"
