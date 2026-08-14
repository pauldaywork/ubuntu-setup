#!/bin/bash
# Print one task's description: task-get-text.sh <uuid>
#
# The edit box pre-fills from this rather than being handed the text over IPC.
# Only the uuid crosses that boundary — hex and dashes, nothing a shell or an
# argument parser can misread — so a description containing quotes, spaces or
# anything else arrives intact regardless of how `dms ipc call` handles its
# arguments.
#
# Silent on failure, like task-tag.sh: the caller is a GUI and reports the
# problem its own way.
set -euo pipefail

UUID=${1:-}
[ -n "$UUID" ] || exit 1

DESCRIPTION=$(task rc.verbose=nothing rc.json.array=on "$UUID" export 2>/dev/null \
    | jq -r 'first(.[] | .description) // ""' 2>/dev/null) || exit 1

[ -n "$DESCRIPTION" ] || exit 1

printf '%s' "$DESCRIPTION"
