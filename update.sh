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

# ─── shared helpers ───────────────────────────────────────────────────────────
for _lib in common paths; do
    if [ ! -f "$DOTFILES/lib/$_lib.sh" ]; then
        echo "Missing $DOTFILES/lib/$_lib.sh — run this from a full clone of the repo" >&2
        exit 1
    fi
done
# shellcheck source=/dev/null
source "$DOTFILES/lib/common.sh"
source "$DOTFILES/lib/paths.sh"

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


# ─── the mapped dotfiles ──────────────────────────────────────────────────────
# Everything that is a straight file, from lib/paths.sh — the same rows
# configure.sh deploys, read in the other direction. config.kdl, the
# wallpapers and the VS Code extension list need more than a file pair and are
# handled separately below.
for _row in "${DOTFILES_MAP[@]}"; do
    map_entry "$_row"
    _live="$HOME/$HOME_PATH"
    _repo="$DOTFILES/$REPO_PATH"

    case "$KIND" in
        copy|exec|merge) pull "$_live" "$_repo" ;;
        # Only present on laptops; silent rather than warning on a desktop.
        laptop)          pull_optional "$_live" "$_repo" ;;
        *) warn "lib/paths.sh: unknown kind '$KIND' for $REPO_PATH" ;;
    esac
done


# ─── niri ─────────────────────────────────────────────────────────────────────
# config.kdl gets `include "dms/laptop.kdl"` appended by `install.sh --laptop` on
# laptop machines. That line is machine-specific, not part of the shared base
# config, so strip it back out before it lands in the repo.
if [ -f "$HOME/.config/niri/config.kdl" ]; then
    mkdir -p "$DOTFILES/config/niri"
    # Built to a temp file first so the stripped result — not the raw live file —
    # is what confirm_overwrite compares and shows in the diff.
    NIRI_TMP=$(mktemp)
    # configure.sh appends '\ninclude "dms/laptop.kdl"\n', so undoing it means
    # dropping the include line *and* the one blank line that newline created.
    # Stripping every trailing blank instead would eat the two this file
    # legitimately ends with, and commit that churn on the next update.
    grep -v '^include "dms/laptop.kdl"$' "$HOME/.config/niri/config.kdl" \
        | awk '{lines[NR]=$0} END {last=NR; if (last>0 && lines[last]=="") last--; for(i=1;i<=last;i++) print lines[i]}' \
        > "$NIRI_TMP" || true
    if confirm_overwrite "$NIRI_TMP" "$DOTFILES/config/niri/config.kdl"; then
        cp "$NIRI_TMP" "$DOTFILES/config/niri/config.kdl"
        info "Pulled $HOME/.config/niri/config.kdl"
    fi
    rm -f "$NIRI_TMP"
else
    warn "Not found, skipping: $HOME/.config/niri/config.kdl"
fi
# dms/binds.kdl is deliberately not pulled — see .gitignore.


# ─── DankMaterialShell ────────────────────────────────────────────────────────
# The activetask plugin is gone — the active-task overlay and the task box both
# belong to niri-tasks now, which is its own repo and its own working tree, so
# there is nothing to snapshot back. The third-party plugins under plugins/ are
# git clones owned by install.sh and were never pulled either.

# ─── VS Code ──────────────────────────────────────────────────────────────────
info "Pulling VS Code extensions list"
# Built in a temp file first. Redirecting straight into the repo truncates the
# list before `code` has run, so on any machine where code isn't on PATH — a tty
# session, an ssh login, a box where the snap isn't installed yet — the list was
# emptied and then `set -e` killed the script on the failed command, committing
# the loss. An empty result is treated the same way: more likely a broken `code`
# than a genuine "no extensions installed".
EXT_DST="$DOTFILES/config/Code/extensions.txt"
if command -v code &>/dev/null; then
    EXT_TMP=$(mktemp)
    if code --list-extensions > "$EXT_TMP" 2>/dev/null && [ -s "$EXT_TMP" ]; then
        # cat rather than mv: keeps the repo file's own permissions, and stays
        # correct when /tmp is a different filesystem.
        cat "$EXT_TMP" > "$EXT_DST"
        info "  $(wc -l < "$EXT_DST") extension(s) saved"
    else
        warn "  code --list-extensions returned nothing — keeping the existing list"
    fi
    rm -f "$EXT_TMP"
else
    warn "  code not on PATH — keeping the existing extensions list"
fi

# ─── Wallpapers ───────────────────────────────────────────────────────────────
# The repo carries a wallpaper *collection*, not a single file: the DMS picker
# needs something to pick from, so ~/Documents/Wallpapers is mirrored in whole.
# Nothing is deleted here — a wallpaper removed from the live folder stays in
# the repo until it's deleted there deliberately.
mkdir -p "$DOTFILES/wallpaper/images"

WALLPAPER_DIR="$HOME/Documents/Wallpapers"
if [ -d "$WALLPAPER_DIR" ]; then
    PULLED=0
    for wall in "$WALLPAPER_DIR"/*; do
        [ -f "$wall" ] || continue
        WALL_NAME="$(basename "$wall")"
        # Only image types — the same list DMS's picker and its cycling service
        # filter on. Without this, anything that lands in the folder ends up
        # committed: a .DS_Store, a stray zip, the __MACOSX leftovers that come
        # out of an unzipped download.
        case "${WALL_NAME,,}" in
            *.jpg|*.jpeg|*.png|*.bmp|*.gif|*.webp|*.jxl|*.avif|*.heif|*.exr) ;;
            *) continue ;;
        esac
        WALL_DST="$DOTFILES/wallpaper/images/$WALL_NAME"
        if [ ! -f "$WALL_DST" ] || ! cmp -s "$wall" "$WALL_DST"; then
            info "Pulling wallpaper: $WALL_NAME"
            cp "$wall" "$WALL_DST"
            PULLED=$((PULLED + 1))
        fi
    done
    [ "$PULLED" -eq 0 ] && info "Wallpapers unchanged"
fi

# Which one is selected right now. configure.sh reads this file rather than
# carrying a hardcoded filename.
DMS_SESSION="$HOME/.local/state/DankMaterialShell/session.json"
if [ -f "$DMS_SESSION" ]; then
    ACTIVE_WALL=$(python3 -c "import json; d=json.load(open('$DMS_SESSION')); print(d.get('wallpaperPath',''))" 2>/dev/null || true)
    if [ -n "$ACTIVE_WALL" ] && [ -f "$ACTIVE_WALL" ]; then
        WALL_FILE=$(basename "$ACTIVE_WALL")
        # A wallpaper picked from outside ~/Documents/Wallpapers won't have been
        # copied by the mirror above, so pull it in before recording it.
        if [ ! -f "$DOTFILES/wallpaper/images/$WALL_FILE" ]; then
            info "Pulling active wallpaper from outside $WALLPAPER_DIR: $WALL_FILE"
            cp "$ACTIVE_WALL" "$DOTFILES/wallpaper/images/$WALL_FILE"
        fi
        if [ "$(cat "$DOTFILES/wallpaper/active" 2>/dev/null)" != "$WALL_FILE" ]; then
            info "Active wallpaper: $WALL_FILE"
            echo "$WALL_FILE" > "$DOTFILES/wallpaper/active"
        else
            info "Active wallpaper unchanged: $WALL_FILE"
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
    echo "    bash configure.sh   # install the repo's version to the live config"
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
