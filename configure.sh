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
for _lib in common paths manifest; do
    if [ ! -f "$DOTFILES/lib/$_lib.sh" ]; then
        echo "Missing $DOTFILES/lib/$_lib.sh — run this from a full clone of the repo" >&2
        exit 1
    fi
done
# shellcheck source=/dev/null
source "$DOTFILES/lib/common.sh"
source "$DOTFILES/lib/paths.sh"
# For HERDR_WORKTRUNK_REF, the one pin configure.sh installs from.
source "$DOTFILES/lib/manifest.sh"

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
        # Deployed only on that machine type, and MACHINE_TYPE is not settled
        # until below, so those rows are applied there instead.
        laptop|desktop) ;;
        *) warn "lib/paths.sh: unknown kind '$KIND' for $REPO_PATH" ;;
    esac
done

# Machine-type config: laptop.kdl + laptop.jsonc on laptops, desktop.kdl (the
# desk's monitors and their 4K modes) on desktops.
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

info "Machine type: $MACHINE_TYPE ($MACHINE_REASON)"
# Deploy this machine type's rows, and remove the other type's. From the table
# rather than spelled out again, so doctor.sh and capture/ cannot end up
# disagreeing with this about which files those are.
#
# Removing matters because a machine can change type (--laptop / --desktop).
# niri's leftover would sit unread once its include is gone, but waybar's
# config.jsonc includes laptop.jsonc whenever it exists, and a stale one brings
# the battery module back — the one that aborts the bar on a mouse replug. They
# are plain copies of repo files, so nothing is lost.
for _row in "${DOTFILES_MAP[@]}"; do
    map_entry "$_row"
    case "$KIND" in laptop|desktop) ;; *) continue ;; esac
    if [ "$KIND" = "$MACHINE_TYPE" ]; then
        copy "$DOTFILES/$REPO_PATH" "$USER_HOME/$HOME_PATH"
    elif [ -e "$USER_HOME/$HOME_PATH" ]; then
        rm -f "$USER_HOME/$HOME_PATH"
        info "Removed ~/$HOME_PATH ($KIND only)"
    fi
done


# niri
# config.kdl is assembled before being installed — the repo's copy plus the
# include for this machine type, laptop.kdl or desktop.kdl — so copy() can
# compare the finished article and skip a file that already matches. Appending
# after copying meant the live file could never equal the repo's, so every run
# rewrote it and archived the old one, which is most of how ~/.config-backups
# filled up.
NIRI_CONFIG_TMP=$(mktemp)
cat "$DOTFILES/config/niri/config.kdl" > "$NIRI_CONFIG_TMP"
printf '\ninclude "%s.kdl"\n' "$MACHINE_TYPE" >> "$NIRI_CONFIG_TMP"
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
    # The bar. The waybar package's own unit, which Ubuntu enables system-wide
    # already; enabled here too so the bar does not hang on a package preset.
    # See the note where config.kdl used to spawn it.
    systemctl --user enable waybar.service 2>/dev/null \
        && info "Enabled the waybar user unit" \
        || warn "Could not enable the waybar user unit (no systemd user session?)"
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        systemctl --user restart swww-daemon.service 2>/dev/null \
            && info "Started swww-daemon" || true
    fi
fi

# ghostty
# No post-processing any more. Its `command =` line used to be rewritten here to
# `niritasks tmux-session`, a wrapper that put each window in a tmux session in
# the workspace's ~/Projects folder. Now ghostty runs a plain login shell, and
# whoever asks for the window picks the folder: Mod+Return runs
# `niritasks terminal`, which opens one in ~/Projects/<workspace>.
#
# ghostty runs as one long-lived process (gtk-single-instance) that reads its
# config once at startup, so every new window keeps the old config until it is
# told to reload — which, when the old config named a command that has since
# gone, means new windows that fail to start at all. SIGUSR2 is its reload
# signal, from 1.2 on. Older versions don't handle it, and SIGUSR2's default
# action is to terminate, so check first.
if pgrep -u "$USER" -x ghostty >/dev/null; then
    GHOSTTY_VERSION=$(ghostty --version 2>/dev/null | sed -n 's/^Ghostty \([0-9.]*\).*/\1/p')
    if [ -n "$GHOSTTY_VERSION" ] \
       && [ "$(printf '%s\n' 1.2 "$GHOSTTY_VERSION" | sort -V | head -1)" = 1.2 ]; then
        pkill -USR2 -u "$USER" -x ghostty && info "Reloaded ghostty's config"
    else
        warn "ghostty ${GHOSTTY_VERSION:-(unknown version)} can't reload by signal — press ctrl+shift+, in a ghostty window"
    fi
fi

# herdr-worktrunk
# The plugin is installed here rather than as a managed file: herdr keeps its
# own checkout and records which commit it came from, and installing is the one
# way to get both. Pinned in lib/manifest.sh; reinstalled only when the pin
# moves. herdr is installed by hand, so without it this is skipped.
if command -v herdr >/dev/null; then
    installed_ref=$(herdr plugin list --json 2>/dev/null \
        | jq -r '.result.plugins[]? | select(.plugin_id == "worktrunk") | .source.resolved_commit' 2>/dev/null)
    if [ "$installed_ref" = "$HERDR_WORKTRUNK_REF" ]; then
        info "herdr-worktrunk already at ${HERDR_WORKTRUNK_REF:0:12}"
    elif herdr plugin install devashish2203/herdr-worktrunk --ref "$HERDR_WORKTRUNK_REF" -y >/dev/null 2>&1; then
        info "Installed herdr-worktrunk ${HERDR_WORKTRUNK_REF:0:12}"
    else
        warn "Could not install herdr-worktrunk — worktree keys in herdr will do nothing"
    fi
fi

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
    # tmux, dropped: herdr is the multiplexer now, one session per project
    # workspace, and plain terminals are plain shells. ~/.tmux (TPM and its
    # plugins) is left alone — it was never a managed file.
    ".tmux.conf"
    # ghostty's legacy config file, which predates config.ghostty and was never
    # managed. ghostty loads both, so it was quietly setting working-directory
    # to ~/Code and a DankMaterialShell theme; what was worth keeping from it
    # now lives in config/ghostty/config.ghostty, colours included, so the
    # theme DMS generated goes with it.
    ".config/ghostty/config"
    ".config/ghostty/themes/dankcolors"
    # Its fuzzel theme too — niri-tasks installs its own as picker.ini.
    ".config/fuzzel/project-picker.ini"
    # The window-rules toggle moved in beside the profiles it switches between,
    # so it installs to window-rules/toggle.sh now.
    ".config/niri/toggle-window-rules.sh"
    # Dropping DMS moved our laptop binds out of the directory DMS generated
    # into. config.kdl includes "laptop.kdl" now, so the old copy is dead — and
    # worse than dead, since it looks exactly like a live config file.
    ".config/niri/dms/laptop.kdl"
    # A single-popup guard that wrapped the launcher and the wallpaper picker.
    # It worked by holding an flock for the popup's lifetime, and flock holds its
    # lock through a file descriptor that every app fuzzel launches inherits — so
    # opening anything from the launcher kept the lock until that app was closed,
    # and the shortcuts stayed dead meanwhile. fuzzel already refuses to run
    # twice on its own, so the wrapper was buying nothing for the cost.
    ".config/niri/popup-guard.sh"

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

# The niri config DMS generated: colors.kdl (matugen's palette), alttab.kdl,
# layout.kdl, wpblur.kdl, cursor.kdl, binds.kdl, and the outputs.kdl symlink into
# profiles/. config.kdl stopped including any of it, and the one file in there
# that was ever ours moved out to ~/.config/niri/laptop.kdl.
#
# Left alone these are worse than clutter, which is the whole reason the sweep
# above exists: six .kdl files sitting in ~/.config/niri/dms/ are indis-
# tinguishable from live config to anyone reading the directory, including you
# in six months. Only `dms/laptop.kdl` was being removed before, which left the
# directory present and looking load-bearing.
if [ -d "$USER_HOME/.config/niri/dms" ] && ! pkg_installed dms; then
    rm -rf "$USER_HOME/.config/niri/dms"
    STALE_REMOVED=$((STALE_REMOVED + 1))
    info "Removed the leftover ~/.config/niri/dms tree"
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

# The bar's accent colour. wallpaper-apply.sh derives it from the wallpaper on
# every paint, but style.css imports it unconditionally and waybar exits over an
# import it cannot open — no bar at all — so it has to exist before waybar first
# starts, which can be before swww-daemon has painted anything. White until then.
# Never overwritten: past the first paint it is the wallpaper's, not ours.
WALLPAPER_COLORS="$USER_HOME/.config/waybar/wallpaper-colors.css"
if [ ! -f "$WALLPAPER_COLORS" ]; then
    mkdir -p "$(dirname "$WALLPAPER_COLORS")"
    printf '@define-color wallpaper_accent #ffffff;\n' > "$WALLPAPER_COLORS"
    info "Seeded the bar accent colour (white until a wallpaper is painted)"
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
