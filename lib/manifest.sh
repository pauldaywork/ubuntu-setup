# What a machine is supposed to have on it. Sourced, never executed.
#
# install.sh installs from this; doctor.sh checks against it. They used to keep
# separate copies with a comment on doctor.sh's asking whoever edited one to
# remember the other, which is a promise no repo keeps — and a diagnostic that
# drifts from the installer is worse than no diagnostic, because it reports
# problems that aren't real and misses ones that are.

# ─── versions ─────────────────────────────────────────────────────────────────
NODE_VERSION="v24.18.0"

# Obsidian has no apt repo — this is the .deb install.sh downloads.
# Latest at https://github.com/obsidianmd/obsidian-releases/releases
OBSIDIAN_VERSION="1.12.7"

# swww is neither on crates.io nor packaged for Ubuntu, so it's built from this
# git tag. https://github.com/LGFae/swww
SWWW_VERSION="v0.11.2"

# bluetui — the TUI the waybar bluetooth module opens. On crates.io but not
# packaged for Ubuntu. https://github.com/pythops/bluetui
BLUETUI_VERSION="0.8.0"

# Iosevka Term — Ghostty's font (the Extended width, set in config.ghostty).
# Not packaged for Ubuntu; install.sh unpacks the release zip into
# ~/.local/share/fonts. https://github.com/be5invis/Iosevka/releases
IOSEVKA_VERSION="34.8.1"

# worktrunk (`wt`) — git worktrees for running coding agents in parallel, one
# per branch, each set up by the repo's own .config/wt.toml hooks. The prebuilt
# musl binary rather than `cargo install`: 0.79 needs a newer rustc than the
# toolchain here, and upgrading every project's compiler to install one tool is
# the wrong trade. https://github.com/max-sixty/worktrunk/releases
WORKTRUNK_VERSION="0.79.0"
WORKTRUNK_SHA256="b8c190b1d652370ef9f6b8f4694a2d6831b5b22f4b789f047612aad32764c6cf"

# dotenvx — worktree hooks use `dotenvx set KEY value -f .env --plain` to
# *replace* a key in a copied .env (a new port, a cloned database), which plain
# appending gets wrong: the copied value stays first and wins. Standalone
# binary, Node bundled. Its curl | sh installer checks no checksum, so this pins
# one. https://github.com/dotenvx/dotenvx/releases
DOTENVX_VERSION="2.30.0"
DOTENVX_SHA256="1ac0fb8fef37c10de4297686a273719290fbc29d8c3abf9595ab7a023119c1c3"

# herdr-worktrunk — the herdr plugin that drives worktrunk from herdr's keys and
# shows each worktree as a workspace grouped under its project. A herdr plugin
# is unsandboxed code, so it is pinned to a full commit whose source was read
# (2026-09-26): it runs `wt` in a visible pane, never passes --yes past
# worktrunk's hook approval, and makes no network calls of its own. Bump the
# pin only after reading the diff.
# https://github.com/devashish2203/herdr-worktrunk
HERDR_WORKTRUNK_REF="8ceca541de8fb0d6006727e172534e1e2af17224"

# ─── .deb installs ────────────────────────────────────────────────────────────
# Downloaded directly rather than listed in APT_PACKAGES: each package's own
# postinst adds its vendor's apt repo (with a keyring it writes itself), so the
# repo cannot be configured before the first install, and updates arrive through
# apt afterwards. That is also why there is no version pin — the URLs are the
# vendors' "latest" links.
#
# VS Code used to be the snap. Its launcher hard-codes --ozone-platform=x11 as the
# last argument, so it always ran under Xwayland and blurred at fractional scale;
# the .deb runs natively on Wayland. Settings and extensions live in ~/.config/Code
# and ~/.vscode either way, so switching loses nothing.
DEB_PACKAGES=(
    "code|https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    "chatgpt|https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb"
)

# ─── apt ──────────────────────────────────────────────────────────────────────
APT_PACKAGES=(
    # window manager. niri and ghostty are from the danklinux PPA, which is why
    # ghostty isn't a snap: the repo is already configured for niri's sake, and
    # the deb avoids classic-snap confinement.
    niri
    ghostty

    # The bar and the notification daemon, which between them replace what
    # DankMaterialShell used to do. Both are plain Ubuntu universe packages —
    # the DMS PPA is gone from install.sh along with `dms` itself.
    #
    # mako in particular used to be actively *removed* by install.sh: DMS owned
    # the notification socket and the two fought over it. Nothing implements
    # org.freedesktop.Notifications now, so notify-send — which
    # window-rules/toggle.sh calls on every profile switch — needs it back.
    waybar
    mako-notifier

    # dmenu-style picker used by open_project_workspace.sh (Mod+Alt+P) and by
    # wallpaper/pick.sh (Mod+Alt+B). Usually pulled in as a niri dependency, but
    # named here so it can't silently disappear from under the shortcuts.
    fuzzel

    # Thumbnails for the wallpaper picker. Named for the same reason as fuzzel:
    # it happened to be installed here already, and a shortcut that quietly
    # stops showing previews on a fresh machine is worse than one that fails.
    # ffmpeg rather than ImageMagick because -frames:v 1 takes the first frame
    # of an animated GIF, and most of these wallpapers are animated GIFs.
    ffmpeg

    # dev tools
    git
    curl
    # unzip — install.sh unpacks the Iosevka release zip with it.
    unzip
    build-essential
    # jq — the Mod+Alt+Q close-workspace bind in config/niri/config.kdl picks
    # the focused workspace's windows out of `niri msg -j`, and laptop.kdl's
    # Mod+Alt+D reads which outputs are lit the same way. Also a
    # general-purpose tool worth having on a new machine.
    jq
    # fzf — the herdr-worktrunk plugin's branch picker.
    fzf
    libudev-dev
    util-linux-extra

    # inotify-tools was here for wallpaper-sync.sh, which watched DMS's session
    # file to follow the wallpaper picker. Both are gone: the selection is a
    # path in a file this repo writes, so nothing watches anything.

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

# Needed to *build* swww, not to run it. install.sh installs these; doctor.sh
# deliberately doesn't check them, because a machine that built swww and then
# had its build deps cleaned up is a healthy machine, and flagging it would be
# doctor crying wolf. The binary links liblz4.so.1 from liblz4-1 — a different
# package, and one nothing here has to ask for. What actually matters, swww
# being installed and running, doctor checks directly.
APT_BUILD_PACKAGES=(
    liblz4-dev
    libwayland-dev
    wayland-protocols
    # niri-tasks: the task box is a GTK window, and the active-task readout is a
    # gtk4-layer-shell surface. Build-time only — the runtime libs come in as
    # dependencies of these.
    libgtk-4-dev
    libgtk4-layer-shell-dev
    # bluetui talks to bluez over D-Bus, and the dbus crate links libdbus-1.
    libdbus-1-dev
)

# ─── snap ─────────────────────────────────────────────────────────────────────
# "name" or "name:classic" — snap_install_entry in common.sh reads this form.
SNAP_PACKAGES=(
    firefox
    cmake:classic
)
