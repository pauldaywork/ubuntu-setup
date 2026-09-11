#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$HOME"

# ─── flags ─────────────────────────────────────────────────────────────────────
LAPTOP=false
DESKTOP=false
for arg in "$@"; do
    case "$arg" in
        --laptop)  LAPTOP=true ;;
        --desktop) DESKTOP=true ;;
    esac
done

# ─── shared helpers ───────────────────────────────────────────────────────────
for _lib in common paths; do
    if [ ! -f "$DOTFILES/lib/$_lib.sh" ]; then
        echo "Missing $DOTFILES/lib/$_lib.sh — run this from a full clone of the repo" >&2
        exit 1
    fi
done
# shellcheck source=/dev/null
source "$DOTFILES/lib/common.sh"
source "$DOTFILES/lib/paths.sh"

# ─── Copy dotfiles ────────────────────────────────────────────────────────────
section "Copying dotfiles"

# Everything that is a straight file, from lib/paths.sh. config.kdl, the
# wallpapers and the seeded stubs are handled below — they need more than a
# source and a destination.
for _row in "${DOTFILES_MAP[@]}"; do
    map_entry "$_row"
    _src="$DOTFILES/$REPO_PATH"
    _dst="$USER_HOME/$HOME_PATH"

    case "$KIND" in
        copy)  copy "$_src" "$_dst" ;;
        exec)  copy "$_src" "$_dst"; chmod +x "$_dst" ;;
        # Deployed only on laptops, and MACHINE_TYPE is not settled until below,
        # so that row is applied there instead.
        laptop) ;;
        *) warn "lib/paths.sh: unknown kind '$KIND' for $REPO_PATH" ;;
    esac
done

# Laptop-specific niri config (display on/off binds, vertical workspace binds).
#
# This used to hang entirely on remembering `--laptop` every single time. The
# copy above replaces config.kdl with the repo's, which never carries the
# include line, so one re-run without the flag silently deleted those binds —
# no error, nothing to notice until you reached for a shortcut that had gone.
#
# So the machine decides for itself, and the decision is remembered the way the
# window-rules profile above already is. The flags stay as an override, and
# --desktop is how you undo a wrong guess.
# The record holds "laptop" or "desktop" rather than existing/not existing, so
# that an explicit --desktop on laptop hardware sticks too. A bare marker file
# would be re-detected away on the next flagless run, which is the same "the
# decision wasn't remembered" bug in the other direction.
mkdir -p "$USER_HOME/.config/niri"
MACHINE_TYPE_FILE="$USER_HOME/.config/niri/.machine-type"

# DMI chassis types: 8 portable, 9 laptop, 10 notebook, 11 hand held,
# 14 sub-notebook, 30 tablet, 31 convertible, 32 detachable. Some machines
# report something useless there, so a battery is the fallback tell — same
# read-sysfs-directly approach install.sh uses to spot an NVIDIA GPU.
is_laptop_hardware() {
    local chassis
    if [ -r /sys/class/dmi/id/chassis_type ]; then
        read -r chassis < /sys/class/dmi/id/chassis_type
        case "$chassis" in
            8|9|10|11|14|30|31|32) return 0 ;;
        esac
    fi
    compgen -G "/sys/class/power_supply/BAT*" > /dev/null
}

RECORDED_TYPE=""
[ -f "$MACHINE_TYPE_FILE" ] && RECORDED_TYPE="$(head -n1 "$MACHINE_TYPE_FILE")"

if [ "$DESKTOP" = true ]; then
    MACHINE_TYPE="desktop"; MACHINE_REASON="--desktop given"
elif [ "$LAPTOP" = true ]; then
    MACHINE_TYPE="laptop";  MACHINE_REASON="--laptop given"
elif [ "$RECORDED_TYPE" = "laptop" ] || [ "$RECORDED_TYPE" = "desktop" ]; then
    MACHINE_TYPE="$RECORDED_TYPE"; MACHINE_REASON="remembered from a previous install"
elif is_laptop_hardware; then
    MACHINE_TYPE="laptop";  MACHINE_REASON="detected from chassis type/battery"
else
    MACHINE_TYPE="desktop"; MACHINE_REASON="no laptop hardware detected"
fi

echo "$MACHINE_TYPE" > "$MACHINE_TYPE_FILE"

if [ "$MACHINE_TYPE" = "laptop" ]; then
    info "Laptop-specific niri config: on ($MACHINE_REASON)"
    # From the table rather than spelled out again, so doctor.sh and capture/
    # cannot end up disagreeing with this about which files those are.
    for _row in "${DOTFILES_MAP[@]}"; do
        map_entry "$_row"
        [ "$KIND" = laptop ] || continue
        copy "$DOTFILES/$REPO_PATH" "$USER_HOME/$HOME_PATH"
    done
else
    info "Laptop-specific niri config: off ($MACHINE_REASON)"
fi


# niri
# config.kdl is assembled before being installed — the repo's copy plus the
# laptop include when this is a laptop — so copy() can compare the finished
# article and skip a file that already matches. Appending after copying meant
# the live file could never equal the repo's, so every run rewrote it and
# archived the old one, which is most of how ~/.config-backups filled up.
NIRI_CONFIG_TMP=$(mktemp)
cat "$DOTFILES/config/niri/config.kdl" > "$NIRI_CONFIG_TMP"
if [ "$MACHINE_TYPE" = "laptop" ]; then
    printf '\ninclude "laptop.kdl"\n' >> "$NIRI_CONFIG_TMP"
fi
copy "$NIRI_CONFIG_TMP" "$USER_HOME/.config/niri/config.kdl"
rm -f "$NIRI_CONFIG_TMP"


# Seed the active window-rules profile only if one isn't already chosen,
# so re-running install doesn't reset an existing choice.
if [ ! -e "$USER_HOME/.config/niri/window-rules-active.kdl" ]; then
    ln -s "$USER_HOME/.config/niri/window-rules/focus.kdl" "$USER_HOME/.config/niri/window-rules-active.kdl"
    echo "focus" > "$USER_HOME/.config/niri/.window-rules-profile"
fi

# The dms/binds.kdl stub that used to be seeded here is gone with the include
# that needed it. It existed only because config.kdl carried an unconditional
# `include "dms/binds.kdl"` and DMS would not create that file until someone
# saved a keybind through its settings UI — so without the stub, a fresh machine
# had an invalid niri config on every login. No include, no stub, and nothing
# recreates ~/.config/niri/dms/ any more.

# niri refuses to load a config whose include is missing — it falls back to its
# built-in defaults, which looks like "my keybinds vanished". niri-tasks owns the
# workspace-task binds and symlinks the real file over this stub when it's
# installed; without the stub, a machine that only has this repo would have a
# config niri refuses to load.
if [ ! -e "$USER_HOME/.config/niri/niri-tasks.kdl" ]; then
    printf 'binds {\n\n}\n' > "$USER_HOME/.config/niri/niri-tasks.kdl"
    info "Seeded empty $USER_HOME/.config/niri/niri-tasks.kdl"
fi

# The systemd user unit for the wallpaper. A unit rather than a niri
# spawn-at-startup line so that a crash is restarted instead of leaving the
# desktop bare until the next login, and so `systemctl --user status` can say
# what went wrong. graphical-session.target starts and stops it with niri.
#
# One unit, where there used to be two: wallpaper-sync.service ran a watch loop
# over DMS's session.json, and swww-daemon.service's only job beyond starting
# the daemon was to kick it. The daemon now paints from its own ExecStartPost.

# `enable` alone is enough: graphical-session.target pulls it in at login.
# Starting it here would fail on a fresh machine that has no session yet
# (Requisite=graphical-session.target), so that's left to the next login —
# except when there *is* a session, where it saves a re-login.
if command -v systemctl &>/dev/null; then
    # Retire wallpaper-sync.service on a machine that already has it. Deleting
    # the unit file without disabling it first would leave a dangling symlink in
    # graphical-session.target.wants, which systemd complains about on every
    # daemon-reload and which `systemctl --user disable` can no longer clean up
    # once the file it points at is gone. Stop before disable, so it isn't left
    # running until the next logout with nothing left to restart it.
    if systemctl --user list-unit-files wallpaper-sync.service &>/dev/null \
       && [ -e "$USER_HOME/.config/systemd/user/wallpaper-sync.service" ]; then
        systemctl --user stop wallpaper-sync.service 2>/dev/null || true
        systemctl --user disable wallpaper-sync.service 2>/dev/null \
            && info "Retired wallpaper-sync.service (swww-daemon paints directly now)"
    fi

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable swww-daemon.service 2>/dev/null \
        && info "Enabled the swww-daemon user unit" \
        || warn "Could not enable the swww-daemon user unit (no systemd user session?)"
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        systemctl --user restart swww-daemon.service 2>/dev/null \
            && info "Started swww-daemon" || true
    fi
fi

# ghostty
# `wt tmux-session` opens a tmux session named after the focused workspace, in
# the matching ~/Projects folder. It belongs to niri-tasks, which is optional —
# so fall back to plain tmux rather than leaving ghostty pointed at a command
# that doesn't exist, which would mean no terminal at all.
if command -v wt >/dev/null; then
    GHOSTTY_COMMAND="wt tmux-session"
else
    GHOSTTY_COMMAND="tmux"
fi
sed -i "s|^command = .*|command = $GHOSTTY_COMMAND|" \
    "$USER_HOME/.config/ghostty/config.ghostty"

# The DankMaterialShell theme path rewrite that used to follow is gone with the
# settings file it edited. waybar and mako need no post-processing: their colours
# are written literally into config/waybar/style.css and config/mako/config,
# because there is no longer anything generating a palette to point at.

# ─── Files this repo used to install and no longer does ───────────────────────
# Deleting a file from the repo does not delete it from a machine that already
# has it. Nothing here reads these any more, but left in place they are worse
# than clutter: the DMS plugin keeps rendering a widget whose scripts are gone,
# and fifteen dead scripts in ~/.config/niri make it impossible to tell at a
# glance which ones are live.
#
# Removal is safe in this order because config.kdl was written above, so by the
# time these go the binds that used to call them are already gone too — either
# replaced by niri-tasks.kdl, or by the empty stub when niri-tasks is absent.
#
# Keep this list rather than globbing ~/.config/niri/*.sh: wallpaper-sync.sh
# lives there and is very much still ours.
STALE_FILES=(
    # The workspace-task system, now https://github.com/pauldaywork/niri-tasks
    ".config/niri/task-lib.sh"
    ".config/niri/task-tag.sh"
    ".config/niri/task-active.sh"
    ".config/niri/task-list.sh"
    ".config/niri/task-add.sh"
    ".config/niri/task-add-text.sh"
    ".config/niri/task-get-text.sh"
    ".config/niri/task-edit-text.sh"
    ".config/niri/task-get-notes.sh"
    ".config/niri/task-annotate-text.sh"
    ".config/niri/create_named_workspace.sh"
    ".config/niri/rename_workspace.sh"
    ".config/niri/default_workspace_name.sh"
    ".config/niri/open_project_workspace.sh"
    ".config/niri/tmux-niri-session.sh"
    # Its fuzzel theme too — niri-tasks installs its own as picker.ini.
    ".config/fuzzel/project-picker.ini"
    # The window-rules toggle moved in beside the profiles it switches between,
    # so it installs to window-rules/toggle.sh now.
    ".config/niri/toggle-window-rules.sh"
    # Dropping DMS moved our laptop binds out of the directory DMS generated
    # into. config.kdl includes "laptop.kdl" now, so the old copy is dead — and
    # worse than dead, since it looks exactly like a live config file.
    ".config/niri/dms/laptop.kdl"
    # The wallpaper watch loop and its unit. swww-daemon.service paints from its
    # own ExecStartPost now. The unit is disabled further up before it is
    # removed here — order matters, see the note there.
    ".config/niri/wallpaper-sync.sh"
    ".config/systemd/user/wallpaper-sync.service"
)

STALE_REMOVED=0
for rel in "${STALE_FILES[@]}"; do
    if [ -e "$USER_HOME/$rel" ]; then
        rm -f "$USER_HOME/$rel"
        STALE_REMOVED=$((STALE_REMOVED + 1))
    fi
done

# DankMaterialShell's whole config tree, which subsumes the activetask plugin
# directory that used to be removed here on its own. A directory, so it needs
# -rf rather than the loop above.
#
# Gated on the package actually being gone. apt leaves ~/.config alone when it
# removes something, so this is the only thing that will ever clean it up — but
# running install.sh is what removes the package, and configure.sh is also run
# on its own, by someone who may still be using DMS and would not thank us for
# deleting its settings out from under it.
if [ -d "$USER_HOME/.config/DankMaterialShell" ] && ! pkg_installed dms; then
    rm -rf "$USER_HOME/.config/DankMaterialShell"
    STALE_REMOVED=$((STALE_REMOVED + 1))
    info "Removed the leftover ~/.config/DankMaterialShell tree"
fi

# The other half of DMS's state: session.json (the wallpaper selection, launcher
# history, night mode, the notepad) under ~/.local/state.
if [ -d "$USER_HOME/.local/state/DankMaterialShell" ] && ! pkg_installed dms; then
    rm -rf "$USER_HOME/.local/state/DankMaterialShell"
    STALE_REMOVED=$((STALE_REMOVED + 1))
    info "Removed the leftover ~/.local/state/DankMaterialShell tree"
fi

[ "$STALE_REMOVED" -gt 0 ] && info "Removed $STALE_REMOVED file(s) this repo no longer installs"

# VS Code settings (extensions are not installed here — see install.sh)

# ─── Projects folder ──────────────────────────────────────────────────────────
section "Setting up Projects folder"

PROJECTS_DIR="$USER_HOME/Projects"
if [ ! -d "$PROJECTS_DIR" ]; then
    mkdir -p "$PROJECTS_DIR"
    info "Created $PROJECTS_DIR"
else
    info "Projects folder already exists: $PROJECTS_DIR"
fi

# ─── Wallpapers ───────────────────────────────────────────────────────────────
section "Setting up wallpapers"

# The whole folder is installed, not just the active one. With DMS's picker gone
# there is nothing browsing this directory at runtime, but switching wallpaper is
# now "point wallpaper-active at a different file in here", and that only works
# if they are all present. Animated GIFs included — swww is what renders those.
WALLPAPER_DIR="$USER_HOME/Documents/Wallpapers"
mkdir -p "$WALLPAPER_DIR"

# copy() compares before writing, so a same-named file that *differs* is treated
# as stale — an edited or truncated copy, or one from before the repo's version
# changed — and gets replaced, with the old one backed up like any other config.
# Wallpapers this machine has that the repo doesn't are left alone; installing is
# not the same as pruning.
for wall in "$DOTFILES/wallpaper/images"/*; do
    [ -f "$wall" ] || continue
    name="$(basename "$wall")"
    # `active` is our own bookkeeping, not a wallpaper.
    [ "$name" = "active" ] && continue
    copy "$wall" "$WALLPAPER_DIR/$name"
done

# Which one to select on a fresh machine. wallpaper/active names it, so the repo
# tracks the choice without configure.sh needing a hardcoded filename.
ACTIVE_WALLPAPER=""
if [ -s "$DOTFILES/wallpaper/active" ]; then
    ACTIVE_WALLPAPER="$(head -n1 "$DOTFILES/wallpaper/active")"
fi
if [ -z "$ACTIVE_WALLPAPER" ] || [ ! -f "$WALLPAPER_DIR/$ACTIVE_WALLPAPER" ]; then
    warn "wallpaper/active names no installed file — falling back to the first wallpaper"
    ACTIVE_WALLPAPER="$(cd "$WALLPAPER_DIR" && ls | head -n1)"
fi

WALLPAPER_DST="$WALLPAPER_DIR/$ACTIVE_WALLPAPER"

# Record which image swww should paint. This replaces seeding DMS's
# session.json, and the rule it enforces is carried over unchanged: select a
# wallpaper if none is selected, but never overrule one already chosen on this
# machine. Re-running the installer to pick up an unrelated config change used
# to throw away whichever wallpaper you'd since picked, and the fix then is the
# fix now — the installer's job is to make sure there *is* one, not to have the
# last word on which. Same treatment as the window-rules profile seeded above.
#
# A single line holding a path. Reading it back needs `head -n1` and a test that
# the file still exists, which is the whole of the format; the fifty lines of
# Python this replaces were spent keeping DMS's other session state intact while
# editing one key out of the middle of its JSON, and none of that is owed to a
# file we write ourselves.
WALLPAPER_ACTIVE="$USER_HOME/.config/niri/wallpaper-active"
CURRENT_WALLPAPER=""
[ -s "$WALLPAPER_ACTIVE" ] && CURRENT_WALLPAPER="$(head -n1 "$WALLPAPER_ACTIVE")"

if [ -z "$ACTIVE_WALLPAPER" ]; then
    warn "No wallpapers installed — none selected"
elif [ -n "$CURRENT_WALLPAPER" ] && [ -f "$CURRENT_WALLPAPER" ]; then
    info "Wallpaper already selected, leaving it alone: $(basename "$CURRENT_WALLPAPER")"
else
    printf '%s\n' "$WALLPAPER_DST" > "$WALLPAPER_ACTIVE"
    info "Wallpaper set to $ACTIVE_WALLPAPER"
fi

# ─── Prune old backups ────────────────────────────────────────────────────────
# Backups are only worth keeping while they're plausibly the version you want
# back. Nothing ever deleted them before, so they accumulated one directory per
# run forever. Keep the newest few and drop the rest — the names are timestamps,
# so sorting them by name sorts them by age.
#
# Only directories whose names match the timestamp format are touched, so
# anything else parked in there by hand is left alone.
KEEP_BACKUPS=5
BACKUP_ROOT="$USER_HOME/.config-backups"

if [ -d "$BACKUP_ROOT" ]; then
    mapfile -t OLD_BACKUPS < <(
        find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
            | grep -E '^[0-9]{8}-[0-9]{6}' | sort -r | tail -n +$((KEEP_BACKUPS + 1))
    )
    for old in "${OLD_BACKUPS[@]}"; do
        rm -rf "${BACKUP_ROOT:?}/${old:?}"
        info "Pruned old config backup: $old"
    done
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
section "Config install complete"

if [ "$BACKED_UP_ANYTHING" = true ]; then
    info "Pre-existing configs backed up to $BACKUP_DIR"
else
    info "Nothing needed replacing — no backup taken"
fi
