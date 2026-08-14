#!/bin/bash
# Print the description of the active task for the focused workspace, or
# nothing. One line of output, no trailing decoration — it's meant to be read by
# something else, namely the activetask DMS bar widget.
#
# "Nothing" covers every uninteresting case identically (unnamed workspace, no
# tasks for it, none of them started), because the widget's job is to disappear
# in all of them rather than explain which one it hit.
set -euo pipefail

# shellcheck source=task-lib.sh
source "$(dirname "$(readlink -f "$0")")/task-lib.sh"

WORKSPACE=$(current_workspace_name)
[ -n "$WORKSPACE" ] || exit 0

TAG=$(workspace_tag "$WORKSPACE")
[ -n "$TAG" ] || exit 0

# +ACTIVE is taskwarrior's virtual tag for started tasks. task-list.sh keeps at
# most one per workspace tag, but take the first regardless — a task started by
# hand in a terminal shouldn't produce two lines here.
task rc.verbose=nothing rc.json.array=on "+$TAG" +ACTIVE status:pending export 2>/dev/null \
    | jq -r 'first(.[] | .description) // ""' 2>/dev/null \
    || true
