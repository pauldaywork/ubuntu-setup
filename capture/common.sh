# Shared preamble for the capture scripts.
#
# Direction matters here and it is the opposite of everything else in this repo:
# configure.sh writes repo → machine, these write machine → repo. Keep that
# split. A script that does both is how you end up unable to say which side is
# authoritative, which is what the old update.sh was.
#
# The rule for whether something belongs in capture/: the change must only be
# makeable on the machine — a GUI, a package manager, a daemon writing state.
# Anything you would change in a text editor should be edited in the repo and
# deployed with configure.sh instead. That is why there is no capture script for
# .bashrc, the window-rules or the theme: 14 of the 17 managed files are
# byte-identical to the repo precisely because nothing edits them out here.
#
# Sourced with:
#   DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$DOTFILES/capture/common.sh"

set -uo pipefail

for _lib in common paths; do
    if [ ! -f "$DOTFILES/lib/$_lib.sh" ]; then
        echo "Missing $DOTFILES/lib/$_lib.sh — run this from a full clone of the repo" >&2
        exit 1
    fi
done
# shellcheck source=/dev/null
source "$DOTFILES/lib/common.sh"
# shellcheck source=/dev/null
source "$DOTFILES/lib/paths.sh"

# ─── flags ────────────────────────────────────────────────────────────────────
# --yes overwrites uncommitted repo edits without asking; see confirm_overwrite
# in lib/common.sh for why that prompt exists at all.
ASSUME_YES=false
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes)     ASSUME_YES=true ;;
        -n|--dry-run) DRY_RUN=true ;;
    esac
done

if git -C "$DOTFILES" rev-parse --git-dir &>/dev/null; then
    IS_GIT_REPO=true
else
    IS_GIT_REPO=false
fi

# What changed, printed at the end so a run that did nothing says so plainly
# rather than leaving you to read back through the output.
CAPTURED=0

captured() { CAPTURED=$((CAPTURED + 1)); }

capture_summary() {
    echo
    if [ "$CAPTURED" -eq 0 ]; then
        info "Nothing to capture — the repo already matches this machine."
    elif [ "$DRY_RUN" = true ]; then
        info "Dry run — $CAPTURED change(s) would be captured. Re-run without --dry-run to apply."
    else
        info "$CAPTURED change(s) captured into the repo. Review with: git -C $DOTFILES diff"
    fi

    # Set by confirm_overwrite when it left an uncommitted repo file alone.
    if [ "${SKIPPED_ANY:-false}" = true ]; then
        warn "Some repo files were kept because they had uncommitted changes."
        warn "Commit or stash them and re-run, or pass --yes to overwrite."
    fi
}
