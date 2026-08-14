#!/bin/bash
# Print the taskwarrior tag for the focused workspace, or nothing.
#
# Exists so the DMS task-add plugin can ask the same question the shell scripts
# ask without reimplementing workspace_tag() in QML — the "one workspace name ->
# one tag" rule in task-lib.sh stays the only definition.
#
# Unlike require_workspace_tag(), a missing tag is silent here: exit 1 with no
# output. The caller is a GUI, so it reports the problem its own way rather than
# firing a notification from underneath.
set -euo pipefail

# shellcheck source=task-lib.sh
source "$(dirname "$(readlink -f "$0")")/task-lib.sh"

WORKSPACE=$(current_workspace_name)
[ -n "$WORKSPACE" ] || exit 1

TAG=$(workspace_tag "$WORKSPACE")
[ -n "$TAG" ] || exit 1

printf '%s' "$TAG"
