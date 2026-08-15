# Shared helpers for install.sh, install-config.sh, update.sh, doctor.sh and
# extra.sh. Sourced, never executed.
#
# These were five near-identical copies before, which is fine until one of them
# drifts and the scripts start disagreeing about what a warning looks like — or
# worse, about what "installed" means. pkg_installed in particular has a subtlety
# that is easy to lose in a copy (see below).
#
# Sourced with:
#   DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$DOTFILES/lib/common.sh"

# ─── output ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Installers speak in info/warn; doctor.sh reports in ok/issue/note. section() is
# common to both.
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${GREEN}══${NC} $* ${GREEN}══${NC}"; }

# issue() counts as it reports, so doctor.sh's summary is just this total.
ISSUES=0
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
issue() { ISSUES=$((ISSUES + 1)); echo -e "${RED}[✗]${NC} $*"; }
note()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ─── packages ─────────────────────────────────────────────────────────────────
# `dpkg -s` exits 0 for packages in the 'rc' state — removed, but with their
# config files left behind — which would report a package that isn't installed
# as present. Match on the status field instead. ulauncher sat in exactly that
# state on this machine for three months.
pkg_installed() {
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
}

snap_install() {
    local pkg="$1"; shift
    if snap list "$pkg" &>/dev/null 2>&1; then
        info "Snap already installed: $pkg"
    else
        info "Installing snap: $pkg"
        sudo snap install "$pkg" "$@"
    fi
}

# Installs one entry written in the manifest's "name" or "name:classic" form, so
# install.sh and doctor.sh can read the same list.
snap_install_entry() {
    local entry="$1" pkg="${1%%:*}"
    if [[ "$entry" == *:classic ]]; then
        snap_install "$pkg" --classic
    else
        snap_install "$pkg"
    fi
}

# ─── moving config files about ────────────────────────────────────────────────
# copy/backup_existing/merge_json used to live in install-config.sh and
# pull/confirm_overwrite in update.sh — inverse operations on the same files,
# with no shared line between them. They are here so the two directions can be
# read side by side, and so lib/paths.sh has somewhere to hand its rows to.

# install-config.sh sets USER_HOME; update.sh and doctor.sh just use $HOME.
: "${USER_HOME:=$HOME}"

# Existing files that would be overwritten are moved into a timestamped tree
# mirroring their path relative to $HOME, rather than left as .bak siblings, so
# a bad install can't be confused with a stray .bak and the live tree stays clean.
: "${BACKUP_DIR:=$USER_HOME/.config-backups/$(date +%Y%m%d-%H%M%S)}"
BACKED_UP_ANYTHING=${BACKED_UP_ANYTHING:-false}

backup_existing() {
    local dst="$1"
    [ -e "$dst" ] || return 0
    local rel="${dst#"$USER_HOME"/}"
    local backup_dst="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$backup_dst")"
    cp -a "$dst" "$backup_dst"
    warn "Backed up existing: $dst → $backup_dst"
    BACKED_UP_ANYTHING=true
}

copy() {
    local src="$1" dst="$2"
    # A file that already matches needs neither writing nor backing up. Without
    # this, re-running the installer on an in-sync machine still archived a
    # complete copy of every config it touched — which is how ~/.config-backups
    # grew to nine directories of near-identical files.
    if cmp -s "$src" "$dst"; then
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    backup_existing "$dst"
    cp "$src" "$dst"
    info "Copied $dst"
}

# For config files the *app* owns and rewrites as it gains features — DMS's
# settings.json above all. Its live file grows keys and climbs a configVersion
# with each release, while the copy in this repo is a snapshot from whenever
# update.sh last ran. Copying ours flat over the top deletes every key our
# snapshot has never heard of: on this machine that was 147 of them, including
# the display profiles and the whole battery section.
#
# So merge rather than replace. Our value wins for every key we actually carry
# (that's the point of installing), and anything only the live file has is left
# where it is.
#
# configVersion is deliberately *not* max()'d — it comes from our file, i.e. the
# older number. That makes DMS re-run its migrations over the merged result on
# next load, which is what forward-migrates the stale-shaped values our snapshot
# contributed (ours still carries the pre-v13 `*Pins` keys, which migration 13
# moves out to cache.json). Re-running those migrations over already-current
# keys is safe: each one is either guarded on a key that no longer exists or a
# plain delete.
#
# Only top-level keys are merged. Nested structures like barConfigs are replaced
# wholesale, which is right — the bar layout is exactly the thing being
# installed — and DMS defaults any per-bar key our snapshot predates.
merge_json() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"

    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        info "Copied $dst (no existing file to merge with)"
        return
    fi

    # Merged into a temp file first, so a merge that changes nothing — the usual
    # case on a machine already in sync — neither rewrites the live file nor
    # leaves a backup copy of it behind.
    #
    # stderr is dropped so a malformed live file reports as the warning below
    # rather than as a python traceback in the middle of the install output.
    local merged_tmp merge_summary
    merged_tmp=$(mktemp)

    if merge_summary=$(python3 - "$src" "$dst" "$merged_tmp" 2>/dev/null <<'PYEOF'
import json, sys

src, dst, out = sys.argv[1], sys.argv[2], sys.argv[3]

with open(src) as f:
    ours = json.load(f)
with open(dst) as f:
    live = json.load(f)

merged = dict(live)
merged.update(ours)

with open(out, "w") as f:
    json.dump(merged, f, indent=2)

kept = len(set(live) - set(ours))
print(f"{len(ours)} key(s) applied, {kept} live-only key(s) preserved")
PYEOF
    ); then
        if cmp -s "$merged_tmp" "$dst"; then
            info "Unchanged $dst — $merge_summary"
        else
            backup_existing "$dst"
            cat "$merged_tmp" > "$dst"
            info "Merged $dst — $merge_summary"
        fi
    else
        # A live file that isn't valid JSON can't be merged into. Backing it up
        # first makes replacing it recoverable, which beats leaving the machine
        # with settings that were never installed.
        warn "Could not merge $dst (unreadable JSON?) — replacing it instead"
        backup_existing "$dst"
        cp "$src" "$dst"
    fi

    rm -f "$merged_tmp"
}

# ─── pulling back (update.sh) ─────────────────────────────────────────────────
# A repo file that matches HEAD is always recoverable with `git checkout`, so it
# gets pulled silently. Untracked files count as uncommitted: there's no
# committed version of those to fall back on either.
SKIPPED_ANY=${SKIPPED_ANY:-false}
ASSUME_YES=${ASSUME_YES:-false}

repo_file_is_uncommitted() {
    local dst="$1"
    [ "${IS_GIT_REPO:-false}" = true ] || return 1
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

# Same, but silent when the live file was never there — for entries that only
# exist on some machines (see the `laptop` kind in lib/paths.sh).
pull_optional() {
    local src="$1" dst="$2"
    [ -f "$src" ] || return 0
    pull "$src" "$dst"
}
