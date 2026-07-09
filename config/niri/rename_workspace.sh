#!/bin/bash
# A clean GUI string pop-up that matches Wayland window protocols
CURRENT_NAME=$(niri msg -j workspaces | jq -r '.[] | select(.is_focused) | .name // empty')
WORKSPACE_NAME=$(zenity --entry --title="Workspace Manager" --text="Rename workspace:" --entry-text="$CURRENT_NAME")

if [ -z "$WORKSPACE_NAME" ]; then
    exit 0
fi

niri msg action set-workspace-name "$WORKSPACE_NAME"
