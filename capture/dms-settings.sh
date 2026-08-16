#!/usr/bin/env bash
# Capture DankMaterialShell's GUI settings into the repo.
#
#   bash capture/dms-settings.sh [--dry-run] [--yes]
#
# The bar layout, widget configuration and picker preferences are all set
# through the DMS UI and exist nowhere else, so this is the only route they have
# into the repo.
#
# Two keys are deliberately NOT captured:
#
#   configVersion    configure.sh merges these files with *our* value winning,
#                    and it wants the older number: that makes DMS re-run its
#                    migrations over the merged result on next load, which is
#                    what forward-migrates the stale-shaped values our snapshot
#                    contributes. Capturing the live (newer) number would stop
#                    those migrations running and strand them.
#
#   displayProfiles  monitor layout, which is per-machine. A laptop's profile
#                    installed onto a desktop is worse than no profile at all.
#                    Pass --with-display-profiles if you actually want it.

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES/capture/common.sh"

WITH_PROFILES=false
for arg in "$@"; do
    [ "$arg" = "--with-display-profiles" ] && WITH_PROFILES=true
done

section "Capturing DankMaterialShell settings"

capture_json() {
    local live="$1" repo="$2" label="$3"

    if [ ! -f "$live" ]; then
        warn "Not found, skipping: $live"
        return
    fi

    local tmp; tmp=$(mktemp)
    # Keep the repo's value for the excluded keys rather than dropping them, so
    # the file stays a complete, installable snapshot.
    if ! python3 - "$live" "$repo" "$tmp" "$WITH_PROFILES" <<'PYEOF' 2>/dev/null
import json, sys

live_p, repo_p, out_p, with_profiles = sys.argv[1:5]

with open(live_p) as f:
    live = json.load(f)
try:
    with open(repo_p) as f:
        repo = json.load(f)
except (OSError, ValueError):
    repo = {}

captured = dict(live)

# configVersion: keep whatever the repo already had (see the header).
if "configVersion" in repo:
    captured["configVersion"] = repo["configVersion"]
elif "configVersion" in captured:
    del captured["configVersion"]

if with_profiles != "true":
    if "displayProfiles" in repo:
        captured["displayProfiles"] = repo["displayProfiles"]
    else:
        captured.pop("displayProfiles", None)

with open(out_p, "w") as f:
    json.dump(captured, f, indent=2)
    f.write("\n")
PYEOF
    then
        warn "Could not read $live as JSON — skipping"
        rm -f "$tmp"
        return
    fi

    if cmp -s "$tmp" "$repo"; then
        info "$label already matches the repo"
        rm -f "$tmp"
        return
    fi

    # Report removals as loudly as additions. Taking a live snapshot drops any
    # key the repo has that DMS no longer writes — usually obsolete ones it has
    # migrated away from, but a capture tool that deletes without saying so is
    # not one you can trust.
    local summary removed_list
    summary=$(python3 - "$tmp" "$repo" <<'PY' 2>/dev/null || echo "? new, ? changed, ? removed"
import json, sys
new = json.load(open(sys.argv[1]))
try:
    old = json.load(open(sys.argv[2]))
except Exception:
    old = {}
added = set(new) - set(old)
removed = set(old) - set(new)
changed = [k for k in set(new) & set(old) if new[k] != old[k]]
print(f"{len(added)} new, {len(changed)} changed, {len(removed)} removed")
PY
)
    removed_list=$(python3 - "$tmp" "$repo" <<'PY' 2>/dev/null || true
import json, sys
new = json.load(open(sys.argv[1]))
try:
    old = json.load(open(sys.argv[2]))
except Exception:
    old = {}
for k in sorted(set(old) - set(new)):
    print(f"    - {k}")
PY
)

    if [ "$DRY_RUN" = true ]; then
        info "Would update $label: $summary"
        [ -n "$removed_list" ] && { warn "  keys that would be dropped:"; echo "$removed_list"; }
    elif confirm_overwrite "$tmp" "$repo"; then
        [ -n "$removed_list" ] && { warn "  dropping keys DMS no longer writes:"; echo "$removed_list"; }
        cat "$tmp" > "$repo"
        info "Captured $label: $summary"
    fi
    captured
    rm -f "$tmp"
}

capture_json "$HOME/.config/DankMaterialShell/settings.json" \
             "$DOTFILES/config/DankMaterialShell/settings.json" \
             "settings.json"

capture_json "$HOME/.config/DankMaterialShell/plugin_settings.json" \
             "$DOTFILES/config/DankMaterialShell/plugin_settings.json" \
             "plugin_settings.json"

# The theme is a file you edit, not a GUI product, so it is deployed rather than
# captured — see capture/common.sh for where that line is drawn.

capture_summary
