#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$HOME"

# ─── flags ─────────────────────────────────────────────────────────────────────
LAPTOP=false
for arg in "$@"; do
    case "$arg" in
        --laptop) LAPTOP=true ;;
    esac
done

# ─── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${GREEN}══${NC} $* ${GREEN}══${NC}"; }

# `dpkg -s` exits 0 for packages in the 'rc' state (removed, config files left
# behind), which would treat an already-removed package as still installed.
# Match on the status field instead.
pkg_installed() {
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
}

# ─── 0. Remove mako ───────────────────────────────────────────────────────────
# DMS now owns notifications, so a leftover mako install fights it for the
# notification socket. Strip it before anything else runs.
section "Checking for mako"

if pkg_installed mako-notifier; then
    info "Removing mako-notifier (superseded by DMS notifications)"
    sudo apt remove -y mako-notifier
else
    info "mako-notifier not installed"
fi

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

sudo mkdir -p /etc/apt/keyrings

# Sublime Text
if ! apt-cache show sublime-text &>/dev/null; then
    info "Adding Sublime Text repo"
    wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg \
        | gpg --dearmor \
        | sudo tee /etc/apt/keyrings/sublimehq-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/sublimehq-archive-keyring.gpg] https://download.sublimetext.com/ apt/stable/" \
        | sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null
fi

# Google Chrome
if ! apt-cache show google-chrome-stable &>/dev/null; then
    info "Adding Google Chrome repo"
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor \
        | sudo tee /etc/apt/keyrings/google-chrome-keyring.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
fi

sudo apt update

# ─── 2. apt packages ──────────────────────────────────────────────────────────
section "Installing apt packages"

APT_PACKAGES=(
    # window manager + shell — all from the danklinux PPA added above.
    # ghostty comes from there too, which is why it isn't a snap: the repo is
    # already configured, and the deb avoids classic-snap confinement.
    niri
    dms
    ghostty

    # dmenu-style picker used by open_project_workspace.sh (Mod+Alt+P).
    # Usually pulled in as a niri dependency, but named here so it can't
    # silently disappear from under the shortcut.
    fuzzel

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

    # docker — Ubuntu's own packages, not the docker-ce repo. Keeps everything
    # on one repo at the cost of tracking the release's version rather than
    # upstream's. docker-ce conflicts with these; don't mix them.
    docker.io
    docker-compose-v2
    docker-buildx

    # audio / system
    pipewire
    wireplumber
    brightnessctl
    playerctl
)

sudo apt install -y "${APT_PACKAGES[@]}"

# ─── Docker permissions ───────────────────────────────────────────────────────
# /var/run/docker.sock is root:docker, so without group membership every docker
# command needs sudo. Group changes only apply to new login sessions — this has
# no effect on the shell running install.sh.
section "Configuring Docker permissions"

sudo systemctl enable --now docker

CURRENT_USER="$(id -un)"
if id -nG "$CURRENT_USER" | grep -qw docker; then
    info "$CURRENT_USER already in the docker group"
else
    info "Adding $CURRENT_USER to the docker group"
    sudo usermod -aG docker "$CURRENT_USER"
    warn "Log out and back in before docker works without sudo"
fi

# ─── .deb installs (no apt repo — downloaded directly) ───────────────────────
section "Installing .deb packages"

install_deb() {
    local name="$1" url="$2"
    if pkg_installed "$name"; then
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
snap_install cmake       --classic

# ─── 4. Rust toolchain ────────────────────────────────────────────────────────
# Installed via the official rustup.rs script rather than the rustup snap —
# the snap's confinement causes friction with `cargo install` and linking
# against system libraries.
section "Setting up Rust toolchain"

if ! command -v rustup &>/dev/null; then
    info "Installing rustup"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable
fi

# shellcheck source=/dev/null
[ -f "$USER_HOME/.cargo/env" ] && source "$USER_HOME/.cargo/env"

if ! rustup toolchain list 2>/dev/null | grep -q "stable"; then
    info "Installing stable Rust toolchain"
    rustup install stable
    rustup default stable
else
    info "Rust stable already installed ($(rustc --version))"
fi

# ─── 5. Bun ────────────────────────────────────────────────────────────────────
section "Installing Bun"

if ! command -v bun &>/dev/null; then
    info "Installing Bun"
    curl -fsSL https://bun.sh/install | bash
else
    info "Bun already installed ($(bun --version))"
fi

# ─── 6. NVM + Node.js ─────────────────────────────────────────────────────────
section "Installing NVM + Node.js"

NVM_DIR="$USER_HOME/.config/nvm"
NODE_VERSION="v24.18.0"

mkdir -p "$NVM_DIR"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then
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

# ─── 7. Claude Code ───────────────────────────────────────────────────────────
section "Installing Claude Code"

if ! command -v claude &>/dev/null; then
    npm install -g @anthropic-ai/claude-code
    info "Claude Code installed — run 'claude' to log in after setup"
else
    info "Claude Code already installed ($(claude --version 2>/dev/null || echo 'unknown version'))"
fi

# ─── 8. Copy config files + wallpaper ─────────────────────────────────────────
CONFIG_ARGS=()
[ "$LAPTOP" = true ] && CONFIG_ARGS+=(--laptop)
"$DOTFILES/install-config.sh" "${CONFIG_ARGS[@]}"

# ─── 9. TPM (tmux plugin manager) ─────────────────────────────────────────────
# .tmux.conf declares plugins via `set -g @plugin ...`, which TPM is what
# actually fetches and loads. Runs after config copy so .tmux.conf is in
# place for install_plugins to read.
section "Installing TPM (tmux plugin manager)"

TPM_DIR="$USER_HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

# install_plugins relies on `tmux start-server` to pick up .tmux.conf, but
# that's a no-op if a tmux server is already running from before this config
# was in place (e.g. re-running install.sh). Reload it explicitly so
# TMUX_PLUGIN_MANAGER_PATH is always set before install_plugins looks for it.
tmux source-file "$USER_HOME/.tmux.conf" 2>/dev/null || true
"$TPM_DIR/bin/install_plugins"
# install_plugins only clones plugins — it doesn't source their *.tmux files
# into a running session (that's what TPM's own prefix+I binding does via a
# second reload). Without this, a freshly cloned plugin's key bindings never
# actually take effect until something else reloads the config.
tmux source-file "$USER_HOME/.tmux.conf" 2>/dev/null || true

# ─── 10. DMS plugins ───────────────────────────────────────────────────────────
section "Installing DMS plugins"

DMS_PLUGIN_DIR="$USER_HOME/.config/DankMaterialShell/plugins"
mkdir -p "$DMS_PLUGIN_DIR"

install_dms_plugin() {
    local name="$1" repo="$2"
    if [ -d "$DMS_PLUGIN_DIR/$name" ]; then
        info "DMS plugin already installed: $name"
    else
        info "Installing DMS plugin: $name"
        git clone "$repo" "$DMS_PLUGIN_DIR/$name"
    fi
}

install_dms_plugin "taskwarrior" "https://github.com/cyrylas/dms-taskwarrior"

# ─── 11. VS Code extensions ───────────────────────────────────────────────────
section "Installing VS Code extensions"

if [ -s "$DOTFILES/config/Code/extensions.txt" ]; then
    while IFS= read -r ext; do
        code --install-extension "$ext" --force
    done < "$DOTFILES/config/Code/extensions.txt"
fi

# ─── 12. Git config ───────────────────────────────────────────────────────────
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

# ─── 13. SSH key ──────────────────────────────────────────────────────────────
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
echo "  3. Log into Firefox, Chrome, Obsidian as needed"
echo "  4. Run 'bash extra.sh' if you want Steam, OpenCode, LM Studio, or NVIDIA drivers"
echo ""
warn "DMS auto-generates its niri config files (colors.kdl, layout.kdl, outputs.kdl) on first launch"
warn "Monitor layout (outputs.kdl) will be detected automatically for the new hardware"
