#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$HOME"

# ─── flags ─────────────────────────────────────────────────────────────────────
# --laptop / --desktop are overrides, not requirements: configure.sh detects
# laptop hardware on its own and remembers the answer. Passed straight through.
LAPTOP=false
DESKTOP=false
for arg in "$@"; do
    case "$arg" in
        --laptop)  LAPTOP=true ;;
        --desktop) DESKTOP=true ;;
    esac
done

# ─── shared helpers + the package/version manifest ────────────────────────────
for lib in lib/common.sh lib/manifest.sh; do
    if [ ! -f "$DOTFILES/$lib" ]; then
        echo "Missing $DOTFILES/$lib — run this from a full clone of the repo" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$DOTFILES/$lib"
done

# ─── 0. Remove DankMaterialShell ──────────────────────────────────────────────
# This slot used to hold the mirror image of this step: remove mako-notifier,
# because DMS owned the notification socket and the two fought over it. DMS is
# the one being superseded now — waybar draws the bar, mako takes the
# notifications, fuzzel is the launcher, and swww already had the wallpaper.
#
# Transitional. A machine installed from scratch today never gets DMS in the
# first place, so this only does anything on a machine that predates the switch.
# Once every machine you own has been through one install, delete this step —
# the mako version of it sat here long after it had any work left to do.
#
# Ordered before the PPAs so that a machine still carrying the avengemedia/dms
# repo has the package gone before `apt update` re-advertises it.
section "Checking for DankMaterialShell"

if pkg_installed dms; then
    warn "Removing DankMaterialShell — waybar and mako replace it"
    warn "  Your bar and notifications will be gone until you log out and back in"
    sudo apt remove -y dms
else
    info "DankMaterialShell not installed"
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

# niri and ghostty. The avengemedia/dms PPA that used to be added alongside this
# one is gone with the `dms` package; waybar and mako-notifier both come from
# Ubuntu universe and need no repo of their own.
add_ppa "danklinux (niri)" "avengemedia/danklinux"

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

# The list itself lives in lib/manifest.sh, so doctor.sh can check the same one.
# APT_BUILD_PACKAGES is what swww needs to compile; see the note there.
sudo apt install -y "${APT_PACKAGES[@]}" "${APT_BUILD_PACKAGES[@]}"

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

# Running `sudo docker` even once creates ~/.docker owned by root, and after
# that every rootless docker command fails on its own config directory — a
# confusing failure, since group membership looks correct. Hand it back.
DOCKER_CONFIG_DIR="$USER_HOME/.docker"
if [ -d "$DOCKER_CONFIG_DIR" ] && [ ! -O "$DOCKER_CONFIG_DIR" ]; then
    warn "$DOCKER_CONFIG_DIR is not owned by $CURRENT_USER (left behind by a sudo docker run) — fixing"
    sudo chown -R "$CURRENT_USER":"$CURRENT_USER" "$DOCKER_CONFIG_DIR"
fi

# ─── NVIDIA Container Toolkit ─────────────────────────────────────────────────
# Lets containers use the host GPU (`docker run --gpus all ...`). Only useful on
# machines with an NVIDIA card, and it pulls in an extra apt repo, so it's gated
# on the hardware actually being present.
section "NVIDIA Container Toolkit"

# Read the PCI vendor/class straight from sysfs rather than shelling out to
# lspci — pciutils isn't in APT_PACKAGES, and this works before any NVIDIA
# driver is installed. 0x10de is NVIDIA; class 0x0300xx is a VGA controller and
# 0x0302xx a 3D controller (compute cards with no display output).
has_nvidia_gpu() {
    local dev vendor class
    for dev in /sys/bus/pci/devices/*; do
        [ -r "$dev/vendor" ] && [ -r "$dev/class" ] || continue
        read -r vendor < "$dev/vendor"
        [ "$vendor" = "0x10de" ] || continue
        read -r class < "$dev/class"
        case "$class" in
            0x0300*|0x0302*) return 0 ;;
        esac
    done
    return 1
}

if ! has_nvidia_gpu; then
    info "No NVIDIA GPU detected — skipping the container toolkit"
elif pkg_installed nvidia-container-toolkit; then
    info "nvidia-container-toolkit already installed"
else
    info "NVIDIA GPU detected — installing nvidia-container-toolkit"

    # Upstream's .list file is the only source for these packages; Ubuntu
    # doesn't ship them. It contains a literal $(ARCH) that apt expands itself,
    # so it must be written through verbatim — don't let the shell touch it.
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg
    sudo chmod a+r /etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    sudo apt update
    sudo apt install -y nvidia-container-toolkit

    # Registers the nvidia runtime in /etc/docker/daemon.json. Root-owned and
    # read by the daemon, so this needs no user-level permissions — but the
    # daemon only picks it up on restart.
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker

    warn "GPU containers also need the NVIDIA driver — see extra.sh if it isn't installed yet"
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

# Obsidian — snap doesn't work; use the official GitHub release .deb.
# OBSIDIAN_VERSION comes from lib/manifest.sh.
install_deb "obsidian" \
    "https://github.com/obsidianmd/obsidian-releases/releases/download/v${OBSIDIAN_VERSION}/obsidian_${OBSIDIAN_VERSION}_amd64.deb"

# VS Code's postinst asks whether to add Microsoft's apt repo. Answer it up front
# so dpkg doesn't stop to ask, and so the answer is yes — that repo is how the
# .deb gets updates. ChatGPT's postinst adds its repo without asking.
echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections

# DEB_PACKAGES comes from lib/manifest.sh — see the note there on why these are
# .debs and not APT_PACKAGES.
for entry in "${DEB_PACKAGES[@]}"; do
    install_deb "${entry%%|*}" "${entry#*|}"
done

# ─── 3. snap packages ─────────────────────────────────────────────────────────
section "Installing snap packages"

for entry in "${SNAP_PACKAGES[@]}"; do
    snap_install_entry "$entry"
done

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

# ─── swww (animated wallpaper daemon) ─────────────────────────────────────────
# niri draws no background of its own, so something has to. swww is the choice
# because most of this collection is animated GIFs and swww is what animates
# them — swaybg and friends show a single still frame.
#
# It originally arrived to work around DMS, which rendered wallpapers with a QML
# Image that decoded one frame and whose upstream declined to animate it in-shell
# (DankMaterialShell#793). DMS is gone; the GIFs are the reason now.
#
# Not on crates.io and not packaged for Ubuntu, so it's installed from the git
# tag. Both binaries are needed: swww-daemon holds the layer surface, swww is
# the client that talks to it.
section "Installing swww"

if ! command -v swww &>/dev/null || ! command -v swww-daemon &>/dev/null; then
    info "Installing swww $SWWW_VERSION"
    cargo install --git https://github.com/LGFae/swww --tag "$SWWW_VERSION" --locked swww swww-daemon
else
    info "swww already installed ($(swww --version 2>/dev/null))"
fi

# ─── bluetui (bluetooth pairing) ──────────────────────────────────────────────
# What the waybar bluetooth module opens on click, in the same way network opens
# nmtui. DMS's bluetooth popover went with DMS and waybar has none of its own.
section "Installing bluetui"

if ! command -v bluetui &>/dev/null; then
    info "Installing bluetui $BLUETUI_VERSION"
    cargo install --version "$BLUETUI_VERSION" --locked bluetui
else
    info "bluetui already installed ($(bluetui --version 2>/dev/null))"
fi

# ─── Iosevka Term (Ghostty's font) ────────────────────────────────────────────
# Per-user, so no sudo: fontconfig reads ~/.local/share/fonts. The Term variant
# keeps every glyph one cell wide; config.ghostty picks its Extended width.
section "Installing Iosevka Term font"

if [ -z "$(fc-list "Iosevka Term")" ]; then
    info "Installing Iosevka Term $IOSEVKA_VERSION"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/iosevka.zip" \
        "https://github.com/be5invis/Iosevka/releases/download/v${IOSEVKA_VERSION}/PkgTTF-IosevkaTerm-${IOSEVKA_VERSION}.zip"
    mkdir -p "$HOME/.local/share/fonts/iosevka-term"
    unzip -o -q "$tmp/iosevka.zip" -d "$tmp"
    find "$tmp" -name '*.ttf' -exec cp {} "$HOME/.local/share/fonts/iosevka-term/" \;
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null
    rm -rf "$tmp"
else
    info "Iosevka Term already installed"
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
[ "$LAPTOP" = true ]  && CONFIG_ARGS+=(--laptop)
[ "$DESKTOP" = true ] && CONFIG_ARGS+=(--desktop)
"$DOTFILES/configure.sh" "${CONFIG_ARGS[@]}"

# ─── 8a. Login screen monitor layout ──────────────────────────────────────────
# GDM's greeter reads /etc/xdg/monitors.xml; without it the desk's HDMI matrix
# comes up in a mode its screen rejects. Here rather than in configure.sh
# because it needs sudo, and after it because configure.sh settles the machine
# type. Desktop only, like desktop.kdl — and taken off a machine that has since
# become a laptop, but only if it is still our copy.
section "Login screen monitor layout"

GDM_MONITORS=/etc/xdg/monitors.xml
if [ "$(head -n1 "$USER_HOME/.config/niri/.machine-type" 2>/dev/null)" = desktop ]; then
    if cmp -s "$DOTFILES/system/monitors.xml" "$GDM_MONITORS"; then
        info "$GDM_MONITORS already matches the repo"
    else
        sudo install -m 644 "$DOTFILES/system/monitors.xml" "$GDM_MONITORS"
        info "Installed $GDM_MONITORS — takes effect at the next login screen"
    fi
elif cmp -s "$DOTFILES/system/monitors.xml" "$GDM_MONITORS"; then
    sudo rm -f "$GDM_MONITORS"
    info "Removed $GDM_MONITORS (desktop only)"
fi

# ─── 8b. niri-tasks ───────────────────────────────────────────────────────────
# Workspace-scoped taskwarrior: Mod+Alt+T/L/P, the task box, and the active-task
# overlay. Its own repo, its own release cycle — this just makes sure a new
# machine ends up with it.
#
# Runs after configure.sh so ~/.config/niri exists and the include stub is
# already seeded; its installer symlinks the real file over that stub.
#
# It lives in ~/Projects like any other project rather than somewhere hidden, so
# `niritasks project open` finds it and editing it is `cargo install --path` again.
section "Installing niri-tasks"

NIRI_TASKS_DIR="$USER_HOME/Projects/niri-tasks"
NIRI_TASKS_REPO="https://github.com/pauldaywork/niri-tasks"

if [ -d "$NIRI_TASKS_DIR/.git" ]; then
    info "Updating niri-tasks"
    git -C "$NIRI_TASKS_DIR" pull --ff-only \
        || warn "Could not fast-forward niri-tasks — leaving the working tree alone"
else
    info "Cloning niri-tasks"
    git clone "$NIRI_TASKS_REPO" "$NIRI_TASKS_DIR" \
        || warn "Could not clone niri-tasks — Mod+Alt+T/L/P will be absent"
fi

if [ -x "$NIRI_TASKS_DIR/install.sh" ]; then
    # Needs cargo, which step 5 installed. Not fatal if it fails: the rest of
    # the machine is fine without it, and the include stub keeps niri loading.
    bash "$NIRI_TASKS_DIR/install.sh" || warn "niri-tasks install failed — see above"
fi

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

# ─── 10. VS Code extensions ───────────────────────────────────────────────────
section "Installing VS Code extensions"

if [ -s "$DOTFILES/config/Code/extensions.txt" ]; then
    while IFS= read -r ext; do
        code --install-extension "$ext" --force
    done < "$DOTFILES/config/Code/extensions.txt"
fi

# ─── 11. Git config ───────────────────────────────────────────────────────────
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

# ─── 12. SSH key ──────────────────────────────────────────────────────────────
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
echo "  1. Reboot (or log out and back in) to start niri"
echo "  2. Run 'claude' to log into Claude Code"
echo "  3. Log into Firefox, Chrome, Obsidian as needed"
echo "  4. Run 'bash extra.sh' if you want Steam, OpenCode, LM Studio, or NVIDIA drivers"
echo ""
# This used to promise the opposite: DMS generated colors.kdl/layout.kdl and
# wrote outputs.kdl from detected hardware, so a new machine configured its own
# monitors. Nothing does that now — the outputs are written out in config.kdl —
# and a new machine that silently runs at the wrong resolution is a much harder
# thing to notice than a line of install output saying it might.
warn "Monitor layout is NOT auto-detected: config/niri/config.kdl names this"
warn "setup's outputs and modes explicitly. On different hardware, check"
warn "'niri msg outputs' and edit the output blocks to match."
