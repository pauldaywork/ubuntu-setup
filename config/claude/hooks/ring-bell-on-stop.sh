#!/bin/sh
# Claude Code Stop hook: ring the terminal bell when the main agent finishes a
# turn, so the workspace it runs on gets flagged in the dock.
#
# The bell does the rest without our help. herdr forwards any pane's bell to
# the Ghostty window attached to the session. Ghostty (bell-features attention)
# asks niri for attention only while that window is unfocused. niri marks the
# window, and so its workspace, urgent until the window is focused, and the
# dock styles urgent workspaces. Stop doesn't fire for subagents, which have
# SubagentStop.
#
# Hooks run without a controlling terminal, so /dev/tty isn't there. The claude
# process that spawned us has one, so walk up to the first ancestor with a tty
# and ring that.

cat >/dev/null

pid=$PPID
while [ "${pid:-1}" -gt 1 ]; do
    tty=$(ps -o tty= -p "$pid" | tr -d ' ')
    case "$tty" in
        ''|'?') pid=$(ps -o ppid= -p "$pid" | tr -d ' ') ;;
        *) printf '\a' >"/dev/$tty" 2>/dev/null; exit 0 ;;
    esac
done
exit 0
