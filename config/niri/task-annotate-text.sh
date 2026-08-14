#!/bin/bash
# Attach a note to a task: task-annotate-text.sh <uuid> <text>
#
# Quoted, like task-edit-text.sh and unlike task-add-text.sh. Word-split,
# `annotate` reads taskwarrior attributes the same way `add` does — "note about
# the due:friday deadline" silently sets a due date and stores "note about the"
# — which is never what a note means. `--` on top, so a note that opens with a
# dash isn't read as a flag.
#
# Annotations are taskwarrior's own mechanism for detail that doesn't fit in a
# description: many per task, each stamped with when it was written, and
# `description.contains` searches them alongside the description.
set -euo pipefail

# shellcheck source=task-lib.sh
source "$(dirname "$(readlink -f "$0")")/task-lib.sh"

UUID=${1:-}
NOTE=${2:-}

[ -n "$UUID" ] || task_fail "task-annotate-text.sh: no uuid given."

NOTE=$(printf '%s' "$NOTE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[ -n "$NOTE" ] || exit 0

task rc.confirmation=no rc.verbose=nothing "$UUID" annotate -- "$NOTE" >/dev/null

task_notify "Noted: $NOTE"
