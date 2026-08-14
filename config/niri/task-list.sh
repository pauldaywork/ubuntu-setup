#!/bin/bash
# Show this workspace's pending tasks in fuzzel, and act on the one you pick:
# edit, delete, complete, or set active. Bound to Mod+Alt+L.
#
# "This workspace's tasks" means tasks tagged with the workspace name — the same
# tag task-add.sh writes. Only one task per workspace is ever active: setting one
# active stops any other task carrying the tag, so the bar widget
# (task-active.sh) always has a single unambiguous answer.
#
# The list is fed to fuzzel as "<uuid>\t<description>" and displayed with
# --with-nth=2: you read and filter the description, the script gets back the
# uuid. Ids would be shorter but they're renumbered as tasks complete, so a
# stale id can point at the wrong task.
set -euo pipefail

# shellcheck source=task-lib.sh
source "$(dirname "$(readlink -f "$0")")/task-lib.sh"

TAG=$(require_workspace_tag)

# `export` exits non-zero when the filter matches nothing, which under `set -e`
# would kill the script before it can say so.
TASKS_JSON=$(task rc.verbose=nothing rc.json.array=on "+$TAG" status:pending export 2>/dev/null || true)
[ -n "$TASKS_JSON" ] || TASKS_JSON='[]'

# Most urgent first — the same order `task next` would show, so the picker
# agrees with the terminal. The marker flags the active task (taskwarrior sets
# `start` when a task is started).
mapfile -t ROWS < <(jq -r '
    sort_by(-.urgency)
    | .[]
    | [.uuid, ((if .start then "▶ " else "  " end) + .description)]
    | @tsv' <<<"$TASKS_JSON")

if [ "${#ROWS[@]}" -eq 0 ]; then
    task_notify "No pending tasks for +$TAG"
    exit 0
fi

LINES=${#ROWS[@]}
[ "$LINES" -le 12 ] || LINES=12

WIDTH=0
for row in "${ROWS[@]}"; do
    display=${row#*$'\t'}
    [ "${#display}" -le "$WIDTH" ] || WIDTH=${#display}
done
WIDTH=$((WIDTH + 6))
[ "$WIDTH" -ge 40 ] || WIDTH=40
[ "$WIDTH" -le 90 ] || WIDTH=90

SELECTED=$(printf '%s\n' "${ROWS[@]}" | task_fuzzel \
    --with-nth=2 \
    --accept-nth=1 \
    --lines="$LINES" \
    --width="$WIDTH" \
    --prompt="+$TAG " || true)

[ -n "$SELECTED" ] || exit 0

# fuzzel echoes whatever you typed when it matches no entry. That's what makes
# the project picker able to create folders; here it would mean acting on a
# uuid that doesn't exist, so drop anything that isn't one of ours.
UUID=""
for row in "${ROWS[@]}"; do
    if [ "${row%%$'\t'*}" = "$SELECTED" ]; then
        UUID=$SELECTED
        break
    fi
done
[ -n "$UUID" ] || exit 0

DESCRIPTION=$(jq -r --arg uuid "$UUID" 'first(.[] | select(.uuid == $uuid) | .description) // ""' <<<"$TASKS_JSON")

ACTION=$(printf 'Edit\nDelete\nComplete\nSet active\n' | task_fuzzel \
    --lines=4 \
    --width=20 \
    --prompt="" || true)

case "$ACTION" in
    Edit)
        # --search pre-fills the input with the current description, so this is
        # an edit box rather than a retype-it-all box.
        NEW=$(printf '' | task_fuzzel \
            --lines=0 \
            --width="$WIDTH" \
            --prompt="edit " \
            --search="$DESCRIPTION" || true)
        NEW=$(printf '%s' "$NEW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$NEW" ] || [ "$NEW" = "$DESCRIPTION" ]; then
            exit 0
        fi
        # Quoted, unlike task-add.sh: this replaces the description outright, and
        # a stray "due:" typed mid-edit should stay text rather than silently
        # setting a date on a task you were only renaming.
        task rc.confirmation=no rc.verbose=nothing "$UUID" modify -- "$NEW" >/dev/null
        task_notify "Renamed: $NEW"
        ;;

    Delete)
        CONFIRM=$(printf 'No\nYes, delete\n' | task_fuzzel \
            --lines=2 \
            --width="$WIDTH" \
            --prompt="delete? " || true)
        [ "$CONFIRM" = "Yes, delete" ] || exit 0

        task rc.confirmation=no rc.verbose=nothing "$UUID" delete >/dev/null
        task_notify "Deleted: $DESCRIPTION"
        ;;

    Complete)
        task rc.confirmation=no rc.verbose=nothing "$UUID" done >/dev/null
        task_notify "Completed: $DESCRIPTION"
        ;;

    "Set active")
        # Clear the workspace's current active task first, so the tag never has
        # two. `stop` exits 1 when nothing matches, which is the normal case.
        task rc.confirmation=no rc.verbose=nothing "+$TAG" +ACTIVE stop >/dev/null 2>&1 || true
        task rc.confirmation=no rc.verbose=nothing "$UUID" start >/dev/null
        task_notify "Active: $DESCRIPTION"
        ;;

    *)
        exit 0
        ;;
esac
