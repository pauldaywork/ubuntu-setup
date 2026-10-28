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

# niri isn't in Ubuntu's archive; this PPA is the source niri's own docs give
# for Ubuntu, and ghostty comes from it too.
add_ppa "niri" "avengemedia/danklinux"

sudo mkdir -p /etc/apt/keyrings

# Firefox — Mozilla's own .deb rather than Ubuntu's snap, so it updates through
# apt like everything else and runs unconfined. Ubuntu's `firefox` is a
# transitional package that installs the snap, and its 1: epoch makes it
# outrank every Mozilla version, so the pin has to be 1000: only that priority
# lets apt pick a lower version (and see below for why that isn't enough).
# The key is checked against the fingerprint
# Mozilla publishes before apt is told to trust it. A repo set up another way
# (Mozilla's own docs write mozilla.list) is left alone: apt rejects the same
# URI listed twice with different Signed-By.
MOZILLA_KEY=/etc/apt/keyrings/packages.mozilla.org.asc
MOZILLA_FPR=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
if [ -f /etc/apt/sources.list.d/mozilla.sources ] ||
   apt-cache policy 2>/dev/null | grep packages.mozilla.org >/dev/null; then
    info "Already present: Mozilla's Firefox repo"
else
    info "Adding Mozilla's Firefox repo"
    tmp=$(mktemp)
    wget -qO "$tmp" https://packages.mozilla.org/apt/repo-signing-key.gpg
    if ! gpg --show-keys --with-colons "$tmp" | grep "^fpr:*$MOZILLA_FPR:" >/dev/null; then
        rm -f "$tmp"
        echo "Mozilla's signing key does not have fingerprint $MOZILLA_FPR — stopping" >&2
        exit 1
    fi
    sudo install -m 644 "$tmp" "$MOZILLA_KEY"
    rm -f "$tmp"
    sudo tee /etc/apt/sources.list.d/mozilla.sources > /dev/null <<EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $MOZILLA_KEY
EOF
fi
# The -1 stanza and the unattended-upgrades drop-in are there because the 1000
# pin alone didn't hold. unattended-upgrades pins every origin outside its
# allowed list to "never", Mozilla's included, so it took Ubuntu's 1:1snap1
# package for an upgrade and swapped it back in, snap and all. Allowing
# Mozilla's site fixes that and gets Firefox its security updates unattended.
# The -1 pin means nothing at all can choose Ubuntu's package again.
sudo tee /etc/apt/preferences.d/mozilla > /dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF
sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox > /dev/null <<'EOF'
Unattended-Upgrade::Origins-Pattern:: "site=packages.mozilla.org";
EOF

# GitHub CLI — not in Ubuntu's archive. configure.sh clones the private
# herdr-speak repo with it. The keyring is published already dearmored.
if ! apt-cache show gh &>/dev/null; then
    info "Adding GitHub CLI repo"
    wget -qO - https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
fi

sudo apt update

# ─── 2. apt packages ──────────────────────────────────────────────────────────
section "Installing apt packages"

# The list itself lives in lib/manifest.sh, so doctor.sh can check the same one.
# APT_BUILD_PACKAGES is what swww needs to compile; see the note there.
# --allow-downgrades is for firefox alone: swapping Ubuntu's transitional
# package (1:1snap1-…) for Mozilla's is a downgrade by version number, and -y
# refuses one without the flag. Only the 1000 pin can make apt choose a lower
# version, so nothing else in the list is affected.
sudo apt install -y --allow-downgrades "${APT_PACKAGES[@]}" "${APT_BUILD_PACKAGES[@]}"

# ─── Firefox ──────────────────────────────────────────────────────────────────
# The .deb is in by now, so the snap that Ubuntu ships can go without leaving
# the machine without a browser. snap remove keeps a snapshot of its profile
# (`snap saved`) for 31 days.
section "Setting up Firefox"

if snap list firefox &>/dev/null; then
    info "Removing the Firefox snap"
    sudo snap remove firefox
fi

# Add-ons are force-installed by enterprise policy, so a new profile gets them
# on first launch and they can't be removed by accident. Password managers and
# login add-ons are deliberately left out — those get signed into by hand.
#
# The same file turns off Firefox's "make me your default" prompt. Outside
# GNOME, accepting it writes a userapp-Firefox-*.desktop of Firefox's own and
# points mimeapps.list at that instead of firefox.desktop — the default is
# set below, so the prompt has nothing to add.
FIREFOX_POLICIES=/etc/firefox/policies/policies.json
if cmp -s "$DOTFILES/system/firefox-policies.json" "$FIREFOX_POLICIES"; then
    info "$FIREFOX_POLICIES already matches the repo"
else
    sudo install -D -m 644 "$DOTFILES/system/firefox-policies.json" "$FIREFOX_POLICIES"
    info "Installed $FIREFOX_POLICIES — Firefox applies it at its next start"
fi

if [ "$(xdg-settings get default-web-browser 2>/dev/null)" != firefox.desktop ]; then
    info "Making Firefox the default browser"
    xdg-settings set default-web-browser firefox.desktop ||
        warn "Could not make Firefox the default browser — doctor.sh will report it"
fi

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

# ─── Backlight permissions ────────────────────────────────────────────────────
# Ubuntu builds brightnessctl without logind support and ships no udev rule, so
# it writes /sys/class/backlight/*/brightness directly. That file is root:video
# 664, so without the video group the brightness keys and waybar's backlight
# scroll fail with "Permission denied". Same new-session caveat as docker.
section "Configuring backlight permissions"

if id -nG "$CURRENT_USER" | grep -qw video; then
    info "$CURRENT_USER already in the video group"
else
    info "Adding $CURRENT_USER to the video group"
    sudo usermod -aG video "$CURRENT_USER"
    warn "Log out and back in before the brightness keys work"
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

# VS Code's postinst asks whether to add Microsoft's apt repo. Answer it up front
# so dpkg doesn't stop to ask, and so the answer is yes — that repo is how the
# .deb gets updates.
echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections

# DEB_PACKAGES comes from lib/manifest.sh — see the note there on why these are
# .debs and not APT_PACKAGES.
for entry in "${DEB_PACKAGES[@]}"; do
    install_deb "${entry%%|*}" "${entry#*|}"
done

# Proton Pass has no apt repo, so it is pinned and checked rather than listed
# in DEB_PACKAGES — see lib/manifest.sh. A mismatched download stops the install.
install_deb proton-pass \
    "https://proton.me/download/pass/linux/proton-pass_${PROTON_PASS_VERSION}_amd64.deb" \
    "$PROTON_PASS_SHA512"

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
# nmtui. waybar has no bluetooth popover of its own.
section "Installing bluetui"

if ! command -v bluetui &>/dev/null; then
    info "Installing bluetui $BLUETUI_VERSION"
    cargo install --version "$BLUETUI_VERSION" --locked bluetui
else
    info "bluetui already installed ($(bluetui --version 2>/dev/null))"
fi

# ─── worktrunk and dotenvx (worktrees for parallel agents) ────────────────────
# Prebuilt, checksum-pinned binaries into ~/.local/bin — see lib/manifest.sh for
# why not cargo or curl | sh. Reinstalled when the pinned version changes.
section "Installing worktrunk and dotenvx"

if wt --version 2>/dev/null | grep -qF "$WORKTRUNK_VERSION"; then
    info "worktrunk already installed ($(wt --version 2>/dev/null))"
else
    info "Installing worktrunk $WORKTRUNK_VERSION"
    install_release_binary \
        "https://github.com/max-sixty/worktrunk/releases/download/v${WORKTRUNK_VERSION}/worktrunk-x86_64-unknown-linux-musl.tar.xz" \
        "$WORKTRUNK_SHA256" "worktrunk-x86_64-unknown-linux-musl/wt" \
        || warn "worktrunk install failed — see above"
fi

if dotenvx --version 2>/dev/null | grep -qF "$DOTENVX_VERSION"; then
    info "dotenvx already installed ($(dotenvx --version 2>/dev/null))"
else
    info "Installing dotenvx $DOTENVX_VERSION"
    install_release_binary \
        "https://github.com/dotenvx/dotenvx/releases/download/v${DOTENVX_VERSION}/dotenvx-${DOTENVX_VERSION}-linux-x86_64.tar.gz" \
        "$DOTENVX_SHA256" "./dotenvx" \
        || warn "dotenvx install failed — see above"
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
# Workspace-scoped taskwarrior: Mod+Alt+T/P and Mod+Alt+Ctrl+T, the task box, and the task
# panel. Its own repo, its own release cycle — this just makes sure a new
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
        || warn "Could not clone niri-tasks — Mod+Alt+T/P and Mod+Alt+Ctrl+T will be absent"
fi

if [ -x "$NIRI_TASKS_DIR/install.sh" ]; then
    # Needs cargo, which step 5 installed. Not fatal if it fails: the rest of
    # the machine is fine without it, and the include stub keeps niri loading.
    bash "$NIRI_TASKS_DIR/install.sh" || warn "niri-tasks install failed — see above"
fi

# ─── 9. VS Code extensions ───────────────────────────────────────────────────
section "Installing VS Code extensions"

if [ -s "$DOTFILES/config/Code/extensions.txt" ]; then
    while IFS= read -r ext; do
        code --install-extension "$ext" --force
    done < "$DOTFILES/config/Code/extensions.txt"
fi

# ─── 10. Git config ───────────────────────────────────────────────────────────
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

# ─── 11. SSH key ──────────────────────────────────────────────────────────────
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
echo "  3. Run 'bash extra.sh' if you want NVIDIA drivers"
echo ""
# Nothing detects monitors: the outputs are written out in config.kdl, and a new
# machine that silently runs at the wrong resolution is a much harder thing to
# notice than a line of install output saying it might.
warn "Monitor layout is NOT auto-detected: config/niri/config.kdl names this"
warn "setup's outputs and modes explicitly. On different hardware, check"
warn "'niri msg outputs' and edit the output blocks to match."
