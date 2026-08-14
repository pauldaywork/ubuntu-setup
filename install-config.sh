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

# ─── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${GREEN}══${NC} $* ${GREEN}══${NC}"; }

# ─── Copy dotfiles ────────────────────────────────────────────────────────────
section "Copying dotfiles"

# Existing files that would be overwritten are moved here (preserving their
# path relative to $HOME) instead of being left as .bak siblings, so a bad
# install can't get confused with a stray .bak file and the live config tree
# stays clean.
BACKUP_DIR="$USER_HOME/.config-backups/$(date +%Y%m%d-%H%M%S)"
BACKED_UP_ANYTHING=false

backup_existing() {
    local dst="$1"
    [ -e "$dst" ] || return 0
    local rel="${dst#"$USER_HOME"/}"
    local backup_dst="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$backup_dst")"
    cp -a "$dst" "$backup_dst"
    warn "Backed up existing: $dst → $backup_dst"
    BACKED_UP_ANYTHING=true
}

copy() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    backup_existing "$dst"
    cp "$src" "$dst"
    info "Copied $dst"
}

# For config files the *app* owns and rewrites as it gains features — DMS's
# settings.json above all. Its live file grows keys and climbs a configVersion
# with each release, while the copy in this repo is a snapshot from whenever
# update.sh last ran. Copying ours flat over the top deletes every key our
# snapshot has never heard of: on this machine that was 147 of them, including
# the display profiles and the whole battery section.
#
# So merge rather than replace. Our value wins for every key we actually carry
# (that's the point of installing), and anything only the live file has is left
# where it is.
#
# configVersion is deliberately *not* max()'d — it comes from our file, i.e. the
# older number. That makes DMS re-run its migrations over the merged result on
# next load, which is what forward-migrates the stale-shaped values our snapshot
# contributed (ours still carries the pre-v13 `*Pins` keys, which migration 13
# moves out to cache.json). Re-running those migrations over already-current
# keys is safe: each one is either guarded on a key that no longer exists or a
# plain delete.
#
# Only top-level keys are merged. Nested structures like barConfigs are replaced
# wholesale, which is right — the bar layout is exactly the thing being
# installed — and DMS defaults any per-bar key our snapshot predates.
merge_json() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"

    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        info "Copied $dst (no existing file to merge with)"
        return
    fi

    backup_existing "$dst"

    # stderr is dropped so a malformed live file reports as the warning below
    # rather than as a python traceback in the middle of the install output.
    if python3 - "$src" "$dst" 2>/dev/null <<'PYEOF'
import json, sys

src, dst = sys.argv[1], sys.argv[2]

with open(src) as f:
    ours = json.load(f)
with open(dst) as f:
    live = json.load(f)

merged = dict(live)
merged.update(ours)

with open(dst, "w") as f:
    json.dump(merged, f, indent=2)

kept = len(set(live) - set(ours))
print(f"{len(ours)} key(s) applied, {kept} live-only key(s) preserved")
PYEOF
    then
        info "Merged $dst"
    else
        # A live file that isn't valid JSON can't be merged into. It's already
        # backed up, so replacing it is recoverable and beats leaving the
        # machine with settings that were never installed.
        warn "Could not merge $dst (unreadable JSON?) — replacing it instead"
        cp "$src" "$dst"
    fi
}

# shell
copy "$DOTFILES/home/.bashrc"  "$USER_HOME/.bashrc"
copy "$DOTFILES/home/.profile" "$USER_HOME/.profile"

# taskwarrior
copy "$DOTFILES/home/.taskrc" "$USER_HOME/.taskrc"

# tmux
copy "$DOTFILES/home/.tmux.conf" "$USER_HOME/.tmux.conf"

# niri
copy "$DOTFILES/config/niri/config.kdl"                   "$USER_HOME/.config/niri/config.kdl"
copy "$DOTFILES/config/niri/create_named_workspace.sh"    "$USER_HOME/.config/niri/create_named_workspace.sh"
chmod +x "$USER_HOME/.config/niri/create_named_workspace.sh"
copy "$DOTFILES/config/niri/rename_workspace.sh"          "$USER_HOME/.config/niri/rename_workspace.sh"
chmod +x "$USER_HOME/.config/niri/rename_workspace.sh"
copy "$DOTFILES/config/niri/open_project_workspace.sh"     "$USER_HOME/.config/niri/open_project_workspace.sh"
chmod +x "$USER_HOME/.config/niri/open_project_workspace.sh"
copy "$DOTFILES/config/niri/default_workspace_name.sh"    "$USER_HOME/.config/niri/default_workspace_name.sh"
chmod +x "$USER_HOME/.config/niri/default_workspace_name.sh"
copy "$DOTFILES/config/niri/toggle-window-rules.sh"       "$USER_HOME/.config/niri/toggle-window-rules.sh"
chmod +x "$USER_HOME/.config/niri/toggle-window-rules.sh"
copy "$DOTFILES/config/niri/tmux-niri-session.sh"         "$USER_HOME/.config/niri/tmux-niri-session.sh"
chmod +x "$USER_HOME/.config/niri/tmux-niri-session.sh"
copy "$DOTFILES/config/niri/wallpaper-sync.sh"            "$USER_HOME/.config/niri/wallpaper-sync.sh"
chmod +x "$USER_HOME/.config/niri/wallpaper-sync.sh"

# taskwarrior shortcuts — task-lib.sh is sourced by the other three, not run,
# so it's the one file here that doesn't need the executable bit.
copy "$DOTFILES/config/niri/task-lib.sh"                  "$USER_HOME/.config/niri/task-lib.sh"
copy "$DOTFILES/config/niri/task-add.sh"                  "$USER_HOME/.config/niri/task-add.sh"
chmod +x "$USER_HOME/.config/niri/task-add.sh"
copy "$DOTFILES/config/niri/task-list.sh"                 "$USER_HOME/.config/niri/task-list.sh"
chmod +x "$USER_HOME/.config/niri/task-list.sh"
copy "$DOTFILES/config/niri/task-active.sh"               "$USER_HOME/.config/niri/task-active.sh"
chmod +x "$USER_HOME/.config/niri/task-active.sh"
copy "$DOTFILES/config/niri/window-rules/normal.kdl"      "$USER_HOME/.config/niri/window-rules/normal.kdl"
copy "$DOTFILES/config/niri/window-rules/focus.kdl"       "$USER_HOME/.config/niri/window-rules/focus.kdl"

# Seed the active window-rules profile only if one isn't already chosen,
# so re-running install doesn't reset an existing choice.
if [ ! -e "$USER_HOME/.config/niri/window-rules-active.kdl" ]; then
    ln -s "$USER_HOME/.config/niri/window-rules/focus.kdl" "$USER_HOME/.config/niri/window-rules-active.kdl"
    echo "focus" > "$USER_HOME/.config/niri/.window-rules-profile"
fi

# config.kdl carries an unconditional `include "dms/binds.kdl"`, and niri
# refuses to load a config whose include is missing — it falls back to its
# built-in defaults, which looks like "my keybinds vanished". So seed an empty
# stub when the file is absent. DMS overwrites it freely; our binds live in
# config.kdl's own binds block.
#
# This is not the same situation as the other dms/*.kdl includes. colors.kdl,
# alttab.kdl, outputs.kdl and cursor.kdl are written automatically on first
# launch (matugen templates, monitor profiles), and dms.service is a systemd
# user unit, so DMS starts and generates them even when niri fell back to its
# defaults — one login later they exist. Don't bother seeding those.
#
# binds.kdl is never written unprompted. In DMS's KeybindsService.qml the only
# writers are saveBind() and fixDmsBindsInclude(), both driven from the
# keybinds UI, and the repair path returns early when `dmsBindsIncluded` is
# set — which our include line is what makes true. The line that needs the
# file is the line that stops DMS from creating it, so without this stub a
# fresh machine has an invalid niri config on every login until someone
# happens to save a keybind through the DMS settings tab.
if [ ! -e "$USER_HOME/.config/niri/dms/binds.kdl" ]; then
    mkdir -p "$USER_HOME/.config/niri/dms"
    printf 'binds {\n\n}\n' > "$USER_HOME/.config/niri/dms/binds.kdl"
    info "Seeded empty $USER_HOME/.config/niri/dms/binds.kdl"
fi

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
    info "Applying laptop-specific niri config ($MACHINE_REASON)"
    copy "$DOTFILES/config/niri/dms/laptop.kdl" "$USER_HOME/.config/niri/dms/laptop.kdl"
    printf '\ninclude "dms/laptop.kdl"\n' >> "$USER_HOME/.config/niri/config.kdl"
else
    info "Skipping laptop-specific niri config ($MACHINE_REASON)"
fi

# systemd user units for the wallpaper pair. They're units rather than niri
# spawn-at-startup lines so that a crash is restarted instead of leaving the
# desktop bare until the next login, and so `systemctl --user status` can say
# what went wrong. graphical-session.target starts and stops them with niri.
copy "$DOTFILES/config/systemd/user/swww-daemon.service"    "$USER_HOME/.config/systemd/user/swww-daemon.service"
copy "$DOTFILES/config/systemd/user/wallpaper-sync.service" "$USER_HOME/.config/systemd/user/wallpaper-sync.service"

# `enable` alone is enough: graphical-session.target pulls them in at login.
# Starting them here would fail on a fresh machine that has no session yet
# (Requisite=graphical-session.target), so that's left to the next login —
# except when there *is* a session, where it saves a re-login.
if command -v systemctl &>/dev/null; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable swww-daemon.service wallpaper-sync.service 2>/dev/null \
        && info "Enabled swww-daemon + wallpaper-sync user units" \
        || warn "Could not enable the wallpaper user units (no systemd user session?)"
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        systemctl --user restart swww-daemon.service wallpaper-sync.service 2>/dev/null \
            && info "Started the wallpaper units" || true
    fi
fi

# fuzzel — picker theme for open_project_workspace.sh (fuzzel.ini itself is
# left alone; the picker passes this file with --config=)
copy "$DOTFILES/config/fuzzel/project-picker.ini" "$USER_HOME/.config/fuzzel/project-picker.ini"

# ghostty
copy "$DOTFILES/config/ghostty/config.ghostty" "$USER_HOME/.config/ghostty/config.ghostty"
sed -i "s|^command = .*|command = $USER_HOME/.config/niri/tmux-niri-session.sh|" \
    "$USER_HOME/.config/ghostty/config.ghostty"

# DankMaterialShell — merged, not copied, so a re-install doesn't roll the live
# settings back to whenever update.sh last ran. See merge_json above.
merge_json "$DOTFILES/config/DankMaterialShell/settings.json"        "$USER_HOME/.config/DankMaterialShell/settings.json"
sed -i "s|\"customThemeFile\": \".*\"|\"customThemeFile\": \"$USER_HOME/.config/DankMaterialShell/themes/peaceAndQuiet/theme.json\"|" \
    "$USER_HOME/.config/DankMaterialShell/settings.json"
merge_json "$DOTFILES/config/DankMaterialShell/plugin_settings.json" "$USER_HOME/.config/DankMaterialShell/plugin_settings.json"
copy "$DOTFILES/config/DankMaterialShell/firefox.css"          "$USER_HOME/.config/DankMaterialShell/firefox.css"
copy "$DOTFILES/config/DankMaterialShell/themes/peaceAndQuiet/theme.json" \
     "$USER_HOME/.config/DankMaterialShell/themes/peaceAndQuiet/theme.json"

# Our own DMS bar plugin. Third-party plugins are git-cloned by install.sh and
# left alone on re-runs; this one is versioned here, so it's copied every time
# like any other dotfile.
copy "$DOTFILES/config/DankMaterialShell/plugins/activetask/plugin.json" \
     "$USER_HOME/.config/DankMaterialShell/plugins/activetask/plugin.json"
copy "$DOTFILES/config/DankMaterialShell/plugins/activetask/ActiveTaskWidget.qml" \
     "$USER_HOME/.config/DankMaterialShell/plugins/activetask/ActiveTaskWidget.qml"

# VS Code settings (extensions are not installed here — see install.sh)
copy "$DOTFILES/config/Code/settings.json" "$USER_HOME/.config/Code/User/settings.json"

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

# The whole folder is installed, not just the active one, so the DMS picker has
# something to pick from — animated GIFs included, which swww is what actually
# renders (see config/niri/wallpaper-sync.sh).
WALLPAPER_DIR="$USER_HOME/Documents/Wallpapers"
mkdir -p "$WALLPAPER_DIR"

# A same-named file that differs is stale, not "already installed" — an edited
# or truncated copy, or one this machine picked up before the repo's version
# changed — so it gets replaced with the repo's, via copy() so the old one is
# backed up like any other config. Wallpapers this machine has that the repo
# doesn't are left alone; installing is not the same as pruning.
for wall in "$DOTFILES/wallpapers"/*; do
    [ -f "$wall" ] || continue
    name="$(basename "$wall")"
    # `active` is our own bookkeeping, not a wallpaper.
    [ "$name" = "active" ] && continue
    if ! cmp -s "$wall" "$WALLPAPER_DIR/$name"; then
        copy "$wall" "$WALLPAPER_DIR/$name"
    fi
done

# Which one to select on a fresh machine. update.sh rewrites this file from
# whatever DMS has live, so the repo tracks the choice without install-config.sh
# needing a hardcoded filename.
ACTIVE_WALLPAPER=""
if [ -s "$DOTFILES/wallpapers/active" ]; then
    ACTIVE_WALLPAPER="$(head -n1 "$DOTFILES/wallpapers/active")"
fi
if [ -z "$ACTIVE_WALLPAPER" ] || [ ! -f "$WALLPAPER_DIR/$ACTIVE_WALLPAPER" ]; then
    warn "wallpapers/active names no installed file — falling back to the first wallpaper"
    ACTIVE_WALLPAPER="$(cd "$WALLPAPER_DIR" && ls | head -n1)"
fi

WALLPAPER_DST="$WALLPAPER_DIR/$ACTIVE_WALLPAPER"

# Seed the DMS session wallpaper so one is selected on first launch.
#
# Only when nothing valid is selected already. This used to overwrite the path
# unconditionally, which meant re-running the installer to pick up an unrelated
# config change silently threw away whichever wallpaper you'd since chosen and
# put the repo's back. A wallpaper you picked on this machine is live state,
# like the window-rules profile seeded further up — the installer's job is to
# make sure there *is* one, not to have the last word on which.
#
# Paths go in through argv rather than being pasted into the source, so a quote
# or backslash in a filename can't end the string early.
DMS_SESSION="$USER_HOME/.local/state/DankMaterialShell/session.json"
mkdir -p "$(dirname "$DMS_SESSION")"

if [ -z "$ACTIVE_WALLPAPER" ]; then
    warn "No wallpapers installed — leaving the DMS session wallpaper alone"
else
    SESSION_RESULT=$(python3 - "$DMS_SESSION" "$WALLPAPER_DST" <<'PYEOF'
import json, os, sys

session_path, wallpaper = sys.argv[1], sys.argv[2]

try:
    with open(session_path) as f:
        session = json.load(f)
except FileNotFoundError:
    session = {}
except (OSError, ValueError):
    # An unreadable session file is DMS's to repair — it rewrites the whole
    # thing from its own defaults on next launch. Replacing it here would throw
    # away every other bit of session state it holds.
    print("!Could not read the DMS session file — leaving it untouched")
    raise SystemExit

current = session.get("wallpaperPath", "")
if current and os.path.isfile(current):
    print(f"Wallpaper already selected, leaving it alone: {os.path.basename(current)}")
else:
    session["wallpaperPath"] = wallpaper
    with open(session_path, "w") as f:
        json.dump(session, f, indent=2)
    print(f"DMS session wallpaper set to {os.path.basename(wallpaper)}")
PYEOF
)
    # A leading "!" marks the warning case; everything else is routine.
    case "$SESSION_RESULT" in
        "!"*) warn "${SESSION_RESULT#!}" ;;
        *)    info "$SESSION_RESULT" ;;
    esac
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
section "Config install complete"

if [ "$BACKED_UP_ANYTHING" = true ]; then
    info "Pre-existing configs backed up to $BACKUP_DIR"
fi
