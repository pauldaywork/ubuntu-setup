#!/usr/bin/env bash
# Diagnose drift between what this machine actually has installed and what
# ~/.bashrc, ~/.profile, and install.sh assume (e.g. a tool that got moved
# or reinstalled by hand without its shell config being updated to match).
#
# Read-only by default — it only reports. Pass --fix to interactively repair
# dangling PATH/env references in dotfiles (each fix is confirmed and the
# file is backed up first). It never installs, uninstalls, or moves software
# on its own — those calls need a human, so those checks only print a
# suggested command.
#
# Usage:
#   bash doctor.sh          # report only
#   bash doctor.sh --fix    # report, and offer to repair dotfile references

set -uo pipefail

FIX=false
[ "${1:-}" = "--fix" ] && FIX=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ISSUES=0
ok()      { echo -e "${GREEN}[✓]${NC} $*"; }
issue()   { ISSUES=$((ISSUES + 1)); echo -e "${RED}[✗]${NC} $*"; }
note()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${GREEN}══${NC} $* ${GREEN}══${NC}"; }

RC_FILES=("$HOME/.bashrc" "$HOME/.profile")

# Prompts before editing a dotfile; only runs when --fix was passed.
confirm_fix() {
    $FIX || return 1
    read -rp "    Apply this fix? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

backup() {
    cp "$1" "$1.doctor-bak-$(date +%Y%m%d%H%M%S)"
}

# ─── 1. Installation completeness ─────────────────────────────────────────────
# Report-only, same as everything else here — installing software isn't a
# dotfile fix, so even --fix just prints the command install.sh would run.
# Keep this list in sync with install.sh if that ever changes.
section "Checking installation completeness"

APT_PACKAGES=(
    niri dms
    git curl build-essential jq tmux libudev-dev util-linux-extra zenity
    taskwarrior sublime-text google-chrome-stable
    pipewire wireplumber brightnessctl playerctl
)

MISSING_APT=()
for pkg in "${APT_PACKAGES[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING_APT+=("$pkg")
done
if [ "${#MISSING_APT[@]}" -eq 0 ]; then
    ok "All apt packages installed"
else
    issue "Missing apt package(s): ${MISSING_APT[*]}"
    note "  Install with: sudo apt install -y ${MISSING_APT[*]}"
fi

if dpkg -s obsidian &>/dev/null; then
    ok "obsidian installed"
else
    issue "obsidian not installed"
    note "  See the OBSIDIAN_VERSION .deb URL in install.sh"
fi

if dpkg -s mako-notifier &>/dev/null; then
    issue "mako-notifier is installed but no longer used (superseded by DMS notifications)"
    note "  Remove with: sudo apt remove -y mako-notifier"
else
    ok "mako-notifier not installed (as expected)"
fi

SNAP_PACKAGES=(firefox code:classic ghostty:classic cmake:classic)
for entry in "${SNAP_PACKAGES[@]}"; do
    pkg="${entry%%:*}"
    flag=""; [[ "$entry" == *:classic ]] && flag=" --classic"
    if snap list "$pkg" &>/dev/null; then
        ok "snap: $pkg installed"
    else
        issue "snap: $pkg not installed"
        note "  Install with: sudo snap install $pkg$flag"
    fi
done

if command -v rustup &>/dev/null; then
    ok "rustup installed ($(rustc --version 2>/dev/null))"
else
    issue "rustup not installed"
    note "  Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
fi

if command -v bun &>/dev/null || [ -x "$HOME/.bun/bin/bun" ]; then
    ok "bun installed"
else
    issue "bun not installed"
    note "  Install with: curl -fsSL https://bun.sh/install | bash"
fi

NVM_INSTALL_DIR="$HOME/.config/nvm"
NODE_VERSION="v24.18.0"
if [ -s "$NVM_INSTALL_DIR/nvm.sh" ]; then
    ok "nvm installed"
    if [ -d "$NVM_INSTALL_DIR/versions/node/$NODE_VERSION" ]; then
        ok "Node.js $NODE_VERSION installed"
    else
        issue "Node.js $NODE_VERSION not installed via nvm"
        note "  Install with: NVM_DIR=$NVM_INSTALL_DIR bash -c 'source $NVM_INSTALL_DIR/nvm.sh && nvm install $NODE_VERSION'"
    fi
else
    issue "nvm not installed at $NVM_INSTALL_DIR"
    note "  Re-run install.sh (see its NVM + Node.js section)"
fi

if command -v claude &>/dev/null; then
    ok "Claude Code installed"
else
    issue "Claude Code not installed"
    note "  Install with: npm install -g @anthropic-ai/claude-code"
fi

if [ -d "$HOME/.tmux/plugins/tpm" ]; then
    ok "TPM (tmux plugin manager) installed"
else
    issue "TPM not installed at ~/.tmux/plugins/tpm"
    note "  Install with: git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm && ~/.tmux/plugins/tpm/bin/install_plugins"
fi

if [ -d "$HOME/.config/DankMaterialShell/plugins/taskwarrior" ]; then
    ok "DMS taskwarrior plugin installed"
else
    issue "DMS taskwarrior plugin not installed at ~/.config/DankMaterialShell/plugins/taskwarrior"
    note "  Install with: git clone https://github.com/cyrylas/dms-taskwarrior ~/.config/DankMaterialShell/plugins/taskwarrior"
fi

# ─── 2. Dangling PATH / env references in dotfiles ───────────────────────────
# Finds lines like `export FOO_DIR="$HOME/x"` or `. "$HOME/x/env"` and checks
# the path they point at still exists. Catches the general case of "a tool
# got moved/reinstalled and the shell config was never updated" without
# needing to know about every tool in advance.
section "Checking for dangling PATH/env references"

for rc in "${RC_FILES[@]}"; do
    [ -f "$rc" ] || continue
    while IFS= read -r line; do
        raw_path=$(echo "$line" | grep -oE '(\$HOME|~|/home/[A-Za-z0-9._-]+)(/[A-Za-z0-9._-]+)+' | head -1)
        [ -z "$raw_path" ] && continue
        expanded="${raw_path/#\~/$HOME}"
        expanded="${expanded/#\$HOME/$HOME}"
        [ -e "$expanded" ] && continue
        issue "$rc references '$expanded' but it doesn't exist:"
        echo "      $line"
    done < <(grep -E '^\s*(export [A-Z_]+=|\. |source )' "$rc")
done
[ "$ISSUES" -eq 0 ] && ok "No dangling references found"

# ─── 3. nvm location vs what's actually configured ───────────────────────────
section "Checking nvm"

configured_nvm_dir=""
for rc in "${RC_FILES[@]}"; do
    [ -f "$rc" ] || continue
    match=$(grep -oP '(?<=export NVM_DIR=")[^"]+' "$rc" 2>/dev/null | head -1)
    [ -n "$match" ] && configured_nvm_dir="${match/#\$HOME/$HOME}" && break
done

if [ -z "$configured_nvm_dir" ]; then
    note "No NVM_DIR export found — skipping"
elif [ -f "$configured_nvm_dir/nvm.sh" ]; then
    ok "NVM_DIR ($configured_nvm_dir) is valid"
else
    issue "NVM_DIR is set to $configured_nvm_dir, but nvm isn't installed there"
    real_dir=""
    for candidate in "$HOME/.nvm" "$HOME/.config/nvm"; do
        [ -f "$candidate/nvm.sh" ] && real_dir="$candidate" && break
    done
    if [ -n "$real_dir" ]; then
        note "  Found a real nvm install at $real_dir instead"
        if confirm_fix; then
            for rc in "${RC_FILES[@]}"; do
                grep -q 'NVM_DIR=' "$rc" 2>/dev/null || continue
                backup "$rc"
                sed -i "s#export NVM_DIR=\"[^\"]*\"#export NVM_DIR=\"$real_dir\"#" "$rc"
                ok "  Updated NVM_DIR in $rc (backup saved)"
            done
        fi
    else
        note "  Couldn't find nvm anywhere under ~/.nvm or ~/.config/nvm — may need reinstalling"
    fi
fi

# ─── 4. Duplicate installs (same tool via two different channels) ────────────
# These are reported only — removing an installed toolchain or app
# automatically is too risky to do without a human confirming which copy
# is actually in use.
section "Checking for duplicate installs"

check_duplicate() {
    local name="$1" snap_name="$2" other_check="$3"
    local has_snap=false has_other=false
    snap list "$snap_name" &>/dev/null && has_snap=true
    eval "$other_check" &>/dev/null && has_other=true
    if $has_snap && $has_other; then
        issue "$name is installed both via snap and another way — likely redundant"
        note "  To drop the snap copy (keeping the other): sudo snap remove $snap_name"
    else
        ok "$name has no duplicate install"
    fi
}

check_duplicate "rustup/cargo" "rustup" '[ -x "$HOME/.cargo/bin/rustup" ]'
check_duplicate "ghostty"      "ghostty" 'dpkg -s ghostty'

# ─── 5. Summary ───────────────────────────────────────────────────────────────
section "Summary"
if [ "$ISSUES" -eq 0 ]; then
    ok "No issues found"
else
    note "$ISSUES issue(s) found."
    $FIX || note "Re-run with --fix to interactively repair dangling PATH/env references."
fi
