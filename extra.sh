#!/usr/bin/env bash
set -euo pipefail

# Optional extras — not every machine has an NVIDIA GPU, so its drivers live
# here instead of install.sh. Run this separately after install.sh if you want
# them:
#
#   bash extra.sh

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── shared helpers ───────────────────────────────────────────────────────────
if [ ! -f "$DOTFILES/lib/common.sh" ]; then
    echo "Missing $DOTFILES/lib/common.sh — run this from a full clone of the repo" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$DOTFILES/lib/common.sh"

# ─── NVIDIA — only if this machine has an NVIDIA GPU ──────────────────────────
section "NVIDIA drivers"

# Uncomment these lines if this machine has an NVIDIA GPU:
# sudo apt install -y nvidia-driver-595-open linux-modules-nvidia-595-open-generic-hwe-26.04
warn "NVIDIA driver install is commented out in extra.sh — edit the script and uncomment if needed"

# ─── Done ─────────────────────────────────────────────────────────────────────
section "Extras complete"
echo ""
info "Manual steps remaining:"
echo "  1. If this machine has NVIDIA — uncomment the NVIDIA lines in this script and re-run"
echo ""
