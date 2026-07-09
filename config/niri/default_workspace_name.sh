#!/bin/bash
# Name workspace 1 "general" on startup, unless it's already been named.
CURRENT_NAME=$(niri msg -j workspaces | jq -r '[.[] | select(.idx == 1)][0].name // empty')

if [ -z "$CURRENT_NAME" ]; then
    niri msg action set-workspace-name --workspace 1 "general"
fi
