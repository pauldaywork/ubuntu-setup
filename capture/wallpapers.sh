#!/usr/bin/env bash
# Capture wallpapers and the current selection into the repo.
#
#   bash capture/wallpapers.sh [--dry-run]
#
# Two separate things, both machine-only:
#   - images you have added to ~/Documents/Wallpapers, which have no other route
#     into the repo
#   - which one DMS currently has selected, recorded in wallpaper/active so a
#     fresh machine boots the same background

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES/capture/common.sh"

section "Capturing wallpapers"

LIVE_DIR="$HOME/Documents/Wallpapers"
REPO_DIR="$DOTFILES/wallpaper/images"
ACTIVE_FILE="$DOTFILES/wallpaper/active"
mkdir -p "$REPO_DIR"

# ─── images ───────────────────────────────────────────────────────────────────
# Nothing is deleted here: a wallpaper removed from the live folder stays in the
# repo until you delete it there deliberately. Deleting on your behalf would
# make a tidy-up on one machine silently destroy the collection.
if [ -d "$LIVE_DIR" ]; then
    NEW=0
    for wall in "$LIVE_DIR"/*; do
        [ -f "$wall" ] || continue
        name="$(basename "$wall")"
        # Image types only — the same list DMS's picker filters on. Without it,
        # anything that lands in the folder gets committed: a .DS_Store, a stray
        # zip, the __MACOSX leftovers out of an unzipped download.
        case "${name,,}" in
            *.jpg|*.jpeg|*.png|*.bmp|*.gif|*.webp|*.jxl|*.avif|*.heif|*.exr) ;;
            *) continue ;;
        esac
        dst="$REPO_DIR/$name"
        if [ ! -f "$dst" ] || ! cmp -s "$wall" "$dst"; then
            if [ "$DRY_RUN" = true ]; then
                info "Would add wallpaper: $name ($(du -h "$wall" | cut -f1))"
            else
                cp "$wall" "$dst"
                info "Captured wallpaper: $name"
            fi
            NEW=$((NEW + 1)); captured
        fi
    done
    [ "$NEW" -eq 0 ] && info "No new wallpapers"
else
    warn "Not found, skipping: $LIVE_DIR"
fi

# ─── which one is selected ────────────────────────────────────────────────────
# configure.sh reads this rather than carrying a hardcoded filename.
SESSION="$HOME/.local/state/DankMaterialShell/session.json"
if [ -f "$SESSION" ]; then
    SELECTED=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('wallpaperPath',''))" "$SESSION" 2>/dev/null || true)
    if [ -n "$SELECTED" ] && [ -f "$SELECTED" ]; then
        name="$(basename "$SELECTED")"
        # A wallpaper picked from outside ~/Documents/Wallpapers won't have been
        # copied by the mirror above, so bring it in before recording it —
        # otherwise wallpaper/active names a file the repo doesn't have.
        if [ ! -f "$REPO_DIR/$name" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would add the selected wallpaper from outside $LIVE_DIR: $name"
            else
                cp "$SELECTED" "$REPO_DIR/$name"
                info "Captured selected wallpaper from outside $LIVE_DIR: $name"
            fi
            captured
        fi
        if [ "$(cat "$ACTIVE_FILE" 2>/dev/null)" = "$name" ]; then
            info "Active wallpaper already recorded: $name"
        elif [ "$DRY_RUN" = true ]; then
            info "Would record active wallpaper: $(cat "$ACTIVE_FILE" 2>/dev/null) → $name"
            captured
        else
            echo "$name" > "$ACTIVE_FILE"
            info "Recorded active wallpaper: $name"
            captured
        fi
    fi
else
    warn "No DMS session file — cannot tell which wallpaper is selected"
fi

capture_summary
