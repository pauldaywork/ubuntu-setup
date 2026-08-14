#!/bin/bash
# Type a task into a fuzzel box; it's added with the current workspace's name as
# a tag.
#
# There's no list here — just an input row. Enter adds, Esc cancels.
#
# The Mod+Alt+T shortcut now opens the DMS modal instead (a multi-line box that
# costs no process launch, since the shell is already running). This stays as
# the fallback for a session where DMS isn't up: same tag, same taskwarrior
# call, one line of input instead of several.
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=task-lib.sh
source "$SCRIPT_DIR/task-lib.sh"

TAG=$(require_workspace_tag)

DESCRIPTION=$(printf '' | task_fuzzel \
    --lines=0 \
    --width=48 \
    --prompt="+$TAG " \
    --placeholder="New task…" || true)

# Trimming, the taskwarrior call and the notification all live in
# task-add-text.sh, shared with the modal.
exec "$SCRIPT_DIR/task-add-text.sh" "$TAG" "$DESCRIPTION"
