#!/bin/bash
# Print a task's existing notes: task-get-notes.sh <uuid>
#
# One annotation per line, "YYYY-MM-DD  text", oldest first — the order
# taskwarrior stores them in, which is the order they were written.
#
# The note box lists these above its input so you can see what's already there
# before adding to it. Without that, notes would be write-only from the GUI and
# only readable by dropping to `task <id> info` in a terminal.
#
# A task with no annotations is not a failure: it prints nothing and exits 0,
# because "no notes yet" is the normal state of most tasks. Only a uuid that
# doesn't resolve is an error.
set -euo pipefail

UUID=${1:-}
[ -n "$UUID" ] || exit 1

JSON=$(task rc.verbose=nothing rc.json.array=on "$UUID" export 2>/dev/null) || exit 1
# A uuid that matches nothing exports "[]", which is valid JSON and would
# otherwise be indistinguishable here from a task that simply has no notes.
[ "$(jq 'length' <<<"$JSON" 2>/dev/null || echo 0)" -gt 0 ] || exit 1

# Whitespace inside a note is collapsed on the way out so one annotation is
# always one line here, however it got into the database.
jq -r '
    first(.[]) // empty
    | (.annotations // [])[]
    | (.entry[0:4] + "-" + .entry[4:6] + "-" + .entry[6:8])
      + "  "
      + (.description | gsub("\\s+"; " "))
' <<<"$JSON" 2>/dev/null || true
