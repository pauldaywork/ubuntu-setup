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
