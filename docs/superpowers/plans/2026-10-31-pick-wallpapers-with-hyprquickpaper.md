# Pick Wallpapers with hyprquickpaper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mod+Alt+B opens the hyprquickpaper Quickshell picker instead of the fuzzel list in `wallpaper/pick.sh`. swww still paints, and the choice still lands in `~/.config/niri/wallpaper-active`.

**Architecture:** `install.sh` fetches upstream hyprquickpaper into `~/.config/quickshell/hyprquickpaper` at a commit pinned in `lib/manifest.sh`, then applies one repo patch to its `commands.sh`. `configure.sh` deploys the repo's own `config.json` over upstream's through a normal `lib/paths.sh` row. Its `custom_command` writes the pick into `wallpaper-active` and runs `wallpaper-apply.sh`, so the GIF Nearest filter, the retries and login persistence all stay where they are. Mod+Alt+Ctrl+B (next wallpaper) moves out of `pick.sh` into its own `wallpaper/next.sh`, and then the fuzzel picker and `wallpaper/picker.ini` are deleted.

**Tech Stack:** bash, git, Quickshell (`qs`, from the danklinux PPA), Qt 6 QML modules, ImageMagick and ffmpeg (hyprquickpaper's thumbnailer), swww, niri KDL.

**Spec:** Taskwarrior task `a26982d6-b4c6-419c-99b7-28bfd69e8893`. Its description and notes are the spec (`task rc.json.array=on a26982d6-b4c6-419c-99b7-28bfd69e8893 export`). There is no separate spec file.

## Global Constraints

- Upstream: `https://github.com/ujjalsigdel/hyprquickpaper`. It has no tags. Pin the full commit `0c2de83fe2734ea938ea06727b2722f275f7c412` (HEAD at refine time) as `HYPRQUICKPAPER_REF` in `lib/manifest.sh`.
- Install location: `~/.config/quickshell/hyprquickpaper` (upstream's own canonical path). Launch: `qs -n -p ~/.config/quickshell/hyprquickpaper`.
- The repo's `config.json` is authoritative and deployed over the clone (ADR 0001, one-way deploy). `wallpaper_path` is `~/Documents/Wallpapers/`.
- `custom_command` writes `$WALLPAPER` into `~/.config/niri/wallpaper-active` and runs `~/.config/niri/wallpaper-apply.sh`.
- Keep `gif` in `video_extensions` so GIFs are listed and thumbnailed. Patch `commands.sh` so every pick goes to `custom_command` and never to mpvpaper.
- Keep Mod+Alt+Ctrl+B (next wallpaper), moved into its own small script. Delete the fuzzel picker (`wallpaper/pick.sh`) and `wallpaper/picker.ini`.
- Add `quickshell` and `imagemagick` to the manifest. Rebind Mod+Alt+B in `config/niri/config.kdl`. Update `doctor.sh`.
- The layout (`active_layout`) is tried live and chosen by the user (Task 4).
- Out of scope: video wallpapers and mpvpaper, theming hooks (`post_apply`), switching swww to awww.
- Commits: Conventional Commits (`<type>(<scope>): <summary>`, imperative, lowercase, ≤72 chars), ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Facts the engineer needs

- **No test suite.** This repo has no test runner. Earlier plans keep their check scripts in a scratch directory, uncommitted. Do the same: set `SCRATCH=$(mktemp -d)` once per task and reuse it. Run every command from the worktree root.
- **How deployment works.** `lib/paths.sh`'s `DOTFILES_MAP` rows are `<repo path>|<path under $HOME>|<kind>` (`copy` or `exec`). `configure.sh` copies each row out. `doctor.sh` reports a live file that differs from the repo, and checks that every row's basename appears in the `## Repo structure` code block of `README.md`. It also checks the other way: every file named in that block must still exist. So **every added or deleted row must be matched in the README tree, or `doctor.sh` fails.**
- **How hyprquickpaper works** (source read at the pin, 2026-10-31):
  - `shell.qml` loads the layout named by `config.json`'s `active_layout`. That layout is a wlr-layer-shell overlay (namespace `hyprquickpaper`, exclusive keyboard focus). It lists `wallpaper_path` with a `FolderListModel` whose filters are `*.png *.jpg *.jpeg` plus `*.<ext>` for each entry in `video_extensions`.
  - On open, every layout runs `bash cache.sh <shell dir>` detached. That makes thumbnails in `cache_path`. PNG/JPG go through ImageMagick (`magick`, else `convert`) and keep their filename. Anything in `video_extensions` goes through ffmpeg, which grabs a frame at `-ss 5`, falling back to `-ss 1` and then frame 0. The frame is saved as `<name>.hq.jpg`, then ImageMagick shrinks it to `<name>.jpg`. So **a GIF's thumbnail needs both ffmpeg and ImageMagick.** Checked on this repo's GIFs: `chill.gif` yields a frame at `-ss 5`, and `moon.gif`, `sunset_live.gif` and `still_on_by_kirokaze_dcsm2x8.gif` at `-ss 1`.
  - On Enter, the layout runs `bash commands.sh <path>` detached and quits. `commands.sh` kills mpvpaper, then **sends any `video_extensions` file to mpvpaper before looking at `custom_command` at all**. That is what the patch changes. For everything else it runs `custom_command` through `bash -c`, with `$WALLPAPER` in the environment. Its output goes nowhere visible.
  - `commands.sh` also writes `~/.cache/hyprquickpaper/current_wallpaper`, so the picker opens on the last pick.
  - No network calls. The only processes it starts are `cache.sh`, `commands.sh` and, from `settings.qml`, `set-layout.sh`.
  - `settings.qml` (the layout switcher) runs `set-layout.sh`, which **rewrites the live `config.json`**. So switching layouts there makes `doctor.sh` report drift. The layout belongs in the repo's file.
- **QML modules.** The `quickshell` package (danklinux PPA, 0.3.x) depends on the Qt libraries but not on the QML modules the layouts import. Across `layouts/*.qml` and `settings.qml` those are `QtQuick`, `QtQuick.Controls`, `QtQuick.Effects`, `QtQuick.Shapes` (one layout), `Qt.labs.folderlistmodel` (every layout) and `Qt5Compat.GraphicalEffects` (10 of 14 layouts). On Ubuntu 26.04 these are `qml6-module-qtquick-controls`, `qml6-module-qtquick-effects`, `qml6-module-qtquick-shapes`, `qml6-module-qt-labs-folderlistmodel` and `qml6-module-qt5compat-graphicaleffects`. All but the last are installed here only by chance, and `qml6-module-qt5compat-graphicaleffects` is **not installed** here at all. Name all five so any layout works.
- **This machine today:** `quickshell` 0.3.0 is installed. `imagemagick` and `qml6-module-qt5compat-graphicaleffects` are not, and `~/.config/quickshell` does not exist. Installing apt packages needs sudo. Ask the user to run the `sudo apt install …` line themselves with the `!` prefix.
- **niri `spawn` vs `spawn-sh`.** `spawn` only expands `~` in its first argument, so the bind uses `spawn-sh "qs -n -p ~/.config/quickshell/hyprquickpaper"`. `-n` (`--no-duplicate`) is Quickshell's own guard, so a second press while the picker is open does nothing. Don't add a flock: see the repo's history on fuzzel popups. `shortcuts/build.py` already handles `spawn-sh` binds.
- **Thumbnail name clash (known, accepted).** A GIF's thumbnail is `<name>.jpg` in the same cache as JPG thumbnails, so `x.gif` and `x.jpg` would share one. Nothing in the collection clashes today. The README notes it.
- **WebP is not listed** by the picker (it isn't in the filters). Nothing in `wallpaper/images/` is WebP. `apply.sh` still paints WebP if one is selected by hand. The `webp` apt package existed only for `pick.sh`'s thumbnails, so it goes in Task 3.

## File map

| File | Change | Task |
|---|---|---|
| `wallpaper/next.sh` | Create: Mod+Alt+Ctrl+B, the next wallpaper | 1 |
| `wallpaper/hyprquickpaper.json` | Create: the deployed `config.json` | 2 |
| `wallpaper/hyprquickpaper.patch` | Create: the `commands.sh` patch | 2 |
| `lib/paths.sh` | Add the `next.sh` and `hyprquickpaper.json` rows, drop the `pick.sh` and `picker.ini` rows | 1, 2, 3 |
| `lib/manifest.sh` | Add the pin, `quickshell`, `imagemagick` and QML modules; drop `webp`; fix comments | 2, 3 |
| `install.sh` | New "Installing hyprquickpaper" section after swww | 2 |
| `config/niri/config.kdl` | Rebind Mod+Alt+Ctrl+B, then Mod+Alt+B | 1, 3 |
| `doctor.sh` | Check `next.sh`, then the clone/pin/patch; drop the fuzzel picker check | 1, 2, 3 |
| `config/fuzzel/fuzzel.ini` | Comment: no more wallpaper-picker.ini | 3 |
| `README.md` | Tree, settings table, "Animated wallpapers" | 1, 2, 3 |
| `wallpaper/pick.sh`, `wallpaper/picker.ini` | Delete | 3 |

---

### Task 1: Move Mod+Alt+Ctrl+B into `wallpaper/next.sh`

**Files:**
- Create: `wallpaper/next.sh`
- Modify: `lib/paths.sh` (wallpaper rows, ~line 64-71)
- Modify: `config/niri/config.kdl:644-645`
- Modify: `doctor.sh` (after the `wallpaper-apply.sh` check, ~line 488-493)
- Modify: `README.md` (tree, ~line 161-168)

**Interfaces:**
- Produces: `~/.config/niri/wallpaper-next.sh`, no arguments. It writes the next path into `wallpaper-active` and `exec`s `wallpaper-apply.sh`.

- [ ] **Step 1: Write the failing check**

```bash
SCRATCH=$(mktemp -d); H=$SCRATCH/home
mkdir -p "$H/Documents/Wallpapers" "$H/.config/niri"
touch "$H/Documents/Wallpapers/"{a.png,b.gif,c.jpg}
printf '#!/bin/sh\necho "painted $(cat "$HOME/.config/niri/wallpaper-active")"\n' \
    > "$H/.config/niri/wallpaper-apply.sh"
chmod +x "$H/.config/niri/wallpaper-apply.sh"
W=$H/Documents/Wallpapers; A=$H/.config/niri/wallpaper-active
cat > "$SCRATCH/check-next.sh" <<EOF
set -u
run() { HOME="$H" bash wallpaper/next.sh; }
fail=0
expect() { [ "\$1" = "\$2" ] && echo "ok   \$3" || { echo "FAIL \$3: got '\$1' want '\$2'"; fail=1; }; }
echo "$W/b.gif" > "$A"; expect "\$(run)" "painted $W/c.jpg" "steps to the next"
expect "\$(run)" "painted $W/a.png" "wraps round at the end"
echo /nope > "$A";       expect "\$(run)" "painted $W/a.png" "unknown current starts at the first"
rm -f "$A";              expect "\$(run)" "painted $W/a.png" "no selection starts at the first"
mv "$W" "$W.x"; run >/dev/null 2>&1; expect "\$?" 1 "no wallpaper dir fails"; mv "$W.x" "$W"
exit \$fail
EOF
bash "$SCRATCH/check-next.sh"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash "$SCRATCH/check-next.sh"`
Expected: every line `FAIL` (`bash: wallpaper/next.sh: No such file or directory`), exit 1.

- [ ] **Step 3: Write `wallpaper/next.sh`**

```bash
#!/usr/bin/env bash
# The next wallpaper along: Mod+Alt+Ctrl+B.
#
# The companion to the picker on Mod+Alt+B (hyprquickpaper): no list, just the
# wallpaper after the current one, in filename order, wrapping round at the
# end. An order rather than a dice roll, so that pressing it N times always
# lands in the same place and every wallpaper comes round once per lap. A
# current one that is not in the folder (renamed, deleted, never set) starts
# from the first.
#
# Like the picker, it only writes the selection and hands off to
# wallpaper-apply.sh. That script owns every swww flag — the Nearest filter on
# GIFs, the retries while the daemon comes up — and two callers of swww with
# two ideas about the flags is how those drift apart.
set -euo pipefail

WALLPAPERS="$HOME/Documents/Wallpapers"
ACTIVE="$HOME/.config/niri/wallpaper-active"
APPLY="$HOME/.config/niri/wallpaper-apply.sh"

die() {
    echo "$*" >&2
    command -v notify-send &>/dev/null && notify-send "Wallpaper" "$*"
    exit 1
}

[ -d "$WALLPAPERS" ] || die "No wallpaper directory: $WALLPAPERS"
[ -x "$APPLY" ] || die "wallpaper-apply.sh missing or not executable — run configure.sh"

# bash sorts a glob, so the order holds from one press to the next; nullglob
# makes an empty folder an empty list rather than the unmatched pattern.
CYCLE=()
shopt -s nullglob
for wall in "$WALLPAPERS"/*; do
    [ -f "$wall" ] && CYCLE+=("$wall")
done
shopt -u nullglob
[ "${#CYCLE[@]}" -gt 0 ] || die "No wallpapers in $WALLPAPERS"

current="$(head -n1 "$ACTIVE" 2>/dev/null || true)"
next=0
for i in "${!CYCLE[@]}"; do
    if [ "${CYCLE[$i]}" = "$current" ]; then
        next=$(( (i + 1) % ${#CYCLE[@]} ))
        break
    fi
done

printf '%s\n' "${CYCLE[$next]}" > "$ACTIVE"

# exec, so the exit status you see is the paint's and not this script's.
exec "$APPLY"
```

Then `chmod +x wallpaper/next.sh`.

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash "$SCRATCH/check-next.sh"`
Expected: five `ok` lines, exit 0. Also run `bash -n wallpaper/next.sh` and, if installed, `shellcheck wallpaper/next.sh`: no output.

- [ ] **Step 5: Deploy it, point the bind at it, and teach doctor and the README**

In `lib/paths.sh`, add this row after the `wallpaper/pick.sh` row:

```bash
    "wallpaper/next.sh|.config/niri/wallpaper-next.sh|exec"
```

In `config/niri/config.kdl`, replace

```kdl
    // Its companion skips the list: the next wallpaper along, in filename order.
    Mod+Alt+Ctrl+B hotkey-overlay-title="Wallpaper: Next" { spawn "~/.config/niri/wallpaper-pick.sh" "--next"; }
```

with

```kdl
    // Its companion skips the list: the next wallpaper along, in filename
    // order. wallpaper/next.sh.
    Mod+Alt+Ctrl+B hotkey-overlay-title="Wallpaper: Next" { spawn "~/.config/niri/wallpaper-next.sh"; }
```

In `doctor.sh`, directly after the block ending `issue "wallpaper-apply.sh missing or not executable — swww-daemon has nothing to paint"` / `note "  Install with: bash configure.sh"` / `fi`, add:

```bash

# Mod+Alt+Ctrl+B. Like the picker, a shortcut that would do nothing rather than
# a blank screen.
if [ ! -x "$HOME/.config/niri/wallpaper-next.sh" ]; then
    issue "wallpaper-next.sh missing or not executable — Mod+Alt+Ctrl+B will do nothing"
    note "  Install with: bash configure.sh"
fi
```

In `README.md`'s tree, change the `pick.sh` line's comment and add `next.sh` below it:

```
│   ├── pick.sh                             # → ~/.config/niri/wallpaper-pick.sh    The picker (Mod+Alt+B)
│   ├── next.sh                             # → ~/.config/niri/wallpaper-next.sh    The next one along (Mod+Alt+Ctrl+B)
```

`pick.sh --next` still works; Task 3 deletes the whole file.

- [ ] **Step 6: Verify the deploy and the bind**

Run:
```bash
bash configure.sh >/dev/null && ls -l ~/.config/niri/wallpaper-next.sh
niri validate
bash doctor.sh 2>&1 | grep -E 'wallpaper-next|README structure|Not in the README|names a'
```
Expected: `niri validate` reports the deployed config is valid. (Don't validate `config/niri/config.kdl` in place: its `include`s only exist once it's deployed.) The deployed file is executable. doctor shows no `wallpaper-next` issue and `All N files in lib/paths.sh appear in the tree`. Then press **Mod+Alt+Ctrl+B** once: the wallpaper changes and `head -n1 ~/.config/niri/wallpaper-active` names the next file.

- [ ] **Step 7: Commit**

```bash
git add wallpaper/next.sh lib/paths.sh config/niri/config.kdl doctor.sh README.md
git commit -m "refactor(wallpaper): move the next-wallpaper bind into its own script

Mod+Alt+Ctrl+B ran pick.sh --next. It gets a script of its own so the
fuzzel picker can be replaced without taking the cycle key with it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Install hyprquickpaper, patched and configured

**Files:**
- Create: `wallpaper/hyprquickpaper.json`
- Create: `wallpaper/hyprquickpaper.patch`
- Modify: `lib/manifest.sh` (versions block; `APT_PACKAGES`)
- Modify: `install.sh` (new section between "Installing swww" and "Installing bluetui", ~line 324)
- Modify: `lib/paths.sh` (wallpaper rows)
- Modify: `doctor.sh` (next to the herdr-worktrunk check, ~line 455-468)
- Modify: `README.md` (tree)

**Interfaces:**
- Consumes: `~/.config/niri/wallpaper-apply.sh` (exists already) and `~/.config/niri/wallpaper-active`.
- Produces: `HYPRQUICKPAPER_REF` in `lib/manifest.sh`; a patched checkout at `~/.config/quickshell/hyprquickpaper` with the repo's `config.json`; `wallpaper/hyprquickpaper.patch`, which `doctor.sh` checks with `git apply --reverse --check`.

- [ ] **Step 1: Write the failing check**

The check pulls the new `install.sh` section out by its header and runs it against a scratch home, so it never touches `~/.config`. It covers three cases: a fresh install, a re-run, and a directory that holds only the deployed `config.json` (what `configure.sh` leaves if it runs before `install.sh`). Then it runs the patched `commands.sh` end to end with the repo's config and a stub `wallpaper-apply.sh`.

```bash
SCRATCH=$(mktemp -d)
cat > "$SCRATCH/check-hqp.sh" <<'EOF'
set -u
REPO=$PWD; S=$1; fail=0
ok()   { echo "ok   $*"; }
bad()  { echo "FAIL $*"; fail=1; }
section_of() {   # the install.sh section, as a script runnable against $S/home
    { echo 'set -euo pipefail'
      echo "DOTFILES='$REPO'; USER_HOME='$1'"
      echo 'source "$DOTFILES/lib/common.sh"; source "$DOTFILES/lib/manifest.sh"'
      sed -n '/^# ─── hyprquickpaper/,/^# ─── bluetui/p' "$REPO/install.sh" | sed '$d'
    } > "$S/run.sh"
    grep -q 'HQP_DIR=' "$S/run.sh" || { bad "no hyprquickpaper section in install.sh"; return 1; }
    bash "$S/run.sh"
}
H=$S/home; D=$H/.config/quickshell/hyprquickpaper
source "$REPO/lib/manifest.sh"
[ -n "${HYPRQUICKPAPER_REF:-}" ] && ok "pin in manifest" || bad "HYPRQUICKPAPER_REF unset"
jq -e . "$REPO/wallpaper/hyprquickpaper.json" >/dev/null && ok "config is JSON" || bad "config not JSON"

# 1. fresh
section_of "$H" >/dev/null || bad "fresh install exited non-zero"
[ "$(git -C "$D" rev-parse HEAD 2>/dev/null)" = "${HYPRQUICKPAPER_REF:-x}" ] && ok "fresh: at the pin" || bad "fresh: not at the pin"
git -C "$D" apply --reverse --check "$REPO/wallpaper/hyprquickpaper.patch" 2>/dev/null && ok "fresh: patched" || bad "fresh: not patched"
# 2. re-run is a no-op
out=$(section_of "$H" 2>&1) || bad "re-run exited non-zero"
grep -q 'already at' <<<"$out" && grep -q 'already patched' <<<"$out" && ok "re-run: no-op" || bad "re-run: $out"
# 3. directory holding only config.json
H2=$S/home2; D2=$H2/.config/quickshell/hyprquickpaper
mkdir -p "$D2"; cp "$REPO/wallpaper/hyprquickpaper.json" "$D2/config.json"
section_of "$H2" >/dev/null && git -C "$D2" apply --reverse --check "$REPO/wallpaper/hyprquickpaper.patch" 2>/dev/null \
    && ok "pre-seeded dir: installed and patched" || bad "pre-seeded dir"

# 4. a GIF pick goes to custom_command, which writes the selection and runs apply
cp "$REPO/wallpaper/hyprquickpaper.json" "$D/config.json"
mkdir -p "$H/.config/niri"
printf '#!/bin/sh\necho "apply ran" > "$HOME/apply.log"\n' > "$H/.config/niri/wallpaper-apply.sh"
chmod +x "$H/.config/niri/wallpaper-apply.sh"
HOME=$H bash "$D/commands.sh" "$H/Documents/Wallpapers/chill.gif" > "$S/cmd.log" 2>&1
[ "$(head -n1 "$H/.config/niri/wallpaper-active" 2>/dev/null)" = "$H/Documents/Wallpapers/chill.gif" ] \
    && ok "GIF pick: selection written" || bad "GIF pick: selection not written ($(cat "$S/cmd.log"))"
[ -f "$H/apply.log" ] && ok "GIF pick: apply ran" || bad "GIF pick: apply did not run"
grep -q mpvpaper "$S/cmd.log" && bad "GIF pick reached mpvpaper" || ok "GIF pick: no mpvpaper"
exit $fail
EOF
bash "$SCRATCH/check-hqp.sh" "$SCRATCH"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash "$SCRATCH/check-hqp.sh" "$SCRATCH"`
Expected: `FAIL HYPRQUICKPAPER_REF unset`, `FAIL no hyprquickpaper section in install.sh` and further FAILs; exit 1.

- [ ] **Step 3: Pin it and name its packages in `lib/manifest.sh`**

After the `HERDR_WORKTRUNK_REF=…` line (end of the versions block), add:

```bash

# hyprquickpaper — the wallpaper picker on Mod+Alt+B, a Quickshell config. Not
# packaged anywhere and untagged, so install.sh fetches this commit into
# ~/.config/quickshell/hyprquickpaper and applies wallpaper/hyprquickpaper.patch.
# The source was read at this commit (2026-10-31): it makes no network calls
# and runs only its own cache.sh, commands.sh and set-layout.sh. Bump the pin
# only after reading the diff, and check the patch still applies.
# https://github.com/ujjalsigdel/hyprquickpaper
HYPRQUICKPAPER_REF="0c2de83fe2734ea938ea06727b2722f275f7c412"
```

In `APT_PACKAGES`, after the `webp` entry, add:

```bash

    # The wallpaper picker (Mod+Alt+B) is hyprquickpaper, a Quickshell config.
    # quickshell comes from the danklinux PPA added for niri. Its package pulls
    # in the Qt libraries but none of the QML modules the picker's layouts
    # import, so those are named here: without them the overlay fails to load,
    # with no error anywhere you would see it. All five, so that switching
    # layout cannot break it.
    quickshell
    qml6-module-qtquick-controls
    qml6-module-qtquick-effects
    qml6-module-qtquick-shapes
    qml6-module-qt-labs-folderlistmodel
    qml6-module-qt5compat-graphicaleffects
    # The picker's thumbnailer: ImageMagick shrinks every thumbnail, and ffmpeg
    # (above) pulls the frame out of a GIF first.
    imagemagick
```

- [ ] **Step 4: Write `wallpaper/hyprquickpaper.patch`**

Create it with exactly this content. It ends with a trailing newline, and the context lines start with one space.

```diff
diff --git a/commands.sh b/commands.sh
index 1fb60a4..d0c9bc0 100644
--- a/commands.sh
+++ b/commands.sh
@@ -70,7 +70,10 @@ notify() {
 # ALWAYS kill any running video wallpaper first.
 pkill mpvpaper 2>/dev/null
 
-if is_video "$WALLPAPER" "$VIDEO_EXT_PATTERN"; then
+# ubuntu-setup: with custom_command set, every pick goes to it. GIFs are
+# listed in video_extensions only so cache.sh thumbnails them with ffmpeg;
+# swww paints them, and mpvpaper is never run.
+if [ -z "$CUSTOM_CMD" ] && is_video "$WALLPAPER" "$VIDEO_EXT_PATTERN"; then
     echo "Detected video file: $WALLPAPER"
 
     # Locate the cached still for this video. cache.sh writes both
```

Line 72 of the context is a blank line, which in a patch is a single space. If your editor strips trailing whitespace, regenerate the file instead. In a scratch clone at the pin, make the same one-line edit to `commands.sh` and save its `git diff` over `wallpaper/hyprquickpaper.patch`.

- [ ] **Step 5: Write `wallpaper/hyprquickpaper.json`**

```json
{
  "wallpaper_path": "~/Documents/Wallpapers/",
  "cache_path": "~/.cache/quickshell/thumbs/",
  "active_layout": "layouts/shell-floating.qml",
  "wallpaper_tool": "auto",
  "custom_command": "printf '%s\\n' \"$WALLPAPER\" > \"$HOME/.config/niri/wallpaper-active\" && \"$HOME/.config/niri/wallpaper-apply.sh\"",
  "post_apply": [],
  "notify_on_apply": false,
  "number_of_pictures": 7,
  "border_color": "#49ccd2",
  "cache_batch_size": 20,
  "stable_copy_path": "",
  "video_extensions": ["gif"],
  "video_thumbnail_interval": 5
}
```

Why these values (JSON has no comments, so this explanation goes in the README in Task 3):
- `active_layout` is upstream's default, a placeholder until the user chooses in Task 4.
- `custom_command` makes `wallpaper_tool` irrelevant.
- `video_extensions` is only `gif`. Any real video format would reach `custom_command`, and swww can't paint it.
- `border_color` is the cyan of the other Mod+Alt pickers.

Confirm the `custom_command` decodes as intended:

```bash
jq -r .custom_command wallpaper/hyprquickpaper.json
```
Expected: `printf '%s\n' "$WALLPAPER" > "$HOME/.config/niri/wallpaper-active" && "$HOME/.config/niri/wallpaper-apply.sh"`

- [ ] **Step 6: Add the install section to `install.sh`**

Insert it after the swww section's closing `fi` and before `# ─── bluetui (bluetooth pairing) ───…`:

```bash
# ─── hyprquickpaper (the wallpaper picker) ────────────────────────────────────
# Mod+Alt+B: a Quickshell overlay with a thumbnail of every wallpaper. Not
# packaged anywhere, so it is a checkout of the commit lib/manifest.sh pins, in
# the directory its own README uses. Fetched by commit into an init'd repo
# rather than cloned, so this works whether the directory is missing, already
# a checkout, or holds only the config.json configure.sh deploys into it.
# Upstream's own install.sh is not run: it prompts, and installs packages the
# manifest already names.
#
# Then one patch: with custom_command set, every pick goes to it — GIFs
# included, which upstream would hand to mpvpaper. configure.sh (step 8, below)
# copies the repo's config.json over upstream's.
#
# Not fatal if it fails: the rest of the machine is fine without a picker, and
# Mod+Alt+Ctrl+B still changes wallpaper.
section "Installing hyprquickpaper"

HQP_DIR="$USER_HOME/.config/quickshell/hyprquickpaper"
HQP_PATCH="$DOTFILES/wallpaper/hyprquickpaper.patch"
if [ -d "$HQP_DIR/.git" ] \
   && [ "$(git -C "$HQP_DIR" rev-parse HEAD 2>/dev/null)" = "$HYPRQUICKPAPER_REF" ]; then
    info "hyprquickpaper already at ${HYPRQUICKPAPER_REF:0:12}"
elif mkdir -p "$HQP_DIR" \
     && git -C "$HQP_DIR" init -q \
     && git -C "$HQP_DIR" fetch -q --depth 1 https://github.com/ujjalsigdel/hyprquickpaper "$HYPRQUICKPAPER_REF" \
     && git -C "$HQP_DIR" checkout -q --force FETCH_HEAD; then
    info "Installed hyprquickpaper ${HYPRQUICKPAPER_REF:0:12}"
else
    warn "Could not fetch hyprquickpaper — Mod+Alt+B will do nothing"
fi

# --reverse --check succeeds only on an already-patched tree, which is what
# makes a re-run quiet. A checkout of a new pin starts unpatched.
if git -C "$HQP_DIR" apply --reverse --check "$HQP_PATCH" 2>/dev/null; then
    info "hyprquickpaper already patched"
elif git -C "$HQP_DIR" apply "$HQP_PATCH" 2>/dev/null; then
    info "Patched hyprquickpaper's commands.sh"
else
    warn "wallpaper/hyprquickpaper.patch does not apply — a GIF pick would go to mpvpaper, not swww"
fi

```

`checkout --force` also discards an applied patch and a deployed `config.json`. That is wanted when the pin changes: the patch is re-applied just below, and `configure.sh` redeploys the config.

- [ ] **Step 7: Deploy the config and add it to the README tree**

In `lib/paths.sh`, after the `wallpaper/swww-daemon.service` row, add:

```bash
    # The picker's config, over upstream's own in the checkout install.sh makes.
    # The patch next to it is applied by install.sh, not deployed.
    "wallpaper/hyprquickpaper.json|.config/quickshell/hyprquickpaper/config.json|copy"
```

In `README.md`'s tree, after the `swww-daemon.service` line, add:

```
│   ├── hyprquickpaper.json                 # → ~/.config/quickshell/hyprquickpaper/config.json  The picker's config
│   ├── hyprquickpaper.patch                # Applied by install.sh to the picker's checkout: every pick goes to swww
```

In `README.md`'s package-manifest paragraph (~line 386), change `the version pins for Node, swww, Iosevka, bluetui, worktrunk, dotenvx and Proton Pass` to `the version pins for Node, swww, Iosevka, bluetui, worktrunk, dotenvx, Proton Pass and hyprquickpaper`.

- [ ] **Step 8: Check it from `doctor.sh`**

Insert directly before the `# herdr-worktrunk: without it …` comment:

```bash
# The wallpaper picker, Mod+Alt+B. A checkout rather than a package, so apt's
# check above cannot see it; and the patch is what keeps a GIF pick on swww.
# Its config.json is a lib/paths.sh row, checked with the other managed files.
HQP_DIR="$HOME/.config/quickshell/hyprquickpaper"
if [ ! -d "$HQP_DIR/.git" ]; then
    issue "hyprquickpaper not installed — Mod+Alt+B will do nothing"
    note "  Install with: bash install.sh"
else
    hqp_ref=$(git -C "$HQP_DIR" rev-parse HEAD 2>/dev/null)
    if ! git -C "$HQP_DIR" apply --reverse --check "$DOTFILES/wallpaper/hyprquickpaper.patch" 2>/dev/null; then
        issue "hyprquickpaper is not patched — a GIF pick would go to mpvpaper, not swww"
        note "  Patch with: bash install.sh"
    elif [ "$hqp_ref" != "$HYPRQUICKPAPER_REF" ]; then
        note "hyprquickpaper is at ${hqp_ref:0:12}, manifest pins ${HYPRQUICKPAPER_REF:0:12}"
    else
        ok "hyprquickpaper ${hqp_ref:0:12} installed and patched"
    fi
fi

```

- [ ] **Step 9: Run the check to verify it passes**

Run: `bash "$SCRATCH/check-hqp.sh" "$SCRATCH"`
Expected: all `ok` (pin, JSON, fresh, patched, re-run no-op, pre-seeded dir, the three GIF-pick lines), exit 0. This runs upstream's `commands.sh` in a scratch home with a stub `wallpaper-apply.sh`. That is the code being installed, so running it is the test. Then:

```bash
bash -n install.sh doctor.sh
bash doctor.sh 2>&1 | grep -E 'hyprquickpaper|README structure|Not in the README|names a'
```
Expected: no syntax errors. doctor shows `hyprquickpaper not installed` (true on this machine until Task 4), `Not installed: ~/.config/quickshell/hyprquickpaper/config.json` (same reason) and `All N files … appear in the tree`, and nothing about the tree naming missing files.

- [ ] **Step 10: Commit**

```bash
git add lib/manifest.sh install.sh lib/paths.sh doctor.sh README.md \
    wallpaper/hyprquickpaper.json wallpaper/hyprquickpaper.patch
git commit -m "feat(wallpaper): install hyprquickpaper at a pinned commit

The Quickshell picker that replaces the fuzzel one. It is fetched at a
pinned commit, patched so every pick, GIFs included, goes to swww and
never to mpvpaper, and given the repo's config.json, whose
custom_command writes the selection and runs wallpaper-apply.sh.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Bind Mod+Alt+B to hyprquickpaper and delete the fuzzel picker

**Files:**
- Modify: `config/niri/config.kdl:639-643`
- Delete: `wallpaper/pick.sh`, `wallpaper/picker.ini`
- Modify: `lib/paths.sh` (wallpaper rows and their comment; the fuzzel comment ~line 77-80)
- Modify: `lib/manifest.sh` (`fuzzel`, `ffmpeg`, `webp` entries)
- Modify: `doctor.sh` (the "picker behind Mod+Alt+B" block, ~line 510-521)
- Modify: `config/fuzzel/fuzzel.ini:1-10`
- Modify: `README.md` (tree; settings table ~line 300; "Animated wallpapers" ~line 341-380)

**Interfaces:**
- Consumes: `~/.config/quickshell/hyprquickpaper` (Task 2) and `wallpaper-next.sh` (Task 1).

- [ ] **Step 1: Write the failing check**

```bash
SCRATCH=$(mktemp -d)
cat > "$SCRATCH/check-gone.sh" <<'EOF'
fail=0
hits=$(git grep -n -E 'wallpaper-pick|pick\.sh|picker\.ini|wallpaper-picker|webpmux' -- . \
       ':!docs/superpowers/plans' ':!docs/superpowers/specs' | grep -v '^doctor.sh:.*went stale three times' \
       | grep -v '^doctor.sh:.*then wallpaper/pick.sh')
[ -z "$hits" ] && echo "ok   no references to the fuzzel picker" || { echo "FAIL references remain:"; echo "$hits"; fail=1; }
[ ! -e wallpaper/pick.sh ] && [ ! -e wallpaper/picker.ini ] && echo "ok   files deleted" || { echo "FAIL files still present"; fail=1; }
grep -q 'Mod+Alt+B .*spawn-sh "qs -n -p ~/.config/quickshell/hyprquickpaper"' config/niri/config.kdl \
    && echo "ok   Mod+Alt+B opens hyprquickpaper" || { echo "FAIL Mod+Alt+B not rebound"; fail=1; }
exit $fail
EOF
bash "$SCRATCH/check-gone.sh"
```

(The two excluded `doctor.sh` lines are the README-tree check's history comment: "…then wallpaper/pick.sh and wallpaper/picker.ini". It records a past event and stays as it is.)

- [ ] **Step 2: Run it to verify it fails**

Run: `bash "$SCRATCH/check-gone.sh"`
Expected: `FAIL references remain:` listing `config.kdl`, `lib/paths.sh`, `lib/manifest.sh`, `doctor.sh`, `README.md` and `fuzzel.ini` lines, plus `FAIL files still present` and `FAIL Mod+Alt+B not rebound`; exit 1.

- [ ] **Step 3: Rebind Mod+Alt+B**

In `config/niri/config.kdl`, replace

```kdl
    // The wallpaper picker lists rather than cycles, because a handful of
    // wallpapers have no order worth stepping through and two of the filenames
    // are download hashes. wallpaper/pick.sh shows them in
    // fuzzel with thumbnails and hands the choice to wallpaper-apply.sh.
    Mod+Alt+B hotkey-overlay-title="Wallpaper: Pick" { spawn "~/.config/niri/wallpaper-pick.sh"; }
```

with

```kdl
    // The wallpaper picker lists rather than cycles, because the wallpapers
    // have no order worth stepping through and several filenames are download
    // hashes. hyprquickpaper shows them as thumbnails; Enter hands the choice to
    // wallpaper-apply.sh through the custom_command in wallpaper/hyprquickpaper.json.
    // spawn-sh because spawn only expands ~ in the program; -n is Quickshell's
    // own guard, so a second press while it is open does nothing.
    Mod+Alt+B hotkey-overlay-title="Wallpaper: Pick" { spawn-sh "qs -n -p ~/.config/quickshell/hyprquickpaper"; }
```

- [ ] **Step 4: Delete the fuzzel picker and its rows**

```bash
git rm wallpaper/pick.sh wallpaper/picker.ini
```

In `lib/paths.sh`, replace the wallpaper comment and rows so the block reads:

```bash
    # wallpaper — one directory in the repo, destinations on disk across three
    # trees, which is exactly why it is a feature directory rather than part of
    # the mirror. The picker's config lands in Quickshell's tree because the
    # picker is a Quickshell config, even though only the wallpaper bind uses it.
    "wallpaper/apply.sh|.config/niri/wallpaper-apply.sh|exec"
    "wallpaper/next.sh|.config/niri/wallpaper-next.sh|exec"
    "wallpaper/swww-daemon.service|.config/systemd/user/swww-daemon.service|copy"
    # The picker's config, over upstream's own in the checkout install.sh makes.
    # The patch next to it is applied by install.sh, not deployed.
    "wallpaper/hyprquickpaper.json|.config/quickshell/hyprquickpaper/config.json|copy"
```

and in the fuzzel comment further down, replace

```bash
    # fuzzel — the launcher on Mod+Space. The other fuzzel configs are not here:
    # picker.ini is a symlink niri-tasks installs, and wallpaper-picker.ini goes
    # out with the wallpaper feature above.
```

with

```bash
    # fuzzel — the launcher on Mod+Space. The other fuzzel config is not here:
    # picker.ini is a symlink niri-tasks installs.
```

In `README.md`'s tree, delete the `pick.sh` and `picker.ini` lines, and change the `wallpaper/` line's comment from `these land in four directories` to `these land in three trees`. In the bullet below the tree (~line 200), replace

```markdown
  instead of being scattered to match. `wallpaper/` is the only one — its two
  scripts, its fuzzel picker config, its systemd unit and its images would
  otherwise be scattered across four destinations to match where each one goes.
```

with

```markdown
  instead of being scattered to match. `wallpaper/` is the only one — its two
  scripts, its picker config, its systemd unit and its images would otherwise
  be scattered across four destinations to match where each one goes.
```

- [ ] **Step 5: Fix the manifest**

In `lib/manifest.sh`'s `APT_PACKAGES`:

Replace the fuzzel comment

```bash
    # dmenu-style picker used by open_project_workspace.sh (Mod+Alt+W) and by
    # wallpaper/pick.sh (Mod+Alt+B). Usually pulled in as a niri dependency, but
    # named here so it can't silently disappear from under the shortcuts.
```

with

```bash
    # dmenu-style picker used by open_project_workspace.sh (Mod+Alt+W) and the
    # launcher (Mod+Space). Usually pulled in as a niri dependency, but named
    # here so it can't silently disappear from under the shortcuts.
```

Replace the ffmpeg comment

```bash
    # Thumbnails for the wallpaper picker. Named for the same reason as fuzzel:
    # it happened to be installed here already, and a shortcut that quietly
    # stops showing previews on a fresh machine is worse than one that fails.
    # ffmpeg rather than ImageMagick because -frames:v 1 takes the first frame
    # of an animated GIF, and most of these wallpapers are animated GIFs.
    ffmpeg
```

with

```bash
    # GIF thumbnails for the wallpaper picker: hyprquickpaper's cache.sh pulls
    # one frame out with ffmpeg, then ImageMagick (below) shrinks it. Named for
    # the same reason as fuzzel: a picker that quietly loses its previews on a
    # fresh machine is worse than one that fails.
    ffmpeg
```

Delete the `webp` entry and its comment:

```bash
    # webpmux, for the thumbnails of animated WebP wallpapers. ffmpeg's WebP
    # decoder reads still WebP only, so the picker has webpmux copy out the
    # first frame for ffmpeg to scale.
    webp

```

- [ ] **Step 6: Replace doctor's fuzzel-picker check**

In `doctor.sh`, delete the whole block from `# The picker behind Mod+Alt+B. Not required for the desktop to come up — unlike` through its closing `fi` (the `wallpaper-pick.sh` / `ffmpeg` / `webpmux` checks). Task 2's hyprquickpaper check replaces it, and the apt check covers ffmpeg and ImageMagick.

- [ ] **Step 7: Fix `config/fuzzel/fuzzel.ini`'s header**

The wallpaper picker isn't fuzzel any more. Replace lines 3-6

```ini
# Every other fuzzel in this setup is handed a config explicitly — the project
# and task pickers get niri-tasks' picker.ini, the wallpaper picker gets
# wallpaper-picker.ini. This is the file fuzzel reads when nothing is passed,
# which is how the bare `fuzzel` in the Mod+Space bind ends up here.
```

with

```ini
# Every other fuzzel in this setup is handed a config explicitly — the project
# and task pickers get niri-tasks' picker.ini. This is the file fuzzel reads
# when nothing is passed, which is how the bare `fuzzel` in the Mod+Space bind
# ends up here.
```

and replace (~line 54)

```ini
# Colours from picker.ini, so this matches the project, task and wallpaper
# pickers rather than the Dracula palette it used to carry.
```

with

```ini
# Colours from picker.ini, so this matches the project and task pickers rather
# than the Dracula palette it used to carry.
```

Change nothing else in that file.

- [ ] **Step 8: Rewrite the README's wallpaper docs**

Settings table row (~line 300) stays as it is. It already reads `Mod+Alt+B` (pick) / `Mod+Alt+Ctrl+B` (next).

In `## Animated wallpapers`, add two rows to the "Piece | Role" table, after `wallpaper/apply.sh`:

```markdown
| hyprquickpaper (`~/.config/quickshell/hyprquickpaper`) | The picker on `Mod+Alt+B`: thumbnails of the folder, `Enter` writes the pick to `wallpaper-active` and runs `apply.sh` |
| `wallpaper/next.sh` | `Mod+Alt+Ctrl+B`: the next wallpaper, in filename order |
```

Replace the paragraph starting `**To change wallpaper**, point` and its code block with:

````markdown
**To change wallpaper**, press `Mod+Alt+B` and pick one (arrows or `h`/`l`,
`Enter` to apply, `Esc` to close), or `Mod+Alt+Ctrl+B` for the next one along.
By hand, point `wallpaper-active` at another image in `~/Documents/Wallpapers`
and restart the daemon:

```bash
echo ~/Documents/Wallpapers/205.png > ~/.config/niri/wallpaper-active
systemctl --user restart swww-daemon.service
```
````

Then, before the paragraph `The reasoning lives next to what it explains`, add:

```markdown
### The picker

[hyprquickpaper](https://github.com/ujjalsigdel/hyprquickpaper) is a
Quickshell config. `install.sh` fetches it at the commit `lib/manifest.sh` pins
(`HYPRQUICKPAPER_REF`) into `~/.config/quickshell/hyprquickpaper`, then applies
`wallpaper/hyprquickpaper.patch`. `configure.sh` deploys
`wallpaper/hyprquickpaper.json` over its `config.json`. That config's
`custom_command` hands every pick to the same path as everything else: it
writes `wallpaper-active` and runs `wallpaper-apply.sh`. So the GIF filter, the
retries and the choice surviving a login all still live in `apply.sh`.

- **GIFs are listed as `video_extensions`.** That is how they get a thumbnail:
  `cache.sh` pulls a frame out with ffmpeg, which it does only for "videos".
  Upstream would then hand the pick to mpvpaper. The patch sends every pick to
  `custom_command` instead. No real video format is in the list, because swww
  can't paint one.
- **Change the layout in the repo.** Set `active_layout` in
  `wallpaper/hyprquickpaper.json` and run `configure.sh`. The switcher
  (`qs -p ~/.config/quickshell/hyprquickpaper/settings.qml`) is fine for
  auditioning, but it rewrites the live `config.json`, which `doctor.sh` then
  reports as drift.
- **Thumbnails** live in `~/.cache/quickshell/thumbs/`. A GIF's is
  `<name>.jpg`, so `x.gif` and `x.jpg` would share one. WebP isn't listed at
  all. Neither happens in this collection.
- **Bumping the pin**: read the upstream diff, change `HYPRQUICKPAPER_REF`, and
  run `install.sh`. If the patch no longer applies, `install.sh` warns and
  `doctor.sh` reports it.
```

Also in the paragraph `The whole image folder is installed…`, change `` `doctor.sh` checks the daemon, the script, and that…`` to `` `doctor.sh` checks the daemon, the scripts, the picker's checkout and patch, and that…``.

- [ ] **Step 9: Run the checks to verify they pass**

Run: `bash "$SCRATCH/check-gone.sh"`
Expected: three `ok` lines, exit 0. Then:

```bash
bash -n doctor.sh
bash configure.sh >/dev/null && niri validate
bash doctor.sh 2>&1 | grep -E 'README structure|Not in the README|names a|wallpaper'
```
Expected: the deployed config is valid, `All N files in lib/paths.sh appear in the tree`, and no `names a file/directory that is gone`.

- [ ] **Step 10: Commit**

```bash
git add -A config/niri/config.kdl lib/paths.sh lib/manifest.sh doctor.sh \
    config/fuzzel/fuzzel.ini README.md wallpaper/
git commit -m "feat(wallpaper): pick wallpapers with hyprquickpaper

Mod+Alt+B opens hyprquickpaper instead of the fuzzel list, which goes,
along with its fuzzel theme and the webp package that only its
thumbnails needed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Install it on this machine, choose the layout, verify end to end

This task needs the user at the keyboard. It installs packages (sudo), opens the picker, and asks the user to choose a layout.

**Files:**
- Modify: `wallpaper/hyprquickpaper.json` (`active_layout` only)

- [ ] **Step 1: Install the packages**

Ask the user to run, at the prompt:

```
! sudo apt install quickshell imagemagick qml6-module-qtquick-controls qml6-module-qtquick-effects qml6-module-qtquick-shapes qml6-module-qt-labs-folderlistmodel qml6-module-qt5compat-graphicaleffects
```

Then `bash doctor.sh 2>&1 | grep -iE 'apt|missing'` should list none of these.

- [ ] **Step 2: Fetch, patch and deploy**

Run the `install.sh` section on its own (the whole `install.sh` prompts and reinstalls a great deal):

```bash
{ echo 'set -euo pipefail'; echo "DOTFILES='$PWD'; USER_HOME='$HOME'"
  echo 'source "$DOTFILES/lib/common.sh"; source "$DOTFILES/lib/manifest.sh"'
  sed -n '/^# ─── hyprquickpaper/,/^# ─── bluetui/p' install.sh | sed '$d'; } > "$SCRATCH/hqp.sh"
bash "$SCRATCH/hqp.sh"
bash configure.sh
```
Expected: `Installed hyprquickpaper 0c2de83fe273`, `Patched hyprquickpaper's commands.sh`, and `configure.sh` copying `~/.config/quickshell/hyprquickpaper/config.json`.

Remove what the fuzzel picker left on this machine. Nothing deploys these any more:

```bash
rm -f ~/.config/niri/wallpaper-pick.sh ~/.config/fuzzel/wallpaper-picker.ini
rm -rf ~/.cache/wallpaper-thumbs
```

- [ ] **Step 3: Have the user try the layouts and choose one**

Open the switcher: `qs -n -p ~/.config/quickshell/hyprquickpaper/settings.qml`. Ask the user to try layouts: apply one in the switcher, then press Mod+Alt+B to see it, and repeat. When they have chosen, read the result back:

```bash
jq -r .active_layout ~/.config/quickshell/hyprquickpaper/config.json
```

Write that value into `active_layout` in `wallpaper/hyprquickpaper.json`, then run `bash configure.sh` so the live file matches the repo again. If any layout fails to open, run `qs -p ~/.config/quickshell/hyprquickpaper` from a terminal. Its log names the missing QML module. Add that module to the manifest list from Task 2 and tell the user.

- [ ] **Step 4: Verify the done-when list**

1. **Mod+Alt+B opens hyprquickpaper with thumbnails for GIF, JPG and PNG.** Press it, then check:
   ```bash
   ls ~/.cache/quickshell/thumbs/ | grep -E '^(205\.png|chill\.jpg|wallhaven-2yy9r9\.jpg)$'
   ```
   Expected: all three, one per line (PNG, GIF→jpg, JPG). Visually confirm the GIF cards show images, not `Loading…` or blanks.
2. **Enter paints the pick with swww and updates `wallpaper-active`.** Pick a GIF other than the current one and press Enter, then:
   ```bash
   head -n1 ~/.config/niri/wallpaper-active
   swww query
   ```
   Expected: both name the picked file, and it animates on screen. Repeat with a JPG.
3. **Mod+Alt+Ctrl+B still cycles.** Press it and run `head -n1 ~/.config/niri/wallpaper-active`. Expected: the next file in filename order, now on screen.
4. **A second Mod+Alt+B while the picker is open** does not open a second one. **Esc** closes it without a change.
5. **doctor.sh is clean:**
   ```bash
   bash doctor.sh 2>&1 | grep -E '✗|issue|Not installed|differs|hyprquickpaper|Wallpaper'
   ```
   Expected: `hyprquickpaper 0c2de83fe273 installed and patched`, `Wallpaper on screen matches the selection (…)`, and no issues from this work. Report any issue that predates this branch to the user rather than fixing it here.

- [ ] **Step 5: Commit the chosen layout**

```bash
git add wallpaper/hyprquickpaper.json
git commit -m "feat(wallpaper): use the <layout name> layout for the picker

Chosen by trying them on this machine.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(Replace `<layout name>` with the chosen layout, e.g. `grid view`. Skip this commit if the user keeps `shell-floating.qml`.)
