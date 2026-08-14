#!/usr/bin/env bash
# Pull the latest configs from the live system into the repo.
# Run this whenever you want to snapshot your current setup, then commit.
#
#   bash update.sh          # asks before discarding uncommitted repo edits
#   bash update.sh --yes    # overwrites them without asking
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── flags ─────────────────────────────────────────────────────────────────────
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=true ;;
    esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

# ─── Guarding against overwriting work that exists nowhere else ───────────────
# Copying a live file over the repo's is this script's entire job, so "these two
# files differ" is the normal case — warning on that would fire every run and
# train you to hit Enter through it.
#
# The case worth stopping for is narrower: a repo file with *uncommitted*
# changes. Those exist in exactly one place, so overwriting one destroys work
# git cannot bring back. That's how the Mod+Alt+P spawn-only-if-empty change was
# lost — edited in the repo, never installed to the live config, so the next
# update.sh faithfully copied the stale live version over the top of it.
#
# A repo file that matches HEAD is always recoverable with `git checkout`, so it
# gets pulled silently exactly as before. Untracked files count as uncommitted:
# there's no committed version of those to fall back on either.
SKIPPED_ANY=false

if git -C "$DOTFILES" rev-parse --git-dir &>/dev/null; then
    IS_GIT_REPO=true
else
    IS_GIT_REPO=false
fi

repo_file_is_uncommitted() {
    local dst="$1"
    [ "$IS_GIT_REPO" = true ] || return 1
    [ -n "$(git -C "$DOTFILES" status --porcelain -- "${dst#"$DOTFILES"/}" 2>/dev/null)" ]
}

# 0 = go ahead and overwrite, 1 = leave the repo file alone.
confirm_overwrite() {
    local src="$1" dst="$2"

    # Nothing to lose: no repo file yet, or the two already agree.
    [ -f "$dst" ] || return 0
    cmp -s "$src" "$dst" && return 0

    # Committed and unmodified — `git checkout` can undo this pull.
    repo_file_is_uncommitted "$dst" || return 0

    local rel="${dst#"$DOTFILES"/}"
    echo ""
    warn "Uncommitted repo changes would be discarded: $rel"
    echo "    These edits are only in the repo. If they were never installed to the"
    echo "    live config, pulling now overwrites them with the older live version."
    echo ""
    # `|| true` covers both diff's exit 1 for differing files and head's SIGPIPE,
    # either of which would otherwise trip pipefail.
    { diff -u --label "repo: $rel (would be lost)" --label "live: $src (would replace it)" \
        "$dst" "$src" | head -40 | sed 's/^/    /'; } 2>/dev/null || true
    echo ""

    if [ "$ASSUME_YES" = true ]; then
        warn "  --yes given — overwriting"
        return 0
    fi

    if [ ! -t 0 ]; then
        warn "  Not running interactively — keeping the repo version."
        warn "  Re-run in a terminal to decide, or pass --yes to overwrite."
        SKIPPED_ANY=true
        return 1
    fi

    local reply=""
    read -rp "    Overwrite $rel with the live version? [y/N] " reply || true
    case "$reply" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *)
            info "Kept the repo version of $rel"
            SKIPPED_ANY=true
            return 1
            ;;
    esac
}

pull() {
    local src="$1" dst="$2"
    if [ -f "$src" ]; then
        confirm_overwrite "$src" "$dst" || return 0
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
    # Built to a temp file first so the stripped result — not the raw live file —
    # is what confirm_overwrite compares and shows in the diff.
    NIRI_TMP=$(mktemp)
    grep -v '^include "dms/laptop.kdl"$' "$HOME/.config/niri/config.kdl" > "$NIRI_TMP" || true
    if confirm_overwrite "$NIRI_TMP" "$DOTFILES/config/niri/config.kdl"; then
        cp "$NIRI_TMP" "$DOTFILES/config/niri/config.kdl"
        info "Pulled $HOME/.config/niri/config.kdl"
    fi
    rm -f "$NIRI_TMP"
else
    warn "Not found, skipping: $HOME/.config/niri/config.kdl"
fi
pull "$HOME/.config/niri/create_named_workspace.sh" "$DOTFILES/config/niri/create_named_workspace.sh"
pull "$HOME/.config/niri/rename_workspace.sh"       "$DOTFILES/config/niri/rename_workspace.sh"
pull "$HOME/.config/niri/open_project_workspace.sh" "$DOTFILES/config/niri/open_project_workspace.sh"
pull "$HOME/.config/niri/default_workspace_name.sh" "$DOTFILES/config/niri/default_workspace_name.sh"
pull "$HOME/.config/niri/tmux-niri-session.sh"      "$DOTFILES/config/niri/tmux-niri-session.sh"
pull "$HOME/.config/niri/toggle-window-rules.sh"    "$DOTFILES/config/niri/toggle-window-rules.sh"
pull "$HOME/.config/niri/task-lib.sh"               "$DOTFILES/config/niri/task-lib.sh"
pull "$HOME/.config/niri/task-add.sh"               "$DOTFILES/config/niri/task-add.sh"
pull "$HOME/.config/niri/task-list.sh"              "$DOTFILES/config/niri/task-list.sh"
pull "$HOME/.config/niri/task-active.sh"            "$DOTFILES/config/niri/task-active.sh"
pull "$HOME/.config/niri/window-rules/normal.kdl"   "$DOTFILES/config/niri/window-rules/normal.kdl"
pull "$HOME/.config/niri/window-rules/focus.kdl"    "$DOTFILES/config/niri/window-rules/focus.kdl"
# dms/binds.kdl is deliberately not pulled — see .gitignore.

# ─── fuzzel ───────────────────────────────────────────────────────────────────
pull "$HOME/.config/fuzzel/project-picker.ini" "$DOTFILES/config/fuzzel/project-picker.ini"

# ─── ghostty ──────────────────────────────────────────────────────────────────
pull "$HOME/.config/ghostty/config.ghostty" "$DOTFILES/config/ghostty/config.ghostty"

# ─── DankMaterialShell ────────────────────────────────────────────────────────
pull "$HOME/.config/DankMaterialShell/settings.json"        "$DOTFILES/config/DankMaterialShell/settings.json"
pull "$HOME/.config/DankMaterialShell/plugin_settings.json" "$DOTFILES/config/DankMaterialShell/plugin_settings.json"
pull "$HOME/.config/DankMaterialShell/firefox.css"          "$DOTFILES/config/DankMaterialShell/firefox.css"
pull "$HOME/.config/DankMaterialShell/themes/peaceAndQuiet/theme.json" \
     "$DOTFILES/config/DankMaterialShell/themes/peaceAndQuiet/theme.json"
# Only our own plugin is pulled back. The third-party ones under plugins/ are
# git clones owned by install.sh, and snapshotting them here would vendor
# somebody else's repo into this one.
pull "$HOME/.config/DankMaterialShell/plugins/activetask/plugin.json" \
     "$DOTFILES/config/DankMaterialShell/plugins/activetask/plugin.json"
pull "$HOME/.config/DankMaterialShell/plugins/activetask/ActiveTaskWidget.qml" \
     "$DOTFILES/config/DankMaterialShell/plugins/activetask/ActiveTaskWidget.qml"

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

if [ "$SKIPPED_ANY" = true ]; then
    warn "Some repo files were left alone to protect uncommitted changes."
    echo "  Those edits aren't on this machine yet. To get everything agreeing again:"
    echo ""
    echo "    bash install-config.sh   # install the repo's version to the live config"
    echo "    bash update.sh           # then this pull becomes a no-op"
    echo ""
    echo "  Or commit them first, so a later pull can be undone with git checkout."
    echo ""
fi

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
