#!/usr/bin/env bash
# The workspace bar, only while there is something worth showing on it.
#
# waybar.service draws the top bar from config.jsonc; this script owns a
# second waybar process for the two bottom bars in dock.jsonc — the workspace
# row and the current workspace's card. When "general" is the only named
# workspace, that row is a lone card reading "general" (the names either side
# are already blank), so the bottom of the screen stays empty instead: the
# dock process runs only while some workspace besides general is named.
#
# It has to be the whole process. The card is blurred by a niri layer-rule
# against its surface, so hiding it with CSS would leave a blurred card-shaped
# ghost, and waybar's two signals cannot say show *and* hide to these bars
# while Mod+Alt+M keeps SIGUSR1 for the top bar. A process that exists or
# does not is also the one state that cannot desync: every decision below
# re-checks reality rather than remembering it.
#
# niri's event stream opens with a full workspace snapshot, so the first
# event settles the initial state; unnamed workspaces (niri's permanent
# trailing empty one) never count, because the bar has nothing to show for
# them anyway.
#
# Run by waybar-dock.service.

set -u

DOCK_CONFIG="$HOME/.config/waybar/dock.jsonc"

# A previous watcher's dock would double every bar; there is at most one.
# The pattern cannot match this script: pgrep -f sees "bash .../dock-watch.sh".
pkill -f "waybar -c $DOCK_CONFIG" 2>/dev/null

dock_pid=

dock_running() {
    [ -n "$dock_pid" ] && kill -0 "$dock_pid" 2>/dev/null
}

show() {
    dock_running && return
    waybar -c "$DOCK_CONFIG" &
    dock_pid=$!
}

hide() {
    dock_running || { dock_pid=; return; }
    kill "$dock_pid" 2>/dev/null
    wait "$dock_pid" 2>/dev/null
    dock_pid=
}

trap hide EXIT

# One JSON object per line; only workspace events produce output, and each
# yields the count of workspaces named something other than "general".
while IFS= read -r named; do
    if [ "$named" -gt 0 ]; then
        show
    else
        hide
    fi
done < <(
    niri msg --json event-stream | jq --unbuffered -r '
        .WorkspacesChanged.workspaces // empty
        | map(select(.name != null and .name != "general")) | length'
)

# The stream only ends with niri, and the dock should not outlive it.
hide
