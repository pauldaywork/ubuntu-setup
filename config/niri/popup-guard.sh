#!/usr/bin/env bash
# One popup at a time.
#
# Run a popup-opening command while holding a lock, and do nothing at all if
# something else already holds it:
#
#     popup-guard.sh fuzzel
#     popup-guard.sh ~/.config/niri/wallpaper-pick.sh
#
# The problem this solves is not what it looks like. fuzzel already refuses to
# run twice — it takes an flock on $XDG_RUNTIME_DIR/fuzzel-$WAYLAND_DISPLAY.lock
# and a second instance dies with "failed to acquire lock: fuzzel already
# running?", in --dmenu mode as well as as a launcher. So no two pickers can
# ever stack, whichever shortcut opens them.
#
# What does stack is anything that is not fuzzel. niri-tasks' task box
# (Mod+Alt+T, and the edit and annotate paths off Mod+Alt+L) is a GTK window
# with no lock of its own, and fuzzel's lock does not know it exists: the box
# opens on top of an open picker, and a picker opens on top of an open box.
# Guarding one program against itself cannot fix that. The lock has to be one
# lock shared by every shortcut that puts a popup on screen, regardless of what
# draws it — which is why this is a wrapper and not a check inside any one tool.
#
# flock -n rather than a pgrep test, for two reasons. It cannot race: two
# keypresses landing together cannot both see "nothing running" and both open.
# And the lock is held by the kernel on behalf of the process, so it is released
# when the popup exits however it exits — including killed, crashed, or the
# compositor going down under it. There is no stale lock file to clean up; the
# file itself is just a handle and is meant to stay behind.
#
# A held lock means the keypress does nothing, silently. No notification: you
# pressed a key expecting a popup, and being told off for it is worse than the
# key appearing not to work while a popup you can see is already open.
#
# The one cost: a popup that hangs holds the lock, and the shortcuts stay dead
# until it goes away. Killing it releases the lock immediately.
set -euo pipefail

# Must match the path niri-tasks uses in its own binds (niri/niri-tasks.kdl in
# that repo). The two do not share any code, only this string — a lock nobody
# else takes is a lock that does nothing, so if it changes here it changes
# there. XDG_RUNTIME_DIR is always set in a systemd session; the fallback is for
# the case where it is not, and both sides spell it the same way so they still
# agree on which file to open.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/niri-popup.lock"

# exec, so the popup replaces this shell rather than being its child: the lock
# then belongs to the popup's own process and lasts exactly as long as it does.
#
# flock exits 1 immediately when the lock is held, which niri ignores — a bind
# that "fails" this way is the whole point.
exec flock -n "$LOCK" "$@"
