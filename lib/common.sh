# Shared helpers for install.sh, configure.sh, doctor.sh, extra.sh and the
# capture/ scripts. Sourced, never executed.
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
# copy/backup_existing used to live in configure.sh and
# pull/confirm_overwrite in update.sh — inverse operations on the same files,
# split across two scripts that shared no line between them. update.sh is gone;
# the pull half is now used by capture/, which writes machine → repo,
# with no shared line between them. They are here so the two directions can be
# read side by side, and so lib/paths.sh has somewhere to hand its rows to.

# configure.sh sets USER_HOME; doctor.sh and capture/ just use $HOME.
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

# merge_json lived here, for config files the *app* owned and rewrote as it
# gained features. DankMaterialShell's settings.json was the only real case: its
# live file grew keys and climbed a configVersion with each release, while the
# repo carried a snapshot from whenever capture/dms-settings.sh last ran, so
# copying ours flat over the top deleted every key our snapshot had never heard
# of — 147 of them on this machine, including the display profiles and the whole
# battery section. Merging kept those.
#
# It went with DMS. waybar and mako read what this repo writes and write nothing
# back, so a plain copy() is both correct and honest about who owns the file. If
# something that owns its own config shows up again, this is in the git history
# rather than gone.

# ─── pulling back (used by capture/) ──────────────────────────────────────────
# A repo file that matches HEAD is always recoverable with `git checkout`, so it
# is overwritten silently. Untracked files count as uncommitted: there's no
# committed version of those to fall back on either.
#
# SKIPPED_ANY records whether anything was left alone, so capture_summary can
# say so — a run that quietly kept the repo version is the run you most need to
# hear about.
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

