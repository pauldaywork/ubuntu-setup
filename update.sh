#!/usr/bin/env bash
# Pull the latest configs from the live system into the repo.
# Run this whenever you want to snapshot your current setup, then commit.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

pull() {
    local src="$1" dst="$2"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        info "Pulled $src"
    else
        warn "Not found, skipping: $src"
    fi
}

# ─── shell ────────────────────────────────────────────────────────────────────
pull "$HOME/.bashrc"  "$DOTFILES/home/.bashrc"
pull "$HOME/.profile" "$DOTFILES/home/.profile"

# ─── taskwarrior ──────────────────────────────────────────────────────────────
pull "$HOME/.taskrc" "$DOTFILES/home/.taskrc"

# ─── tmux ─────────────────────────────────────────────────────────────────────
pull "$HOME/.tmux.conf" "$DOTFILES/home/.tmux.conf"

# ─── niri ─────────────────────────────────────────────────────────────────────
# config.kdl gets `include "dms/laptop.kdl"` appended by `install.sh --laptop` on
# laptop machines. That line is machine-specific, not part of the shared base
# config, so strip it back out before it lands in the repo.
if [ -f "$HOME/.config/niri/config.kdl" ]; then
    mkdir -p "$DOTFILES/config/niri"
    grep -v '^include "dms/laptop.kdl"$' "$HOME/.config/niri/config.kdl" > "$DOTFILES/config/niri/config.kdl" || true
    info "Pulled $HOME/.config/niri/config.kdl"
else
    warn "Not found, skipping: $HOME/.config/niri/config.kdl"
fi
pull "$HOME/.config/niri/create_named_workspace.sh" "$DOTFILES/config/niri/create_named_workspace.sh"
pull "$HOME/.config/niri/toggle-window-rules.sh"    "$DOTFILES/config/niri/toggle-window-rules.sh"
pull "$HOME/.config/niri/window-rules/normal.kdl"   "$DOTFILES/config/niri/window-rules/normal.kdl"
pull "$HOME/.config/niri/window-rules/focus.kdl"    "$DOTFILES/config/niri/window-rules/focus.kdl"
pull "$HOME/.config/niri/dms/binds.kdl"             "$DOTFILES/config/niri/dms/binds.kdl"

# ─── ghostty ──────────────────────────────────────────────────────────────────
pull "$HOME/.config/ghostty/config.ghostty" "$DOTFILES/config/ghostty/config.ghostty"

# ─── mako ─────────────────────────────────────────────────────────────────────
pull "$HOME/.config/mako/config" "$DOTFILES/config/mako/config"

# ─── DankMaterialShell ────────────────────────────────────────────────────────
pull "$HOME/.config/DankMaterialShell/settings.json"        "$DOTFILES/config/DankMaterialShell/settings.json"
pull "$HOME/.config/DankMaterialShell/plugin_settings.json" "$DOTFILES/config/DankMaterialShell/plugin_settings.json"
pull "$HOME/.config/DankMaterialShell/firefox.css"          "$DOTFILES/config/DankMaterialShell/firefox.css"
pull "$HOME/.config/DankMaterialShell/themes/peaceAndQuiet/theme.json" \
     "$DOTFILES/config/DankMaterialShell/themes/peaceAndQuiet/theme.json"

# ─── VS Code ──────────────────────────────────────────────────────────────────
pull "$HOME/.config/Code/User/settings.json" "$DOTFILES/config/Code/settings.json"
info "Pulling VS Code extensions list"
code --list-extensions 2>/dev/null > "$DOTFILES/config/Code/extensions.txt"
info "  $(wc -l < "$DOTFILES/config/Code/extensions.txt") extension(s) saved"

# ─── Wallpaper ────────────────────────────────────────────────────────────────
DMS_SESSION="$HOME/.local/state/DankMaterialShell/session.json"
if [ -f "$DMS_SESSION" ]; then
    ACTIVE_WALL=$(python3 -c "import json; d=json.load(open('$DMS_SESSION')); print(d.get('wallpaperPath',''))" 2>/dev/null || true)
    if [ -n "$ACTIVE_WALL" ] && [ -f "$ACTIVE_WALL" ]; then
        WALL_FILE=$(basename "$ACTIVE_WALL")
        WALL_DST="$DOTFILES/wallpapers/$WALL_FILE"
        if [ ! -f "$WALL_DST" ] || ! cmp -s "$ACTIVE_WALL" "$WALL_DST"; then
            info "Pulling wallpaper: $WALL_FILE"
            mkdir -p "$DOTFILES/wallpapers"
            find "$DOTFILES/wallpapers" -type f -delete
            cp "$ACTIVE_WALL" "$WALL_DST"
            sed -i "s|wallpapers/[^ ]*|wallpapers/$WALL_FILE|g" "$DOTFILES/install.sh"
            sed -i "s|Documents/Wallpapers/[^ \"]*|Documents/Wallpapers/$WALL_FILE|g" "$DOTFILES/install.sh"
        else
            info "Wallpaper unchanged: $WALL_FILE"
        fi
    else
        warn "Could not read active wallpaper from DMS session"
    fi
fi

# ─── Git status ───────────────────────────────────────────────────────────────
echo ""
cd "$DOTFILES"
if ! git rev-parse --git-dir &>/dev/null; then
    warn "Not a git repo yet. To start tracking changes:"
    echo "  cd $DOTFILES && git init && git add -A && git commit -m 'Initial configs'"
elif git diff --quiet && git diff --cached --quiet; then
    info "No changes — repo is already up to date"
else
    info "Changes ready to commit:"
    git diff --stat
    echo ""
    echo "  git add -A && git commit -m 'Update configs'"
fi
