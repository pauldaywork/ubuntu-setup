#!/bin/bash
# Type a task into a fuzzel box; it's added with the current workspace's name as
# a tag. Bound to Mod+Alt+T.
#
# There's no list here — just an input row. Enter adds, Esc cancels.
#
# Taskwarrior's own attribute syntax works, so "ship the release due:friday
# priority:H" sets a due date and a priority rather than becoming part of the
# description. That only happens when the text reaches `task` as separate
# arguments, which is why the description is deliberately word-split below.
set -euo pipefail

# shellcheck source=task-lib.sh
source "$(dirname "$(readlink -f "$0")")/task-lib.sh"

TAG=$(require_workspace_tag)

DESCRIPTION=$(printf '' | task_fuzzel \
    --lines=0 \
    --width=48 \
    --prompt="+$TAG " \
    --placeholder="New task…" || true)

DESCRIPTION=$(printf '%s' "$DESCRIPTION" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[ -n "$DESCRIPTION" ] || exit 0

# Word-splitting is the point (see above), but it comes with the shell's other
# habit: without noglob, a task like "clean up * files" would expand the * to
# whatever is in the current directory and store that instead.
set -f
# shellcheck disable=SC2086
task rc.confirmation=no rc.verbose=nothing add $DESCRIPTION "+$TAG" >/dev/null
set +f

task_notify "Added to +$TAG: $DESCRIPTION"
