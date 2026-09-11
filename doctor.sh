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

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── shared helpers + the package/version manifest ────────────────────────────
# The manifest is the point: this script used to keep its own copy of the
# package list with a comment asking whoever edited install.sh to remember to
# edit this one too.
for lib in lib/common.sh lib/manifest.sh lib/paths.sh; do
    if [ ! -f "$DOTFILES/$lib" ]; then
        echo "Missing $DOTFILES/$lib — run this from a full clone of the repo" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$DOTFILES/$lib"
done

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
#
# APT_PACKAGES and SNAP_PACKAGES come from lib/manifest.sh, the same lists
# install.sh installs from. APT_BUILD_PACKAGES is deliberately not checked: see
# the note there.
section "Checking installation completeness"

MISSING_APT=()
for pkg in "${APT_PACKAGES[@]}"; do
    pkg_installed "$pkg" || MISSING_APT+=("$pkg")
done
if [ "${#MISSING_APT[@]}" -eq 0 ]; then
    ok "All apt packages installed"
else
    issue "Missing apt package(s): ${MISSING_APT[*]}"
    note "  Install with: sudo apt install -y ${MISSING_APT[*]}"
fi

if pkg_installed obsidian; then
    ok "obsidian installed"
else
    issue "obsidian not installed"
    note "  See the OBSIDIAN_VERSION .deb URL in install.sh"
fi

if pkg_installed docker-ce; then
    issue "docker-ce is installed and conflicts with docker.io (install.sh uses Ubuntu's docker.io)"
    note "  Remove with: sudo apt remove -y docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io docker-buildx-plugin docker-compose-plugin"
fi

if id -nG "$(id -un)" | grep -qw docker; then
    ok "In the docker group"
else
    issue "Not in the docker group — docker commands will need sudo"
    note "  Fix with: sudo usermod -aG docker $(id -un)   (then log out and back in)"
fi

if systemctl is-active --quiet docker; then
    ok "docker service running"
else
    issue "docker service not running"
    note "  Start with: sudo systemctl enable --now docker"
fi

# mako used to be checked here in the negative — "installed but no longer used,
# remove it" — because DMS owned notifications and the two fought over the
# socket. It is in APT_PACKAGES now, so the loop above checks it like any other
# package and a second opinion here would only contradict it.

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

# ─── config drift ─────────────────────────────────────────────────────────────
# Every mapped file from lib/paths.sh, checked against the repo. This is the
# third consumer of that table: configure.sh deploys it, capture/ pulls back the
# handful a GUI owns, and here we ask whether the two still agree.
#
# Only mismatches are reported. A machine in sync says so in one line rather
# than eighteen, which keeps the interesting output visible.
# Files configure.sh rewrites *after* copying, so the live copy is meant to
# differ from the repo's and comparing them would report drift forever:
#
#   ghostty  its `command =` line becomes `wt tmux-session` when wt is on PATH
#
# Presence is still checked; only the content comparison is skipped.
is_post_processed() {
    case "$1" in
        .config/ghostty/config.ghostty) return 0 ;;
        *) return 1 ;;
    esac
}

MISSING=0
DRIFTED=0
CHECKED=0
MACHINE_TYPE_NOW="desktop"
[ -f "$HOME/.config/niri/.machine-type" ] && MACHINE_TYPE_NOW="$(head -n1 "$HOME/.config/niri/.machine-type")"

for _row in "${DOTFILES_MAP[@]}"; do
    map_entry "$_row"
    _live="$HOME/$HOME_PATH"
    _repo="$DOTFILES/$REPO_PATH"

    # Laptop-only rows are not expected to exist on a desktop.
    [ "$KIND" = laptop ] && [ "$MACHINE_TYPE_NOW" != laptop ] && continue

    CHECKED=$((CHECKED + 1))
    if [ ! -f "$_live" ]; then
        issue "Not installed: ~/$HOME_PATH"
        note "  Install with: bash configure.sh"
        MISSING=$((MISSING + 1))
    elif ! is_post_processed "$HOME_PATH" && ! cmp -s "$_live" "$_repo"; then
        # Every row is a plain copy now, so every row is expected to match
        # byte-for-byte. The `merge` exemption that used to be here covered
        # DankMaterialShell's two settings files, whose live copies legitimately
        # carried keys the repo's snapshot had never heard of.
        note "Differs from the repo: ~/$HOME_PATH"
        DRIFTED=$((DRIFTED + 1))
    fi
done

if [ "$MISSING" -eq 0 ] && [ "$DRIFTED" -eq 0 ]; then
    ok "All $CHECKED mapped config files present and matching the repo"
elif [ "$MISSING" -eq 0 ]; then
    ok "All $CHECKED mapped config files present ($DRIFTED differ — bash configure.sh to deploy the repo's version over them)"
fi

# config.kdl is not in the table — it is assembled with the laptop include
# appended — so the count above does not cover it. Check it here rather than
# leave "all N match" implying the most important file was among them. Same
# strip capture/niri.sh does, so the comparison is like for like.
if [ -f "$HOME/.config/niri/config.kdl" ]; then
    NIRI_CMP=$(mktemp)
    # Two things make a naive comparison wrong here: configure.sh appends the
    # laptop include, and the repo file happens to end in blank lines while the
    # appended one does not. Normalise both sides by dropping the include and
    # every trailing blank, or this reports drift on every laptop forever.
    strip_kdl() {
        grep -v '^include "laptop.kdl"$' "$1" \
            | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba'
    }
    NIRI_REPO_CMP=$(mktemp)
    strip_kdl "$HOME/.config/niri/config.kdl" > "$NIRI_CMP" || true
    strip_kdl "$DOTFILES/config/niri/config.kdl" > "$NIRI_REPO_CMP" || true
    if cmp -s "$NIRI_CMP" "$NIRI_REPO_CMP"; then
        ok "niri config.kdl matches the repo"
    else
        note "Differs from the repo: ~/.config/niri/config.kdl"
    fi
    rm -f "$NIRI_CMP" "$NIRI_REPO_CMP"
fi

# The executable bit is set by configure.sh, not carried in git for the
# destination, so a file restored by hand or from a backup can be present,
# matching, and still not runnable.
for _row in "${DOTFILES_MAP[@]}"; do
    map_entry "$_row"
    [ "$KIND" = exec ] || continue
    if [ -f "$HOME/$HOME_PATH" ] && [ ! -x "$HOME/$HOME_PATH" ]; then
        issue "Not executable: ~/$HOME_PATH"
        note "  Fix with: chmod +x ~/$HOME_PATH"
    fi
done

# The workspace-task system lives in its own repo now. Delegate to its doctor
# rather than duplicating the checks here — it knows what it installed, and this
# repo works fine without it.
if command -v wt >/dev/null; then
    ok "wt installed ($(wt --version 2>/dev/null || echo 'version unknown'))"

    # niri refuses to load a config whose include is missing, so this one is
    # fatal to the whole session rather than just to the task binds.
    if [ -e "$HOME/.config/niri/niri-tasks.kdl" ]; then
        ok "niri-tasks include present"
    else
        issue "Missing ~/.config/niri/niri-tasks.kdl — niri will refuse to load its config"
        note "  Seed the stub with: bash configure.sh"
    fi

    if systemctl --user is-active --quiet niri-tasks.service; then
        ok "Active-task overlay running"
    else
        issue "niri-tasks.service is not running — the active-task overlay will not appear"
        note "  Start it with: systemctl --user start niri-tasks"
    fi
else
    note "wt not installed — Mod+Alt+T/L/P and the active-task overlay are absent"
    note "  Install with: https://github.com/pauldaywork/niri-tasks"

    # The stub still has to exist, or niri will not load at all.
    if [ ! -e "$HOME/.config/niri/niri-tasks.kdl" ]; then
        issue "Missing ~/.config/niri/niri-tasks.kdl — niri will refuse to load its config"
        note "  Seed the stub with: bash configure.sh"
    fi
fi

# Files this repo used to install and no longer does. Deleting them from the
# repo doesn't delete them from a machine that already has them, and a stale
# script is worse than clutter — it's indistinguishable from a live one.
#
# configure.sh does the removing; this only reports, like everything else here.
STALE_ON_DISK=()
for rel in \
    ".config/niri/task-lib.sh" ".config/niri/task-tag.sh" ".config/niri/task-active.sh" \
    ".config/niri/task-list.sh" ".config/niri/task-add.sh" ".config/niri/task-add-text.sh" \
    ".config/niri/task-get-text.sh" ".config/niri/task-edit-text.sh" \
    ".config/niri/task-get-notes.sh" ".config/niri/task-annotate-text.sh" \
    ".config/niri/create_named_workspace.sh" ".config/niri/rename_workspace.sh" \
    ".config/niri/default_workspace_name.sh" ".config/niri/open_project_workspace.sh" \
    ".config/niri/tmux-niri-session.sh" ".config/niri/toggle-window-rules.sh" \
    ".config/fuzzel/project-picker.ini" ".config/niri/dms/laptop.kdl"
do
    [ -e "$HOME/$rel" ] && STALE_ON_DISK+=("$rel")
done
[ -d "$HOME/.config/DankMaterialShell/plugins/activetask" ] && \
    STALE_ON_DISK+=(".config/DankMaterialShell/plugins/activetask")

if [ "${#STALE_ON_DISK[@]}" -gt 0 ]; then
    issue "${#STALE_ON_DISK[@]} file(s) this repo no longer installs are still on disk"
    for rel in "${STALE_ON_DISK[@]}"; do
        note "    ~/$rel"
    done
    note "  Remove them with: bash configure.sh"
else
    ok "No leftovers from past moves"
fi

# Wallpapers. Three things have to agree or the desktop goes black: swww has to
# be installed and running, DMS's own wallpaper layer has to stay disabled (it
# would paint a still frame over the top), and wallpaper-sync.sh has to be alive
# to carry picker changes across.
if command -v swww &>/dev/null && command -v swww-daemon &>/dev/null; then
    ok "swww installed ($(swww --version 2>/dev/null))"
else
    issue "swww not installed — animated wallpapers won't render"
    note "  Install with: cargo install --git https://github.com/LGFae/swww --tag $SWWW_VERSION --locked swww swww-daemon"
fi

# Both run as systemd user units, so ask systemd rather than looking for the
# processes: it distinguishes "never installed" from "enabled but crashed", and
# knows which one to tell you to look at.
for unit in swww-daemon wallpaper-sync; do
    if [ ! -f "$HOME/.config/systemd/user/$unit.service" ]; then
        issue "$unit.service not installed"
        note "  Install with: bash configure.sh"
    elif ! systemctl --user is-enabled --quiet "$unit.service" 2>/dev/null; then
        issue "$unit.service is not enabled — it won't start at next login"
        note "  Enable with: systemctl --user enable --now $unit.service"
    elif systemctl --user is-active --quiet "$unit.service" 2>/dev/null; then
        ok "$unit.service running"
    else
        issue "$unit.service is enabled but not running"
        note "  Look at why with: systemctl --user status $unit.service"
        note "  Start with: systemctl --user start $unit.service"
    fi
done

# The end-to-end check: what swww has on screen should be what DMS thinks is
# selected. Those two diverging is the whole failure mode this setup guards
# against — a paint missed while the daemon was down leaves the screen on swww's
# cached image forever — and nothing else here would catch it. Skipped when
# per-monitor wallpapers are on, since then there's no single right answer.
DMS_SESSION="$HOME/.local/state/DankMaterialShell/session.json"
if [ -f "$DMS_SESSION" ] && command -v swww &>/dev/null \
   && systemctl --user is-active --quiet swww-daemon.service 2>/dev/null; then
    WANTED=$(python3 -c "
import json, sys
d = json.load(open('$DMS_SESSION'))
print('' if d.get('perMonitorWallpaper') else d.get('wallpaperPath', ''))" 2>/dev/null || true)
    ON_SCREEN=$(swww query 2>/dev/null | sed -n 's/.*currently displaying: image: //p' | sort -u)

    if [ -z "$WANTED" ]; then
        :   # per-monitor wallpapers, or nothing selected — nothing to compare
    elif [ -z "$ON_SCREEN" ]; then
        issue "swww isn't displaying an image — the desktop background is blank"
        note "  Repaint with: systemctl --user restart swww-daemon.service"
    elif [ "$ON_SCREEN" = "$WANTED" ]; then
        ok "Wallpaper on screen matches DMS's selection ($(basename "$WANTED"))"
    else
        issue "Wallpaper on screen isn't the one DMS has selected"
        note "  DMS wants:  $WANTED"
        note "  On screen:  $ON_SCREEN"
        note "  Repaint with: systemctl --user restart swww-daemon.service"
    fi
fi

DMS_SETTINGS="$HOME/.config/DankMaterialShell/settings.json"
if [ -f "$DMS_SETTINGS" ]; then
    if python3 -c "import json,sys; d=json.load(open('$DMS_SETTINGS')); sys.exit(0 if d.get('screenPreferences',{}).get('wallpaper') == [] else 1)" 2>/dev/null; then
        ok "DMS built-in wallpapers disabled (swww owns the background)"
    else
        issue "DMS built-in wallpapers are enabled — they'll cover swww with a still frame"
        note "  Fix in Settings → Wallpaper → Disable Built-in Wallpapers, or re-run configure.sh"
    fi
fi

# Laptop binds. configure.sh replaces config.kdl wholesale and appends the
# laptop include afterwards, so a re-run that decides this machine isn't a laptop
# takes the display and workspace binds away with no error — worth noticing here
# rather than the next time you reach for a shortcut that's gone.
NIRI_CONFIG="$HOME/.config/niri/config.kdl"
if [ -f "$NIRI_CONFIG" ]; then
    # A machine deliberately installed as --desktop records that, and is not
    # nagged about the binds it asked not to have.
    MACHINE_TYPE=""
    [ -f "$HOME/.config/niri/.machine-type" ] && MACHINE_TYPE="$(head -n1 "$HOME/.config/niri/.machine-type")"

    HAS_BATTERY=false
    [ "$MACHINE_TYPE" != "desktop" ] && compgen -G "/sys/class/power_supply/BAT*" > /dev/null && HAS_BATTERY=true
    HAS_INCLUDE=false
    grep -q '^include "laptop.kdl"$' "$NIRI_CONFIG" && HAS_INCLUDE=true

    if [ "$HAS_BATTERY" = true ] && [ "$HAS_INCLUDE" = false ]; then
        issue "This machine has a battery but config.kdl doesn't include laptop.kdl"
        note "  The display and workspace binds in it are missing"
        note "  Fix with: bash configure.sh --laptop"
    elif [ "$HAS_INCLUDE" = true ] && [ ! -f "$HOME/.config/niri/laptop.kdl" ]; then
        issue "config.kdl includes laptop.kdl but that file is missing — niri won't load the config"
        note "  Fix with: bash configure.sh --laptop"
    elif [ "$HAS_INCLUDE" = true ]; then
        ok "Laptop niri config included"
    fi
fi

# ─── 2. Dangling PATH / env references in dotfiles ───────────────────────────
# Finds lines like `export FOO_DIR="$HOME/x"` or `. "$HOME/x/env"` and checks
# the path they point at still exists. Catches the general case of "a tool
# got moved/reinstalled and the shell config was never updated" without
# needing to know about every tool in advance.
#
# A missing path is only a problem when the line reads it unconditionally.
# The stock Ubuntu .bashrc guards its optional includes:
#
#   if [ -f ~/.bash_aliases ]; then
#       . ~/.bash_aliases
#   fi
#
# so the file is allowed to be absent. Lines guarded by a file test — on the
# same line (`[ -f x ] && . x`) or on one of the few lines above — are skipped.
section "Checking for dangling PATH/env references"

DANGLING=0
for rc in "${RC_FILES[@]}"; do
    [ -f "$rc" ] || continue
    mapfile -t rc_lines < "$rc"
    for i in "${!rc_lines[@]}"; do
        line="${rc_lines[$i]}"
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+[A-Z_]+=|\.[[:space:]]|source[[:space:]]) ]] || continue
        raw_path=$(echo "$line" | grep -oE '(\$HOME|~|/home/[A-Za-z0-9._-]+)(/[A-Za-z0-9._-]+)+' | head -1)
        [ -z "$raw_path" ] && continue
        expanded="${raw_path/#\~/$HOME}"
        expanded="${expanded/#\$HOME/$HOME}"
        [ -e "$expanded" ] && continue

        # Look at this line and the 3 above it for a `[ -f/-e/-r/-s <path> ]`
        # test naming the same path — that makes the reference conditional.
        guarded=false
        start=$((i > 3 ? i - 3 : 0))
        for ((j = start; j <= i; j++)); do
            if [[ "${rc_lines[$j]}" == *"["*"-"[fersx]" "*"$raw_path"* ]]; then
                guarded=true
                break
            fi
        done
        $guarded && continue

        issue "$rc references '$expanded' but it doesn't exist:"
        echo "      $line"
        DANGLING=$((DANGLING + 1))
    done
done
[ "$DANGLING" -eq 0 ] && ok "No dangling references found"

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
check_duplicate "ghostty"      "ghostty" 'pkg_installed ghostty'

# ─── 5. Summary ───────────────────────────────────────────────────────────────
section "Summary"
if [ "$ISSUES" -eq 0 ]; then
    ok "No issues found"
else
    note "$ISSUES issue(s) found."
    # --fix only covers the NVM_DIR check; every other check here is report-only
    # by design (see the header comment), so don't advertise more than it does.
    $FIX || note "Re-run with --fix to interactively repair a misconfigured NVM_DIR."
fi
