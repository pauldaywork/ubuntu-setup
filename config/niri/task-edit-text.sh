#!/bin/bash
# Replace one task's description: task-edit-text.sh <uuid> <description>
#
# The counterpart to task-add-text.sh, and deliberately its opposite in one
# way: the description is quoted here, not word-split. Adding a task is where
# taskwarrior's attribute syntax earns its keep ("ship it due:friday"), but a
# "due:" typed while renaming an existing task should stay text rather than
# silently putting a date on something you were only retitling.
set -euo pipefail

# shellcheck source=task-lib.sh
source "$(dirname "$(readlink -f "$0")")/task-lib.sh"

UUID=${1:-}
DESCRIPTION=${2:-}

[ -n "$UUID" ] || task_fail "task-edit-text.sh: no uuid given."

DESCRIPTION=$(printf '%s' "$DESCRIPTION" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
# An empty box means "leave it alone". Clearing a description isn't something
# taskwarrior will do anyway — `modify -- ""` is rejected — so the alternative
# to exiting here is an error the user never asked for.
[ -n "$DESCRIPTION" ] || exit 0

task rc.confirmation=no rc.verbose=nothing "$UUID" modify -- "$DESCRIPTION" >/dev/null

task_notify "Renamed: $DESCRIPTION"
