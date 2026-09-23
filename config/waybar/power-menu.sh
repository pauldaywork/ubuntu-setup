#!/bin/sh
# The top bar's power button (custom/power in config.jsonc). Picking an entry
# is the confirmation; Escape or clicking away picks nothing and does nothing.
#
# fuzzel rather than a dedicated logout tool because it is already the launcher
# and the other pickers, so this looks like them and adds no package.

choice=$(printf '%s\n' "Shut down" "Reboot" "Suspend" "Log out" \
    | fuzzel --dmenu --prompt "⏻  " --lines 4 --width 20) || exit 0

case "$choice" in
    "Shut down") systemctl poweroff ;;
    "Reboot")    systemctl reboot ;;
    "Suspend")   systemctl suspend ;;
    # niri's own quit, without its "are you sure" dialog: the menu was the ask.
    "Log out")   niri msg action quit --skip-confirmation ;;
esac
