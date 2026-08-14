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

# Start new sessions in the project folder that matches the workspace name —
# that's what makes open_project_workspace.sh land you in the project. Fall
# back to ~/Projects (created by install-config.sh), then to $HOME if that's
# missing too, so this still works standalone.
start_dir="$HOME/Projects/$ws"
[ -d "$start_dir" ] || start_dir="$HOME/Projects"
[ -d "$start_dir" ] || start_dir="$HOME"

exec tmux new-session -A -s "$session" -c "$start_dir"