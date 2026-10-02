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
# process that spawned us has a tty when it is interactive, so walk up to that
# process and ring its own tty. A headless claude (claude -p, from a script, a
# skill or the Bash tool) has no tty and rings nothing: climbing past it would
# ring the outer agent's pane, or an unrelated terminal, while the real agent is
# still working. Never ring any other process's tty.

cat >/dev/null

pid=$PPID
while [ "${pid:-1}" -gt 1 ]; do
    if [ "$(ps -o comm= -p "$pid" | tr -d ' ')" = claude ]; then
        tty=$(ps -o tty= -p "$pid" | tr -d ' ')
        case "$tty" in
            ''|'?') ;;
            *) printf '\a' >"/dev/$tty" 2>/dev/null ;;
        esac
        exit 0
    fi
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done
exit 0
