#!/bin/bash
# Shared helpers for the taskwarrior scripts driven from niri shortcuts:
# task-add.sh (Mod+Alt+T) and task-list.sh (Mod+Alt+L). Sourced, not run.
#
# The idea tying them together: every task is tagged with the name of the
# workspace it was created on, so "my tasks" always means "the tasks for the
# project I'm looking at". Nothing here knows about ~/Projects — it goes purely
# off the niri workspace name, which open_project_workspace.sh sets to the
# folder name.

# Same stripped-down fuzzel theme the project picker uses.
TASK_PICKER_CONFIG="$HOME/.config/fuzzel/project-picker.ini"

task_notify() {
    if command -v notify-send >/dev/null; then
        notify-send "Tasks" "$1"
    else
        echo "$1" >&2
    fi
}

task_fail() {
    task_notify "$1"
    exit 1
}

# Name of the focused workspace, or empty — niri workspaces are unnamed until
# something names them, and an unnamed workspace has no tag to scope tasks to.
current_workspace_name() {
    niri msg -j workspaces | jq -r 'first(.[] | select(.is_focused) | .name) // ""'
}

# A taskwarrior tag is a single bare word: dashes read as operators inside
# filters and spaces split the argument, so neither survives `task +<tag>`.
# Fold everything else to underscores and lowercase, which also means
# "Ubuntu-Setup", "ubuntu setup" and "ubuntu-setup" all resolve to the one tag
# rather than three tags holding a third of the project's tasks each.
workspace_tag() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9_]\+/_/g' -e 's/^_\+//' -e 's/_\+$//'
}

# Every script here starts the same way: refuse to run rather than guess a tag.
# Writing untagged tasks would be worse than doing nothing — they'd be invisible
# to every list, since the list is always filtered by tag.
require_workspace_tag() {
    local name tag
    name=$(current_workspace_name)
    [ -n "$name" ] || task_fail "This workspace has no name — name it with Mod+Shift+Alt+W first."

    tag=$(workspace_tag "$name")
    [ -n "$tag" ] || task_fail "Workspace name '$name' has no usable tag characters."

    printf '%s' "$tag"
}

# Common fuzzel invocation. Callers add --lines/--width and their own flags.
task_fuzzel() {
    local args=(--dmenu)
    [ -f "$TASK_PICKER_CONFIG" ] && args+=(--config="$TASK_PICKER_CONFIG")
    fuzzel "${args[@]}" "$@"
}
