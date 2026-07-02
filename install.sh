#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$HOME"

# ─── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${GREEN}══${NC} $* ${GREEN}══${NC}"; }

# ─── 1. PPAs and external repos ───────────────────────────────────────────────
section "Adding package repositories"

add_ppa() {
    local name="$1" ppa="$2"
    if ! apt-cache policy 2>/dev/null | grep -q "$ppa"; then
        info "Adding PPA: $name"
        sudo add-apt-repository -y "ppa:$ppa"
    else
        info "Already present: $name"
    fi
}

add_ppa "danklinux (niri)" "avengemedia/danklinux"
add_ppa "dms (DankMaterialShell bar)" "avengemedia/dms"

# Sublime Text
if ! apt-cache show sublime-text &>/dev/null; then
    info "Adding Sublime Text repo"
    wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg \
        | gpg --dearmor \
        | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
    echo "deb https://download.sublimetext.com/ apt/stable/" \
        | sudo tee /etc/apt/sources.list.d/sublime-text.list
fi

# Google Chrome
if ! apt-cache show google-chrome-stable &>/dev/null; then
    info "Adding Google Chrome repo"
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor \
        | sudo tee /etc/apt/trusted.gpg.d/google-chrome.gpg > /dev/null
    echo "deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list
fi

sudo apt update

# ─── 2. apt packages ──────────────────────────────────────────────────────────
section "Installing apt packages"

APT_PACKAGES=(
    # window manager + shell
    niri
    dms

    # dev tools
    git
    curl
    build-essential
    jq
    tmux
    libudev-dev
    util-linux-extra
    zenity

    # apps (from external repos)
    taskwarrior
    sublime-text
    google-chrome-stable

    # audio / system
    pipewire
    wireplumber
    brightnessctl
    playerctl
)

sudo apt install -y "${APT_PACKAGES[@]}"

# ─── NVIDIA — only if this machine has an NVIDIA GPU ──────────────────────────
# Uncomment these lines if you need NVIDIA drivers:
# sudo apt install -y nvidia-driver-595-open linux-modules-nvidia-595-open-generic-hwe-26.04

# ─── .deb installs (no apt repo — downloaded directly) ───────────────────────
section "Installing .deb packages"

install_deb() {
    local name="$1" url="$2"
    if dpkg -s "$name" &>/dev/null 2>&1; then
        info "Already installed: $name"
        return
    fi
    info "Downloading $name..."
    local tmp
    tmp=$(mktemp /tmp/"${name}"-XXXXXX.deb)
    curl -fsSL "$url" -o "$tmp"
    sudo dpkg -i "$tmp"
    sudo apt-get install -f -y   # fix any missing dependencies
    rm -f "$tmp"
    info "Installed: $name"
}

# Obsidian — snap doesn't work; use the official GitHub release .deb
# To get the latest: https://github.com/obsidianmd/obsidian-releases/releases
OBSIDIAN_VERSION="1.12.7"
install_deb "obsidian" \
    "https://github.com/obsidianmd/obsidian-releases/releases/download/v${OBSIDIAN_VERSION}/obsidian_${OBSIDIAN_VERSION}_amd64.deb"

# LM Studio — use their official installer which always fetches the latest version
if command -v lms &>/dev/null; then
    info "LM Studio already installed ($(lms version 2>/dev/null || echo 'unknown version'))"
else
    info "Installing LM Studio (latest)"
    curl -fsSL https://lmstudio.ai/install.sh | bash
fi

# ─── 3. snap packages ─────────────────────────────────────────────────────────
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

snap_install firefox
snap_install code        --classic
snap_install ghostty     --classic
snap_install cmake       --classic
snap_install rustup      --classic
snap_install opencode    --classic
snap_install steam
snap_install termius-app
snap_install workshop    --classic

# ─── 4. Rust toolchain ────────────────────────────────────────────────────────
section "Setting up Rust toolchain"

if ! /snap/bin/rustup toolchain list 2>/dev/null | grep -q "stable"; then
    info "Installing stable Rust toolchain"
    /snap/bin/rustup install stable
    /snap/bin/rustup default stable
else
    info "Rust stable already installed ($(/snap/bin/rustc --version))"
fi

# ─── 5. NVM + Node.js ─────────────────────────────────────────────────────────
section "Installing NVM + Node.js"

NVM_DIR="$USER_HOME/.config/nvm"
NODE_VERSION="v24.18.0"

if [ ! -d "$NVM_DIR" ]; then
    info "Installing NVM (to ~/.config/nvm)"
    PROFILE=/dev/null NVM_DIR="$NVM_DIR" \
        bash <(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh)
fi

export NVM_DIR="$NVM_DIR"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

if ! nvm ls "$NODE_VERSION" &>/dev/null; then
    info "Installing Node.js $NODE_VERSION"
    nvm install "$NODE_VERSION"
fi
nvm use "$NODE_VERSION"

# ─── 6. Claude Code ───────────────────────────────────────────────────────────
section "Installing Claude Code"

if ! command -v claude &>/dev/null; then
    npm install -g @anthropic-ai/claude-code
    info "Claude Code installed — run 'claude' to log in after setup"
else
    info "Claude Code already installed ($(claude --version 2>/dev/null || echo 'unknown version'))"
fi

# ─── 7. Copy dotfiles ─────────────────────────────────────────────────────────
section "Copying dotfiles"

copy() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ]; then
        warn "Backing up existing: $dst → $dst.bak"
        cp "$dst" "$dst.bak"
    fi
    cp "$src" "$dst"
    info "Copied $dst"
}

# shell
copy "$DOTFILES/home/.bashrc"  "$USER_HOME/.bashrc"
copy "$DOTFILES/home/.profile" "$USER_HOME/.profile"

# taskwarrior
copy "$DOTFILES/home/.taskrc" "$USER_HOME/.taskrc"

# niri
copy "$DOTFILES/config/niri/config.kdl"    "$USER_HOME/.config/niri/config.kdl"
copy "$DOTFILES/config/niri/dms/binds.kdl" "$USER_HOME/.config/niri/dms/binds.kdl"

# ghostty
copy "$DOTFILES/config/ghostty/config.ghostty" "$USER_HOME/.config/ghostty/config.ghostty"

# alacritty theme (referenced by DMS)
copy "$DOTFILES/config/alacritty/dank-theme.toml" "$USER_HOME/.config/alacritty/dank-theme.toml"

# DankMaterialShell
copy "$DOTFILES/config/DankMaterialShell/settings.json"        "$USER_HOME/.config/DankMaterialShell/settings.json"
copy "$DOTFILES/config/DankMaterialShell/plugin_settings.json" "$USER_HOME/.config/DankMaterialShell/plugin_settings.json"
copy "$DOTFILES/config/DankMaterialShell/firefox.css"          "$USER_HOME/.config/DankMaterialShell/firefox.css"
copy "$DOTFILES/config/DankMaterialShell/themes/peaceAndQuiet/theme.json" \
     "$USER_HOME/.config/DankMaterialShell/themes/peaceAndQuiet/theme.json"

# VS Code
copy "$DOTFILES/config/Code/settings.json" "$USER_HOME/.config/Code/User/settings.json"
if [ -s "$DOTFILES/config/Code/extensions.txt" ]; then
    info "Installing VS Code extensions"
    while IFS= read -r ext; do
        code --install-extension "$ext" --force
    done < "$DOTFILES/config/Code/extensions.txt"
fi

# ─── 8. Wallpaper ─────────────────────────────────────────────────────────────
section "Setting up wallpaper"

WALLPAPER_DST="$USER_HOME/Documents/Wallpapers/205.png"
mkdir -p "$USER_HOME/Documents/Wallpapers"

if [ ! -f "$WALLPAPER_DST" ]; then
    cp "$DOTFILES/wallpapers/205.png" "$WALLPAPER_DST"
    info "Wallpaper copied to $WALLPAPER_DST"
fi

# Write the DMS session wallpaper path so it loads on first launch
DMS_SESSION="$USER_HOME/.local/state/DankMaterialShell/session.json"
mkdir -p "$(dirname "$DMS_SESSION")"

if [ ! -f "$DMS_SESSION" ]; then
    info "Creating DMS session with wallpaper path"
    python3 - <<PYEOF
import json, os
session = {"wallpaperPath": "$WALLPAPER_DST"}
with open("$DMS_SESSION", "w") as f:
    json.dump(session, f, indent=2)
PYEOF
else
    info "Updating wallpaper path in existing DMS session"
    python3 - <<PYEOF
import json
with open("$DMS_SESSION") as f:
    session = json.load(f)
session["wallpaperPath"] = "$WALLPAPER_DST"
with open("$DMS_SESSION", "w") as f:
    json.dump(session, f, indent=2)
PYEOF
fi

# ─── 9. Git config ────────────────────────────────────────────────────────────
section "Git configuration"

if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    read -rp "Git name: " git_name
    git config --global user.name "$git_name"
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    read -rp "Git email: " git_email
    git config --global user.email "$git_email"
fi
git config --global init.defaultBranch main

# ─── 10. SSH key ──────────────────────────────────────────────────────────────
section "SSH key"

SSH_KEY="$USER_HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    read -rp "Email for SSH key (Enter to skip): " ssh_email
    if [ -n "$ssh_email" ]; then
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
        ssh-keygen -t ed25519 -C "$ssh_email" -f "$SSH_KEY" -N ""
        info "SSH key generated. Add this public key to GitHub:"
        echo
        cat "${SSH_KEY}.pub"
        echo
        warn "→ https://github.com/settings/ssh/new"
    fi
else
    info "SSH key already exists. Public key:"
    cat "${SSH_KEY}.pub"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
section "Setup complete"
echo ""
info "Manual steps remaining:"
echo "  1. Reboot (or log out and back in) to start niri + DMS"
echo "  2. Run 'claude' to log into Claude Code"
echo "  3. Log into Firefox, Chrome, Obsidian, Steam, Termius as needed"
echo "  4. Open LM Studio and re-download any models you need"
echo "  5. If this machine has NVIDIA — uncomment the NVIDIA lines in this script and re-run"
echo ""
warn "DMS auto-generates its niri config files (colors.kdl, layout.kdl, outputs.kdl) on first launch"
warn "Monitor layout (outputs.kdl) will be detected automatically for the new hardware"
