#!/bin/bash
# Pick a folder from ~/Projects, give it a workspace named after the folder,
# and open a terminal in it. The picker is fuzzel in dmenu mode with a
# stripped-down config (see fuzzel/project-picker.ini): no prompt, no headings,
# no buttons — just the folder names. Up/Down moves, Enter or a mouse click
# selects, Esc cancels, and typing filters.
#
# The terminal lands in the right directory because tmux-niri-session.sh starts
# tmux in ~/Projects/<workspace name> when that folder exists.
set -euo pipefail

PROJECTS_DIR="$HOME/Projects"
PICKER_CONFIG="$HOME/.config/fuzzel/project-picker.ini"

fail() {
    if command -v notify-send >/dev/null; then
        notify-send "Open Project" "$1"
    else
        echo "$1" >&2
    fi
    exit 1
}

[ -d "$PROJECTS_DIR" ] || fail "No $PROJECTS_DIR folder found."

mapfile -t PROJECTS < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d \
    -not -name '.*' -printf '%f\n' | sort)

[ "${#PROJECTS[@]}" -gt 0 ] || fail "No project folders in $PROJECTS_DIR."

# Size the window to the list so there are no empty rows and no truncated
# names: as many lines as folders (up to 12, then it scrolls), and wide enough
# for the longest name plus a little breathing room.
LINES=${#PROJECTS[@]}
[ "$LINES" -le 12 ] || LINES=12

WIDTH=0
for p in "${PROJECTS[@]}"; do
    [ "${#p}" -le "$WIDTH" ] || WIDTH=${#p}
done
WIDTH=$((WIDTH + 4))
[ "$WIDTH" -ge 20 ] || WIDTH=20

FUZZEL_ARGS=(--dmenu --no-sort --lines="$LINES" --width="$WIDTH")
[ -f "$PICKER_CONFIG" ] && FUZZEL_ARGS+=(--config="$PICKER_CONFIG")

PROJECT=$(printf '%s\n' "${PROJECTS[@]}" | fuzzel "${FUZZEL_ARGS[@]}" || true)

if [ -z "$PROJECT" ]; then
    exit 0
fi

WORKSPACES=$(niri msg -j workspaces)

if jq -e --arg name "$PROJECT" \
    'any(.[]; (.name // "") | ascii_downcase == ($name | ascii_downcase))' \
    <<<"$WORKSPACES" >/dev/null; then
    # Already opened this project once — go back to its workspace rather than
    # ending up with two workspaces sharing a name.
    niri msg action focus-workspace "$PROJECT"
else
    # focus-workspace-down only creates a new workspace when you're already on
    # the last one; otherwise it just moves to (and would rename) whatever
    # workspace already exists below. So jump straight to the last workspace on
    # the current output (niri always keeps an empty one there) before naming it.
    CURRENT_OUTPUT=$(jq -r '.[] | select(.is_focused) | .output' <<<"$WORKSPACES")
    LAST_IDX=$(jq -r --arg output "$CURRENT_OUTPUT" \
        '[.[] | select(.output == $output) | .idx] | max' <<<"$WORKSPACES")

    niri msg action focus-workspace "$LAST_IDX"
    niri msg action set-workspace-name "$PROJECT"
fi

niri msg action spawn -- ghostty
