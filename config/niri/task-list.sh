#!/bin/bash
# Show this workspace's pending tasks in fuzzel, and act on the one you pick:
# edit, delete, complete, or set active — or add a new one. Bound to Mod+Alt+L.
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
# agrees with the terminal. The leading marker flags the active task
# (taskwarrior sets `start` when a task is started); the trailing ¶ flags a task
# carrying notes, which are otherwise invisible from here — the row shows a
# description, and an annotation isn't one.
#
# `.annotations` is absent rather than empty on a task that has none, hence the
# // [] before counting.
mapfile -t ROWS < <(jq -r '
    sort_by(-.urgency)
    | .[]
    | [.uuid, ((if .start then "▶ " else "  " end)
               + .description
               + (if ((.annotations // []) | length) > 0 then " ¶" else "" end))]
    | @tsv' <<<"$TASKS_JSON")

# A workspace with no tasks yet used to fire a notification and exit without
# ever showing the picker, which is indistinguishable from a dead shortcut —
# especially at a 1s notification timeout. Always show the picker, and give it a
# row that opens the add box, so the list is never empty and pressing the key
# always visibly does something.
#
# This is a real row rather than a reliance on fuzzel echoing text that matches
# no entry. That echo is what lets the project picker create folders, but it
# isn't documented to survive --accept-nth, and a row can't be misread.
ADD_SENTINEL="__add__"
ROWS+=("$ADD_SENTINEL"$'\t'"＋ Add a task…")

LINES=${#ROWS[@]}
[ "$LINES" -le 12 ] || LINES=12

WIDTH=0
for row in "${ROWS[@]}"; do
    display=${row#*$'\t'}
    [ "${#display}" -le "$WIDTH" ] || WIDTH=${#display}
done
WIDTH=$((WIDTH + 6))
[ "$WIDTH" -ge 40 ] || WIDTH=40
# fuzzel's --width is in characters, but at this font each one costs roughly
# 30px, so the old cap of 90 asked for ~2700px on a 1920px screen. fuzzel
# clamped that to the display, and the popup lost its margins and its rounded
# corners to the screen edge — which only showed up once a task description got
# long enough to reach the cap. 52 keeps the widest case comfortably inside a
# 1080p screen; longer descriptions are elided rather than widening the popup.
[ "$WIDTH" -le 52 ] || WIDTH=52

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

# Hand straight over to the add box rather than reimplementing it here, so
# there's one definition of what "adding a task" means (and one place where
# taskwarrior's attribute syntax keeps working).
#
# That box is the DMS modal, same as Mod+Alt+T — asking for it over IPC rather
# than spawning task-add.sh means picking this row gets the multi-line box, not
# a second, narrower one. Falls back to the fuzzel script when DMS isn't
# answering, so the row still does something on a bare niri session.
if [ "$UUID" = "$ADD_SENTINEL" ]; then
    if command -v dms >/dev/null && dms ipc call taskBox open >/dev/null 2>&1; then
        exit 0
    fi
    exec "$(dirname "$(readlink -f "$0")")/task-add.sh"
fi

DESCRIPTION=$(jq -r --arg uuid "$UUID" 'first(.[] | select(.uuid == $uuid) | .description) // ""' <<<"$TASKS_JSON")

ACTION=$(printf 'Edit\nNote\nDelete\nComplete\nSet active\n' | task_fuzzel \
    --lines=5 \
    --width=20 \
    --prompt="" || true)

case "$ACTION" in
    Edit)
        # Same multi-line box as Mod+Alt+T, which matters more here than when
        # adding: the descriptions you reach for the edit box to fix are the
        # long ones, and those are exactly the ones a single fuzzel row showed
        # you a fraction of.
        #
        # Only the uuid is passed — the box fetches the description itself, so
        # no task text goes through `dms ipc call` argument quoting.
        if command -v dms >/dev/null && dms ipc call taskBox edit "$UUID" >/dev/null 2>&1; then
            exit 0
        fi

        # Fallback for a session without DMS. --search pre-fills the input with
        # the current description, so this is an edit box rather than a
        # retype-it-all box.
        NEW=$(printf '' | task_fuzzel \
            --lines=0 \
            --width="$WIDTH" \
            --prompt="edit " \
            --search="$DESCRIPTION" || true)
        NEW=$(printf '%s' "$NEW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$NEW" ] || [ "$NEW" = "$DESCRIPTION" ]; then
            exit 0
        fi
        exec "$(dirname "$(readlink -f "$0")")/task-edit-text.sh" "$UUID" "$NEW"
        ;;

    Note)
        # Taskwarrior annotations: many per task, each stamped with when it was
        # written, and searched by a bare `task <word>` alongside descriptions.
        # This is where detail that doesn't belong in a one-line description
        # goes — the box lists what's already there above the input.
        if command -v dms >/dev/null && dms ipc call taskBox annotate "$UUID" >/dev/null 2>&1; then
            exit 0
        fi

        # Fallback for a session without DMS. No list of existing notes here —
        # fuzzel has nowhere to put one.
        NOTE=$(printf '' | task_fuzzel \
            --lines=0 \
            --width="$WIDTH" \
            --prompt="note " \
            --placeholder="New note…" || true)

        exec "$(dirname "$(readlink -f "$0")")/task-annotate-text.sh" "$UUID" "$NOTE"
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
