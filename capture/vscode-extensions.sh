#!/usr/bin/env bash
# Capture the installed VS Code extension list into config/Code/extensions.txt.
#
#   bash capture/vscode-extensions.sh [--dry-run]
#
# install.sh reads that file on a new machine. Nothing else keeps it current, so
# without this it goes stale silently — you install an extension, and a rebuild
# a year later quietly doesn't have it.

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES/capture/common.sh"

section "Capturing VS Code extensions"

DST="$DOTFILES/config/Code/extensions.txt"

if ! command -v code &>/dev/null; then
    warn "code not on PATH — keeping the existing list"
    capture_summary
    exit 0
fi

# Built in a temp file first. Redirecting straight into the repo truncates the
# list before `code` has run, so on a tty session or an ssh login the list was
# emptied and then the failure killed the script, committing the loss. An empty
# result is treated the same way: far more likely a broken `code` than a genuine
# "no extensions installed".
TMP=$(mktemp)
if ! code --list-extensions > "$TMP" 2>/dev/null || [ ! -s "$TMP" ]; then
    warn "code --list-extensions returned nothing — keeping the existing list"
    rm -f "$TMP"
    capture_summary
    exit 0
fi

sort -o "$TMP" "$TMP"

if cmp -s "$TMP" "$DST"; then
    info "Extension list already matches ($(wc -l < "$DST") extension(s))"
else
    added=$(comm -23 "$TMP" <(sort "$DST" 2>/dev/null) | wc -l)
    removed=$(comm -13 "$TMP" <(sort "$DST" 2>/dev/null) | wc -l)
    if [ "$DRY_RUN" = true ]; then
        info "Would update extensions.txt: +$added, -$removed"
        comm -23 "$TMP" <(sort "$DST" 2>/dev/null) | sed 's/^/    + /'
        comm -13 "$TMP" <(sort "$DST" 2>/dev/null) | sed 's/^/    - /'
    elif confirm_overwrite "$TMP" "$DST"; then
        # cat rather than mv: keeps the repo file's permissions, and stays
        # correct when /tmp is a different filesystem.
        cat "$TMP" > "$DST"
        info "Captured extensions.txt: +$added, -$removed ($(wc -l < "$DST") total)"
    fi
    captured
fi
rm -f "$TMP"

capture_summary
