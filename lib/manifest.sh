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

# ─── apt ──────────────────────────────────────────────────────────────────────
APT_PACKAGES=(
    # window manager + shell — all from the danklinux PPA. ghostty comes from
    # there too, which is why it isn't a snap: the repo is already configured,
    # and the deb avoids classic-snap confinement.
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
    # jq is no longer used by anything in this repo — the scripts that needed it
    # moved to niri-tasks, which talks to niri's socket directly. Kept because
    # it is a general-purpose tool worth having on a new machine.
    jq
    tmux
    libudev-dev
    util-linux-extra

    # inotify-tools is what wallpaper-sync.sh watches the DMS session file with,
    # so it's a runtime dependency of the wallpaper setup, not a build one.
    inotify-tools

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
)

# ─── snap ─────────────────────────────────────────────────────────────────────
# "name" or "name:classic" — snap_install_entry in common.sh reads this form.
SNAP_PACKAGES=(
    firefox
    code:classic
    cmake:classic
)
