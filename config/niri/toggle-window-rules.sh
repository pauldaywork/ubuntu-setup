#!/usr/bin/env bash
set -euo pipefail

niri_dir="$HOME/.config/niri"
profiles_dir="$niri_dir/window-rules"
active_link="$niri_dir/window-rules-active.kdl"
state_file="$niri_dir/.window-rules-profile"
profiles=(normal focus)

current="focus"
[ -f "$state_file" ] && current="$(cat "$state_file")"

next="normal"
for i in "${!profiles[@]}"; do
    if [ "${profiles[$i]}" = "$current" ]; then
        next="${profiles[$(((i + 1) % ${#profiles[@]}))]}"
        break
    fi
done

ln -sf "$profiles_dir/$next.kdl" "$active_link"
echo "$next" > "$state_file"
niri msg action load-config-file

command -v notify-send &>/dev/null && notify-send "niri" "Window rules: $next"
