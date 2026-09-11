#!/usr/bin/env bash
# Capture the live niri config back into the repo.
#
#   bash capture/niri.sh [--dry-run] [--yes]
#
# You would normally edit config/niri/config.kdl in the repo and deploy it. This
# exists for the times the machine is ahead anyway: DMS's KeybindsService writes
# binds into the live file from its settings UI, and it is natural to try a
# layout change against the running compositor before committing to it.

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES/capture/common.sh"

section "Capturing niri config"

LIVE="$HOME/.config/niri/config.kdl"
REPO="$DOTFILES/config/niri/config.kdl"

if [ ! -f "$LIVE" ]; then
    warn "Not found, skipping: $LIVE"
    capture_summary
    exit 0
fi

# configure.sh appends '\ninclude "laptop.kdl"\n' on laptops. That line is
# machine-specific, so undoing it means dropping the include *and* the one blank
# line that leading newline created. Stripping every trailing blank instead
# would eat the two this file legitimately ends with, and commit that churn on
# every run from a laptop.
TMP=$(mktemp)
grep -v '^include "laptop.kdl"$' "$LIVE" \
  | awk '{lines[NR]=$0} END {last=NR; if (last>0 && lines[last]=="") last--; for(i=1;i<=last;i++) print lines[i]}' \
  > "$TMP" || true

if cmp -s "$TMP" "$REPO"; then
    info "config.kdl already matches the repo"
elif [ "$DRY_RUN" = true ]; then
    info "Would update config/niri/config.kdl:"
    diff -u --label "repo" --label "live (laptop include stripped)" "$REPO" "$TMP" \
      | head -40 | sed 's/^/    /'
    captured
elif confirm_overwrite "$TMP" "$REPO"; then
    cp "$TMP" "$REPO"
    info "Captured config/niri/config.kdl"
    captured
fi
rm -f "$TMP"

capture_summary
