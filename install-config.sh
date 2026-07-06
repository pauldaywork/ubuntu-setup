#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$HOME"

# ─── flags ─────────────────────────────────────────────────────────────────────
LAPTOP=false
for arg in "$@"; do
    case "$arg" in
        --laptop) LAPTOP=true ;;
    esac
done

# ─── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${GREEN}══${NC} $* ${GREEN}══${NC}"; }

# ─── Copy dotfiles ────────────────────────────────────────────────────────────
section "Copying dotfiles"

# Existing files that would be overwritten are moved here (preserving their
# path relative to $HOME) instead of being left as .bak siblings, so a bad
# install can't get confused with a stray .bak file and the live config tree
# stays clean.
BACKUP_DIR="$USER_HOME/.config-backups/$(date +%Y%m%d-%H%M%S)"
BACKED_UP_ANYTHING=false

copy() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ]; then
        local rel="${dst#"$USER_HOME"/}"
        local backup_dst="$BACKUP_DIR/$rel"
        mkdir -p "$(dirname "$backup_dst")"
        cp -a "$dst" "$backup_dst"
        warn "Backed up existing: $dst → $backup_dst"
        BACKED_UP_ANYTHING=true
    fi
    cp "$src" "$dst"
    info "Copied $dst"
}

# shell
copy "$DOTFILES/home/.bashrc"  "$USER_HOME/.bashrc"
copy "$DOTFILES/home/.profile" "$USER_HOME/.profile"

# taskwarrior
copy "$DOTFILES/home/.taskrc" "$USER_HOME/.taskrc"

# tmux
copy "$DOTFILES/home/.tmux.conf" "$USER_HOME/.tmux.conf"

# niri
copy "$DOTFILES/config/niri/config.kdl"                   "$USER_HOME/.config/niri/config.kdl"
copy "$DOTFILES/config/niri/create_named_workspace.sh"    "$USER_HOME/.config/niri/create_named_workspace.sh"
chmod +x "$USER_HOME/.config/niri/create_named_workspace.sh"
copy "$DOTFILES/config/niri/toggle-window-rules.sh"       "$USER_HOME/.config/niri/toggle-window-rules.sh"
chmod +x "$USER_HOME/.config/niri/toggle-window-rules.sh"
copy "$DOTFILES/config/niri/tmux-niri-session.sh"         "$USER_HOME/.config/niri/tmux-niri-session.sh"
chmod +x "$USER_HOME/.config/niri/tmux-niri-session.sh"
copy "$DOTFILES/config/niri/window-rules/normal.kdl"      "$USER_HOME/.config/niri/window-rules/normal.kdl"
copy "$DOTFILES/config/niri/window-rules/focus.kdl"       "$USER_HOME/.config/niri/window-rules/focus.kdl"
copy "$DOTFILES/config/niri/dms/binds.kdl" "$USER_HOME/.config/niri/dms/binds.kdl"

# Seed the active window-rules profile only if one isn't already chosen,
# so re-running install doesn't reset an existing choice.
if [ ! -e "$USER_HOME/.config/niri/window-rules-active.kdl" ]; then
    ln -s "$USER_HOME/.config/niri/window-rules/focus.kdl" "$USER_HOME/.config/niri/window-rules-active.kdl"
    echo "focus" > "$USER_HOME/.config/niri/.window-rules-profile"
fi

if [ "$LAPTOP" = true ]; then
    info "Applying laptop-specific niri config"
    copy "$DOTFILES/config/niri/dms/laptop.kdl" "$USER_HOME/.config/niri/dms/laptop.kdl"
    printf '\ninclude "dms/laptop.kdl"\n' >> "$USER_HOME/.config/niri/config.kdl"
fi

# ghostty
copy "$DOTFILES/config/ghostty/config.ghostty" "$USER_HOME/.config/ghostty/config.ghostty"
sed -i "s|^command = .*|command = $USER_HOME/.config/niri/tmux-niri-session.sh|" \
    "$USER_HOME/.config/ghostty/config.ghostty"

# DankMaterialShell
copy "$DOTFILES/config/DankMaterialShell/settings.json"        "$USER_HOME/.config/DankMaterialShell/settings.json"
sed -i "s|\"customThemeFile\": \".*\"|\"customThemeFile\": \"$USER_HOME/.config/DankMaterialShell/themes/peaceAndQuiet/theme.json\"|" \
    "$USER_HOME/.config/DankMaterialShell/settings.json"
copy "$DOTFILES/config/DankMaterialShell/plugin_settings.json" "$USER_HOME/.config/DankMaterialShell/plugin_settings.json"
copy "$DOTFILES/config/DankMaterialShell/firefox.css"          "$USER_HOME/.config/DankMaterialShell/firefox.css"
copy "$DOTFILES/config/DankMaterialShell/themes/peaceAndQuiet/theme.json" \
     "$USER_HOME/.config/DankMaterialShell/themes/peaceAndQuiet/theme.json"

# VS Code settings (extensions are not installed here — see install.sh)
copy "$DOTFILES/config/Code/settings.json" "$USER_HOME/.config/Code/User/settings.json"

# ─── Wallpaper ────────────────────────────────────────────────────────────────
section "Setting up wallpaper"

WALLPAPER_DST="$USER_HOME/Documents/Wallpapers/205.png"
mkdir -p "$USER_HOME/Documents/Wallpapers"

if [ ! -f "$WALLPAPER_DST" ]; then
    cp "$DOTFILES/wallpapers/205.png" "$WALLPAPER_DST"
    info "Wallpaper copied to $WALLPAPER_DST"
fi

# Write the DMS session wallpaper path so it loads on first launch
DMS_SESSION="$USER_HOME/.local/state/DankMaterialShell/session.json"
mkdir -p "$(dirname "$DMS_SESSION")"

if [ ! -f "$DMS_SESSION" ]; then
    info "Creating DMS session with wallpaper path"
    python3 - <<PYEOF
import json, os
session = {"wallpaperPath": "$WALLPAPER_DST"}
with open("$DMS_SESSION", "w") as f:
    json.dump(session, f, indent=2)
PYEOF
else
    info "Updating wallpaper path in existing DMS session"
    python3 - <<PYEOF
import json
with open("$DMS_SESSION") as f:
    session = json.load(f)
session["wallpaperPath"] = "$WALLPAPER_DST"
with open("$DMS_SESSION", "w") as f:
    json.dump(session, f, indent=2)
PYEOF
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
section "Config install complete"

if [ "$BACKED_UP_ANYTHING" = true ]; then
    info "Pre-existing configs backed up to $BACKUP_DIR"
fi
