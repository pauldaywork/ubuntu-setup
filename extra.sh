#!/usr/bin/env bash
set -euo pipefail

# Optional extras — not everyone wants Steam, OpenCode, LM Studio, or NVIDIA
# drivers on every machine, so these live here instead of install.sh.
# Run this separately after install.sh if you want them:
#
#   bash extra.sh

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${GREEN}══${NC} $* ${GREEN}══${NC}"; }

# ─── NVIDIA — only if this machine has an NVIDIA GPU ──────────────────────────
section "NVIDIA drivers"

# Uncomment these lines if this machine has an NVIDIA GPU:
# sudo apt install -y nvidia-driver-595-open linux-modules-nvidia-595-open-generic-hwe-26.04
warn "NVIDIA driver install is commented out in extra.sh — edit the script and uncomment if needed"

# ─── LM Studio ─────────────────────────────────────────────────────────────────
section "Installing LM Studio"

# LM Studio — use their official installer which always fetches the latest version
if command -v lms &>/dev/null; then
    info "LM Studio already installed ($(lms version 2>/dev/null || echo 'unknown version'))"
else
    info "Installing LM Studio (latest)"
    curl -fsSL https://lmstudio.ai/install.sh | bash
fi

# ─── snap packages ─────────────────────────────────────────────────────────────
section "Installing snap packages"

snap_install() {
    local pkg="$1"; shift
    if snap list "$pkg" &>/dev/null 2>&1; then
        info "Snap already installed: $pkg"
    else
        info "Installing snap: $pkg"
        sudo snap install "$pkg" "$@"
    fi
}

snap_install opencode --classic
snap_install steam

# ─── Done ─────────────────────────────────────────────────────────────────────
section "Extras complete"
echo ""
info "Manual steps remaining:"
echo "  1. Log into Steam"
echo "  2. Open LM Studio and re-download any models you need"
echo "  3. If this machine has NVIDIA — uncomment the NVIDIA lines in this script and re-run"
echo ""
