#!/usr/bin/env bash
# Mod+Alt+/ — every shortcut in fuzzel, and Enter runs the one you pick.
#
# shortcuts.tsv is written by shortcuts/build.py on every configure.sh run: the
# first column is what fuzzel shows, the second the command to run (niri msg
# action …), or nothing for herdr and ghostty keys, which only mean something
# inside those apps. The command runs after fuzzel has closed, so a window action
# lands on the window you had focused, not on the picker.
#
# No lock of our own: fuzzel already refuses to run twice (see config.kdl's note
# on the launcher), and a lock fd would leak into whatever the command starts.
set -u

list="${XDG_DATA_HOME:-$HOME/.local/share}/shortcuts/shortcuts.tsv"
if [ ! -r "$list" ]; then
    notify-send "Shortcuts" "No shortcut list yet — run configure.sh to build it."
    exit 1
fi

# A monospace font, unlike the launcher: build.py lines the key, title and
# category up in columns of spaces, and only a fixed-width font keeps them lined
# up on every screen. DejaVu Sans Mono ships with Ubuntu and has the arrows.
# fuzzel sizes its window in characters, not pixels: at 10pt on the laptop a
# character is 12px, plus 58px of padding, so 95 is the widest under 1200px
# (1196px). No icons: the launcher's icon column would push the right edge off.
# The prompt starts with two spaces to match the list's indent; build.py says why.
cmd=$(fuzzel --dmenu --with-nth=1 --accept-nth=2 --font='DejaVu Sans Mono:size=10' \
             --width=95 --lines=18 --no-icons --prompt='  shortcut › ' <"$list") || exit 0
[ -n "$cmd" ] && exec sh -c "$cmd"
