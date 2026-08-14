#!/usr/bin/env bash
set -euo pipefail

# Optional extras — not everyone wants Steam, OpenCode, LM Studio, or NVIDIA
# drivers on every machine, so these live here instead of install.sh.
# Run this separately after install.sh if you want them:
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

# snap_install comes from lib/common.sh. These two stay listed here rather than
# in the manifest: they're the optional extras this script exists for, and
# doctor.sh deliberately doesn't check them.
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
