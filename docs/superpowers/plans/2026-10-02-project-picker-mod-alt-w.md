# Project Picker on Mod+Alt+W Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Mod+Alt+W` opens the project picker (`niritasks project open`); `Mod+Alt+P` is unbound and the "New Named Workspace" bind is gone.

**Architecture:** The bind itself lives in the niri-tasks repo (`niri/niri-tasks.kdl`, symlinked live as `~/.config/niri/niri-tasks.kdl`). This repo only mentions the key in docs and comments, plus the shortcut list that `configure.sh` builds from the live `niri-tasks.kdl` via `shortcuts/build.py`. So: rebind in niri-tasks, fix every prose mention in both repos, then rebuild the list with `configure.sh`.

**Tech Stack:** niri KDL config, bash, `shortcuts/build.py` (python3), `niri validate`.

**Spec:** Taskwarrior task `126c04a8-1b7a-4035-a72b-5edae1b0aadf` — read it with `task rc.json.array=on 126c04a8-1b7a-4035-a72b-5edae1b0aadf export`.

## Global Constraints

- `Mod+Alt+W` runs `niritasks project open`. The picker already creates a new project from a typed name (fuzzel echoes unmatched text; see niri-tasks `src/project.rs:3-4`).
- Drop the "New Named Workspace" bind. For a workspace with no folder, go to an empty workspace and use `Mod+Alt+Ctrl+W`. The `niritasks workspace new` subcommand stays (do not touch `src/main.rs` or the README's `niritasks workspace new|rename|default` usage line).
- `Mod+Alt+P` is freed, with no alias. `Mod+Alt+Ctrl+W` stays as rename.
- Out of scope: removing the `workspace new` subcommand; changing plain `Mod+W` (`toggle-column-tabbed-display`).
- Historical plans under `docs/superpowers/` and `.scratch/` in either repo are records, not docs — leave their `Mod+Alt+P` mentions alone. "grep finds no Mod+Alt+P" means outside those.

## Two repos, two checkouts

- **ubuntu-setup:** this worktree, `/home/paul/.worktrees/ubuntu-setup/task-move-project-picker-to-mod-alt-w-drop-126c04a8`. Landed later with the `finish-worktree` skill.
- **niri-tasks:** `/home/paul/Projects/niri-tasks`, branch `main`. Edit and commit there directly — it is the checkout `~/.config/niri/niri-tasks.kdl` symlinks to, so it is the only place the live bind and the shortcut list can see the change. Before editing, check `git -C /home/paul/Projects/niri-tasks status --short` is empty; if it is not, stop and ask. Do **not** push; say in the report that the niri-tasks commit is local and unpushed.

---

### Task 1: Rebind in niri-tasks

**Files (all under `/home/paul/Projects/niri-tasks`):**
- Modify: `niri/niri-tasks.kdl:54-55` (drop the New Named Workspace bind), `:66-72` (P → W)
- Modify: `README.md:20-21`
- Modify: `install.sh:133`
- Modify: `fuzzel/picker.ini:2`

**Interfaces:**
- Produces: live bind `Mod+Alt+W hotkey-overlay-title="Open Project Workspace" { spawn "niritasks" "project" "open"; }`, which Task 2's shortcut list rebuild reads.

- [ ] **Step 1: Show the failing check**

Run:
```bash
cd /home/paul/Projects/niri-tasks
git status --short
grep -rn 'Mod+Alt+P\|New Named Workspace' --exclude-dir=.git --exclude-dir=target --exclude-dir=superpowers .
```
Expected: `git status` empty; grep lists `install.sh:133`, `README.md:20`, `fuzzel/picker.ini:2`, `niri/niri-tasks.kdl:55` and `:72`.

- [ ] **Step 2: Rebind in `niri/niri-tasks.kdl`**

Delete these two lines (and the blank line after them) at the top of `binds {`:

```kdl
    // Create a new workspace and name it.
    Mod+Alt+W hotkey-overlay-title="New Named Workspace" { spawn "niritasks" "workspace" "new"; }
```

so `binds {` opens with the rename bind. Extend the rename comment so the dropped bind's job has a home:

```kdl
binds {
    // Rename the current workspace — and with it, which tag its tasks carry.
    // It is also how to get a named workspace with no project folder: go to
    // the empty workspace at the end and name it here.
    Mod+Alt+Ctrl+W hotkey-overlay-title="Rename Workspace" { spawn "niritasks" "workspace" "rename"; }
```

Then replace the project bind block:

```kdl
    // Pick a folder from ~/Projects, put it on its own named workspace, and
    // open a terminal on that workspace's herdr session
    // (`herdr --session <workspace>`) and VS Code in it. herdr reattaches the
    // session if it exists and creates it in the project folder if not. The
    // editor is skipped when `code` is not on $PATH — it is a nicety here, not
    // a requirement.
    Mod+Alt+P hotkey-overlay-title="Open Project Workspace" { spawn "niritasks" "project" "open"; }
```

with:

```kdl
    // Pick a folder from ~/Projects (or type a new name to make one), put it on
    // its own named workspace, and open a terminal on that workspace's herdr
    // session (`herdr --session <workspace>`) and VS Code in it. herdr
    // reattaches the session if it exists and creates it in the project folder
    // if not. The editor is skipped when `code` is not on $PATH — it is a
    // nicety here, not a requirement. W for workspace; its Ctrl companion,
    // Mod+Alt+Ctrl+W, renames one.
    Mod+Alt+W hotkey-overlay-title="Open Project Workspace" { spawn "niritasks" "project" "open"; }
```

- [ ] **Step 3: Update `README.md` keybind table (lines 20-21)**

Replace:

```markdown
| `Mod+Alt+P` | Pick a folder from `~/Projects`, put it on its own named workspace, open a terminal and an editor in it |
| `Mod+Alt+W` | Create a new workspace and name it |
```

with:

```markdown
| `Mod+Alt+W` | Pick a folder from `~/Projects` (or type a new name to make one), put it on its own named workspace, open a terminal and an editor in it |
```

Leave the `Mod+Alt+Ctrl+W` row as it is.

- [ ] **Step 4: Update `install.sh:133`**

Replace:

```bash
info "Done. Keybinds: Mod+Alt+T add, Mod+Alt+Ctrl+T pick on the panel, Mod+Alt+P project, Mod+Alt+W new workspace, Mod+Alt+Ctrl+W rename it."
```

with:

```bash
info "Done. Keybinds: Mod+Alt+T add, Mod+Alt+Ctrl+T pick on the panel, Mod+Alt+W open a project workspace, Mod+Alt+Ctrl+W rename it."
```

- [ ] **Step 5: Update `fuzzel/picker.ini:2`**

Replace `# open_project_workspace.sh (Mod+Alt+P), task-add.sh (Mod+Alt+T) and` with `# open_project_workspace.sh (Mod+Alt+W), task-add.sh (Mod+Alt+T) and`.

- [ ] **Step 6: Verify**

Run:
```bash
cd /home/paul/Projects/niri-tasks
grep -rn 'Mod+Alt+P\|New Named Workspace' --exclude-dir=.git --exclude-dir=target --exclude-dir=superpowers .
grep -n 'Mod+Alt+W\|Mod+Alt+Ctrl+W' niri/niri-tasks.kdl
niri validate -c ~/.config/niri/config.kdl
bash -n install.sh
```
Expected: first grep prints nothing; second shows exactly one `Mod+Alt+W ... "project" "open"` bind and one `Mod+Alt+Ctrl+W ... "rename"` bind; `niri validate` reports the config is valid; `bash -n` is silent.

- [ ] **Step 7: Commit (niri-tasks main, do not push)**

```bash
cd /home/paul/Projects/niri-tasks
git add niri/niri-tasks.kdl README.md install.sh fuzzel/picker.ini
git commit -m "$(cat <<'EOF'
Open a project workspace on Mod+Alt+W, drop New Named Workspace

W for workspace. The picker already makes a project from a typed name, and a
named workspace with no folder is an empty workspace plus Mod+Alt+Ctrl+W, so
the separate New Named Workspace bind goes and Mod+Alt+P is freed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Follow the new key in ubuntu-setup and rebuild the shortcut list

**Files (all in this worktree):**
- Modify: `README.md:261`, `README.md:281`
- Modify: `lib/manifest.sh:89`
- Modify: `wallpaper/picker.ini:8`
- Modify: `docs/worktree-setup.md:19`
- Modify: `config/waybar/dock.jsonc:23`, `:103`

**Interfaces:**
- Consumes: Task 1's committed `Mod+Alt+W` bind in `/home/paul/Projects/niri-tasks/niri/niri-tasks.kdl`.

- [ ] **Step 1: Show the failing check**

Run:
```bash
grep -rn 'Mod+Alt+P' --exclude-dir=.git --exclude-dir=superpowers --exclude-dir=.scratch .
python3 shortcuts/build.py --out "$TMPDIR/sc-before" >/dev/null && grep -E 'Mod\+Alt\+(P|W) ' "$TMPDIR/sc-before/shortcuts.tsv"
```
(Set `TMPDIR` to the session scratchpad first if it is not already.)
Expected: grep lists the seven lines above. If Task 1 is committed, the tsv already shows `Mod+Alt+W ... Open project workspace` and no `Mod+Alt+P`, since build.py reads the live niri-tasks.kdl — that is the dependency working, not a problem.

- [ ] **Step 2: Replace each mention**

Every one is a literal `Mod+Alt+P` → `Mod+Alt+W` with nothing else on the line changing:

- `README.md:261` — `` `Mod+Alt+P` to open a project on its own named workspace, `Mod+Alt+T` to add a `` → `` `Mod+Alt+W` to open ... ``
- `README.md:281` — `` window is a login shell — and `Mod+Alt+P` opens the project's terminal on its `` → `` `Mod+Alt+W` ``
- `lib/manifest.sh:89` — `# dmenu-style picker used by open_project_workspace.sh (Mod+Alt+P) and by` → `(Mod+Alt+W)`
- `docs/worktree-setup.md:19` — ``In a project's herdr session (`Mod+Alt+P`), the herdr-worktrunk plugin's keys:`` → `` (`Mod+Alt+W`) ``
- `config/waybar/dock.jsonc:23` — `// project open on them (Mod+Alt+P), so the list reads as a list of what you are` → `(Mod+Alt+W)`
- `config/waybar/dock.jsonc:103` — `// niri names workspaces, and niri-tasks leans on that heavily — Mod+Alt+P` → `Mod+Alt+W`

`wallpaper/picker.ini:8` lists three keys at once: `# a file in another repo and change how Mod+Alt+P/T/L look as a side effect.` → `# a file in another repo and change how Mod+Alt+W/T/L look as a side effect.`

A single command does all seven:
```bash
sed -i 's/Mod+Alt+P\b/Mod+Alt+W/g' README.md lib/manifest.sh docs/worktree-setup.md config/waybar/dock.jsonc
sed -i 's#Mod+Alt+P/T/L#Mod+Alt+W/T/L#' wallpaper/picker.ini
```

Leave `README.md:54` alone: "rename the workspace rather than make one" still describes `Mod+Alt+Ctrl+W` against `Mod+Alt+W`, which still makes a workspace.

- [ ] **Step 3: Verify the repo**

Run:
```bash
grep -rn 'Mod+Alt+P' --exclude-dir=.git --exclude-dir=superpowers --exclude-dir=.scratch .
git diff --stat
bash -n lib/manifest.sh
```
Expected: grep prints nothing; diff touches exactly `README.md`, `lib/manifest.sh`, `wallpaper/picker.ini`, `docs/worktree-setup.md`, `config/waybar/dock.jsonc`, 7 lines changed; `bash -n` silent.

- [ ] **Step 4: Run configure.sh and check the live result**

Run from this worktree (the spec says to run it; it copies this worktree's configs and rebuilds the shortcut list):
```bash
bash configure.sh
```
No `--laptop`/`--desktop` flag: configure.sh reuses the recorded machine type or detects it (`configure.sh:86-96`).

Then:
```bash
niri validate
niri msg action load-config-file
grep -E 'Mod\+Alt\+(P|W) ' ~/.local/share/shortcuts/shortcuts.tsv
grep -c 'New named workspace' ~/.local/share/shortcuts/shortcuts.tsv
```
Expected: config valid; the tsv has one `Mod+Alt+W  Open project workspace ... niritasks project open` line and no `Mod+Alt+P` line; the count is `0`.

- [ ] **Step 5: Hand-check with the user**

Ask the user to press `Mod+Alt+W` (fuzzel project picker appears; Escape closes it), press `Mod+Alt+P` (nothing happens), and open `Mod+Alt+/` and type `project` (the row shows `Mod+Alt+W`). Do not mark the task done until they confirm.

- [ ] **Step 6: Commit**

```bash
git add README.md lib/manifest.sh wallpaper/picker.ini docs/worktree-setup.md config/waybar/dock.jsonc
git commit -m "$(cat <<'EOF'
Point Mod+Alt+P mentions at Mod+Alt+W, the project picker's new key

niri-tasks moved the picker to W for workspace; these comments and docs
follow it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```
