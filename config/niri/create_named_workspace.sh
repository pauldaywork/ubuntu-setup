#!/bin/bash
# A clean GUI string pop-up that matches Wayland window protocols
WORKSPACE_NAME=$(zenity --entry --title="Workspace Manager" --text="Enter workspace name:")

if [ -z "$WORKSPACE_NAME" ]; then
    exit 0
fi

# focus-workspace-down only creates a new workspace when you're already on
# the last one; otherwise it just moves to (and would rename) whatever
# workspace already exists below. So jump straight to the last workspace on
# the current output (niri always keeps an empty one there) before naming it.
CURRENT_OUTPUT=$(niri msg -j workspaces | jq -r '.[] | select(.is_focused) | .output')
LAST_IDX=$(niri msg -j workspaces | jq -r --arg output "$CURRENT_OUTPUT" \
    '[.[] | select(.output == $output) | .idx] | max')

niri msg action focus-workspace "$LAST_IDX"
niri msg action set-workspace-name "$WORKSPACE_NAME"
