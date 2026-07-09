#!/usr/bin/env bash
set -euo pipefail

# Get the focused workspace's name, falling back to its index if unnamed
ws=$(niri msg -j workspaces | jq -r '.[] | select(.is_focused==true) | .name // (.idx|tostring)')
ws=${ws:-unknown}

# Sanitize (tmux session names dislike ':' '.' and spaces cause quoting pain)
ws_clean=$(echo "$ws" | tr -c 'A-Za-z0-9_-' '_')

# Find the smallest unused number for this workspace name
n=1
while tmux has-session -t "${ws_clean}${n}" 2>/dev/null; do
  n=$((n + 1))
done

session="${ws_clean}${n}"

# Start new sessions in ~/Projects (created by install-config.sh); fall back
# to $HOME if it's missing so this still works standalone.
start_dir="$HOME/Projects"
[ -d "$start_dir" ] || start_dir="$HOME"

exec tmux new-session -A -s "$session" -c "$start_dir"