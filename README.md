# backup-os

A dotfiles repo and bootstrap script for my Ubuntu + Niri + DankMaterialShell setup. Clone this on a new machine and run `install.sh` to get a working environment.

## What's included

| Category | Files |
|---|---|
| Shell | `.bashrc`, `.profile` |
| Terminal multiplexer | tmux (`.tmux.conf` + TPM-managed plugins) |
| Window manager | Niri config + custom DMS keybindings + swappable window-rules/layout profiles (`Mod+Alt+R`) |
| Notifications | DankMaterialShell (built-in) |
| Terminal | Ghostty (deb from the danklinux PPA, not the snap) |
| Bar / shell | DankMaterialShell (theme, settings, plugins) |
| Editor | Sublime Text (installed), VS Code (settings + extensions) |
| Task manager | Taskwarrior (+ DMS taskwarrior widget plugin) |
| Containers | Docker (Ubuntu's `docker.io` + compose/buildx, user in `docker` group) |
| Wallpaper | Active wallpaper at time of last `update.sh` run |

## Setting up a new machine

### 1. Install Ubuntu

Install Ubuntu 25.04 (Resolute) — the PPAs used here target this release.

### 2. Clone this repo

You'll need git first:

```bash
sudo apt install git
git clone git@github.com:yourusername/backup-os.git ~/Documents/Code/backup-os
```

If you don't have your SSH key yet, clone with HTTPS instead and set up the key during the install script (step 4).

### 3. Run the install script

```bash
cd ~/Documents/Code/backup-os
bash install.sh
```

On a laptop, pass `--laptop` to also install laptop-specific niri config (currently: `Super+Alt+Comma` / `Super+Alt+Period` to turn the built-in display off/on for when an external monitor is connected, plus `Mod+Up`/`Mod+Down` to focus the workspace above/below and `Mod+Ctrl+Up`/`Mod+Ctrl+Down` to move the current column to it):

```bash
bash install.sh --laptop
```

The script will:

1. Remove a leftover `mako-notifier` install if present (DMS owns notifications now, and the two fight over the notification socket)
2. Add PPAs for Niri, DankMaterialShell, Sublime Text, and Google Chrome
3. Install all apt packages
4. Enable the Docker service and add you to the `docker` group (takes effect on next login)
5. Install apps without an apt repo (Obsidian) via their official installers
6. Install snap packages (Firefox, VS Code, CMake)
7. Install Rust via the official rustup.rs script (not the rustup snap — its confinement causes friction with `cargo install` and linking against system libraries)
8. Install Bun via the official installer
9. Install NVM + Node.js v24.18.0
10. Install Claude Code via npm
11. Copy all config files to their correct locations, create `~/Projects/`, and copy the wallpaper to `~/Documents/Wallpapers/`
12. Install TPM (tmux plugin manager) and fetch tmux plugins
13. Install DMS plugins (taskwarrior widget)
14. Install VS Code extensions from `config/Code/extensions.txt`
15. Prompt for your git name and email
16. Generate a new SSH key and print the public key so you can add it to GitHub

### 4. After the script finishes

- **Reboot** to start Niri and DankMaterialShell (also picks up `docker` group membership)
- **Log into Claude Code**: run `claude` in a terminal
- **Add your SSH key to GitHub**: the script prints the public key — paste it at https://github.com/settings/ssh/new
- **Log into** Firefox, Chrome, and Obsidian as normal
- **Run `bash extra.sh`** if you want Steam, OpenCode, LM Studio, or NVIDIA drivers (see below)

### 5. Optional extras

`extra.sh` covers things not everyone wants on every machine: Steam, OpenCode, LM Studio, and NVIDIA drivers.

```bash
bash extra.sh
```

If the machine has an NVIDIA GPU, edit `extra.sh` and uncomment the NVIDIA lines before running it:

```bash
# sudo apt install -y nvidia-driver-595-open linux-modules-nvidia-595-open-generic-hwe-26.04
```

After running, re-download any LM Studio models you need (not included in this repo) and log into Steam.

---

## Niri window-rules / layout profiles

Niri is set up with two swappable profiles — `normal` (fully opaque windows) and `focus` (unfocused windows fade out, with its own gaps/border/layout tuning) — defined in `config/niri/window-rules/normal.kdl` and `focus.kdl`. Each file is a self-contained `layout { ... }` + `window-rule { ... }` block; `config.kdl` includes whichever one is active via the `~/.config/niri/window-rules-active.kdl` symlink.

Press **`Mod+Alt+R`** to cycle between profiles. This runs `config/niri/toggle-window-rules.sh`, which:

1. Repoints the `window-rules-active.kdl` symlink at the next profile
2. Records the choice in `~/.config/niri/.window-rules-profile`
3. Forces an immediate reload with `niri msg action load-config-file`
4. Shows a notification (if `notify-send` is available) naming the new profile

The symlink and state file are machine-local, not tracked in git — `install.sh` seeds them to `focus` only if they don't already exist, so re-running install won't reset a profile you've already picked. To add another profile, drop a new `.kdl` file in `config/niri/window-rules/` and add its name to the `profiles=(...)` array in `toggle-window-rules.sh`.

---

## Project workspaces

Press **`Mod+Alt+P`** to jump to a project. This runs `config/niri/open_project_workspace.sh`, which:

1. Lists the folders in `~/Projects` in a fuzzel picker — just the names, no prompt or buttons. Up/Down moves, Enter or a mouse click selects, Esc cancels, and typing filters
2. Creates the folder if what you typed doesn't match anything (see below)
3. Focuses that project's workspace if it already exists, otherwise names the empty workspace at the end of the current output after the folder
4. Spawns a Ghostty window on it — but only for a workspace that's new or empty

Re-picking a project you already have open is a "take me back there", not a request for another terminal, so the shortcut is safe to hit repeatedly. The exception is a workspace you've closed every window on: niri keeps the name, and the picker treats it like a fresh one and gives you a terminal again.

### Creating a project from the picker

Type a name that matches no existing folder and press Enter: the script creates `~/Projects/<name>`, notifies you, and then opens it exactly as if it had already been there. This works because fuzzel's dmenu mode prints the typed text verbatim when it matches no entry. An empty `~/Projects` is fine too — the picker shows a bare input box and whatever you type becomes the first project.

Whitespace in a typed name becomes a dash, so created folders never contain spaces: `my cool project` makes `~/Projects/my-cool-project`, and runs of spaces or tabs collapse to one dash. The dashed name is then re-checked against the existing folders, so typing `my project` when `my-project` already exists just opens it rather than trying to create a duplicate. Only *typed* names are rewritten — a folder you already have with a space in its name still shows in the list and opens under its real name.

Names containing `/` or starting with `.` are rejected, since those would write outside `~/Projects` or create a folder the picker filters out of its own list.

The one rough edge: fuzzel only hands back raw text when it matches *nothing*, so you can't create a project whose name is contained in an existing one — typing `note` when `notes` exists selects `notes` instead. Use `mkdir` for those, or pick a name that isn't a substring of another.

The picker's look lives in `config/fuzzel/project-picker.ini`, passed to fuzzel with `--config=` so it stays separate from any `fuzzel.ini` you use elsewhere. The script sizes the window to the folder list at runtime (`--lines`/`--width`), so only the ini's font, padding and colours are worth editing.

The terminal lands in the project directory because Ghostty launches `tmux-niri-session.sh`, which starts its tmux session in `~/Projects/<workspace name>` when such a folder exists (falling back to `~/Projects`, then `$HOME`). So any terminal opened on a project workspace — not just the one this shortcut spawns — starts in the right place.

Related workspace shortcuts: **`Mod+Alt+W`** to create and name a workspace by hand, **`Mod+Shift+Alt+W`** to rename the focused one.

---

## Workspace tasks

Taskwarrior, scoped to whatever workspace you're on. The workspace name is the tag, so the tasks you see are always the tasks for the project in front of you.

| Shortcut | Does |
| --- | --- |
| **`Mod+Alt+T`** | Type a task into a fuzzel box; it's added tagged with the current workspace |
| **`Mod+Alt+L`** | List this workspace's pending tasks, then edit / delete / complete / set-active the one you pick |

The bottom bar carries an **Active Task** widget showing the started task for the focused workspace, and nothing at all when there isn't one. It updates on niri's event stream, so switching workspace changes it immediately.

### The tag rule

Workspace name → tag is lowercase, with everything that isn't a letter, digit or underscore folded to `_`. Taskwarrior tags are a single bare word: a dash reads as an operator inside a filter and a space splits the argument, so neither survives `task +<tag>`. Folding also means `Ubuntu-Setup`, `ubuntu setup` and `ubuntu-setup` all resolve to `ubuntu_setup` rather than to three tags each holding a third of the project's tasks.

An unnamed workspace has no tag, so both shortcuts refuse to run and say so — writing untagged tasks would put them somewhere no list ever looks.

The rule lives once, in `config/niri/task-lib.sh`, which the three scripts source.

### Adding vs editing

`Mod+Alt+T` passes what you type to `task` as separate words, so taskwarrior's own attribute syntax works: `ship the release due:friday priority:H` sets a due date and a priority instead of burying them in the description. (The script runs with globbing off, so a `*` in a task stays a `*`.)

Editing a description from `Mod+Alt+L` deliberately does the opposite — it's quoted, so a `due:` typed mid-rename stays text rather than silently putting a date on a task you were only retitling.

### Active tasks

"Set active" runs `task start`, having first run `task stop` on any other task carrying the tag. One active task per workspace, always — which is what lets the bar widget show a single unambiguous answer. Starting a task by hand in a terminal still works; the widget just takes the first if you somehow end up with two.

---

## Keeping configs up to date

When you change any config on your current machine and want to save it to the repo, run:

```bash
cd ~/Documents/Code/backup-os
bash update.sh
```

This copies all config files from their live locations into the repo and regenerates the VS Code extensions list. It also detects if you've changed your wallpaper in DMS and updates the repo to match.

### update.sh protects uncommitted repo edits

`update.sh` copies live → repo, so "this file differs" is the normal case and warning about it would fire every run. The one case it stops for is a repo file with **uncommitted** changes: those exist in exactly one place, so overwriting one destroys work git can't recover. A file that matches `HEAD` is pulled silently, because `git checkout` can always undo that.

When it finds one, it shows the diff and asks. Enter (the default) keeps the repo version. Untracked files count as uncommitted — there's no committed version of those to fall back on either.

```bash
bash update.sh          # asks before discarding uncommitted repo edits
bash update.sh --yes    # overwrites them without asking
```

Run non-interactively it never overwrites; it keeps the repo version and tells you at the end.

This exists because it already bit once: the `Mod+Alt+P` spawn-only-if-empty change was edited in the repo but never installed to `~/.config/niri/`, so the next `update.sh` copied the stale live version over the top of it. **The lesson the warning encodes: a repo edit isn't safe until it's either installed live or committed.**

### DMS settings are merged, not replaced

`install-config.sh` copies most files straight over the live one. The two DankMaterialShell JSON files are the exception: they're merged, because DMS owns and rewrites them. Every DMS release adds keys and bumps `configVersion`, so the copy in this repo is only ever a snapshot of whenever `update.sh` last ran — and copying it flat over a newer live file deletes every key the snapshot has never heard of. Measured on this machine, that was 147 keys, including the display profiles and the entire battery section.

The merge takes our value for every key we carry and leaves live-only keys alone. `configVersion` deliberately comes from *our* file, i.e. the older number, so DMS re-runs its migrations over the result on next load and forward-migrates anything our snapshot holds in an old shape. Only top-level keys merge — nested structures like `barConfigs` are replaced wholesale, which is correct, since the bar layout is the thing being installed.

Running `update.sh` regularly still matters: it's what stops the snapshot drifting far enough behind that the merge is doing real work.

Then commit:

```bash
git add -A && git commit -m "Update configs"
git push
```

### What update.sh captures

| Config | Source |
|---|---|
| `.bashrc`, `.profile` | `~/` |
| tmux | `~/.tmux.conf` |
| Niri config | `~/.config/niri/` |
| Niri window-rules profiles | `~/.config/niri/window-rules/*.kdl`, `toggle-window-rules.sh` |
| Fuzzel project picker | `~/.config/fuzzel/project-picker.ini` |
| Ghostty | `~/.config/ghostty/` |
| DankMaterialShell | `~/.config/DankMaterialShell/` |
| VS Code settings | `~/.config/Code/User/settings.json` |
| VS Code extensions | generated by `code --list-extensions` |
| Taskwarrior | `~/.taskrc` |
| Wallpaper | active wallpaper read from DMS session |

### What is NOT tracked

- **SSH private key** — generate a new one per machine (the install script does this)
- **Claude Code auth** — re-login with `claude` after install
- **Browser profiles** — log in manually after install
- **LM Studio models** — too large; re-download from within the app
- **Obsidian vault** — sync separately (iCloud, Syncthing, etc.)
- **DMS auto-generated niri configs** — `colors.kdl`, `layout.kdl`, `outputs.kdl` etc. are regenerated by DMS on first launch and are machine-specific. `binds.kdl` is in this group too: DMS owns the file, and ours is an empty stub because those binds were folded into `config.kdl`'s own `binds` block. `install-config.sh` seeds that stub, since niri refuses to load a config whose `include` target is missing
- **Active window-rules profile** — `~/.config/niri/window-rules-active.kdl` (symlink) and `.window-rules-profile` (state file) are machine-local; `install.sh` seeds them to `focus` only on first install

---

## Diagnosing an existing setup

If a tool on your current machine ever gets moved or reinstalled by hand (e.g. nvm relocated but `~/.bashrc` still points at the old path), `install.sh` isn't the right tool to fix it — it copies the repo's config over your live one, which can undo local state you didn't mean to touch. Use `doctor.sh` instead:

```bash
bash doctor.sh          # report-only: lists drift between what's installed and what your dotfiles expect
bash doctor.sh --fix    # same, but offers to interactively repair dangling PATH/env references (with a backup)
```

It only ever edits dotfile references, and only after you confirm each one. If it finds the same tool installed two different ways (e.g. both snap and apt/rustup.rs), it reports that and prints the command to remove the redundant one — it won't uninstall anything on its own.

---

## Repo structure

```
backup-os/
├── install.sh                              # Run on a new machine
├── install-config.sh                       # Config files + wallpaper only (no app installs)
├── extra.sh                                # Optional: Steam, OpenCode, LM Studio, NVIDIA
├── update.sh                               # Run on current machine to snapshot changes
├── doctor.sh                               # Diagnose drift on an existing, already-set-up machine
├── home/
│   ├── .bashrc
│   ├── .profile
│   ├── .taskrc
│   └── .tmux.conf
├── config/
│   ├── niri/
│   │   ├── config.kdl
│   │   ├── create_named_workspace.sh       # GUI prompt to name a new workspace (zenity)
│   │   ├── rename_workspace.sh             # GUI prompt to rename the focused workspace (zenity)
│   │   ├── open_project_workspace.sh       # Picks (or creates) a ~/Projects folder, names a workspace after it, opens a terminal there (Mod+Alt+P)
│   │   ├── default_workspace_name.sh       # Names workspace 1 "general" on startup if unnamed
│   │   ├── tmux-niri-session.sh            # Ghostty's launch command; opens a tmux session named after the workspace, in the matching ~/Projects folder
│   │   ├── toggle-window-rules.sh          # Cycles window-rules/layout profile (Mod+Alt+R)
│   │   ├── task-lib.sh                     # Shared workspace-name → taskwarrior-tag rule; sourced by the three below
│   │   ├── task-add.sh                     # Types a task tagged with the current workspace (Mod+Alt+T)
│   │   ├── task-list.sh                    # Lists this workspace's tasks; edit/delete/complete/set-active (Mod+Alt+L)
│   │   ├── task-active.sh                  # Prints the workspace's active task; read by the Active Task bar widget
│   │   ├── window-rules/
│   │   │   ├── normal.kdl                  # Fully opaque windows
│   │   │   └── focus.kdl                   # Unfocused windows fade out
│   │   └── dms/
│   │       └── laptop.kdl                  # Only installed with `install.sh --laptop`
│   ├── fuzzel/
│   │   └── project-picker.ini              # Minimal picker theme shared by the project and task pickers
│   ├── ghostty/
│   │   └── config.ghostty
│   ├── DankMaterialShell/
│   │   ├── settings.json
│   │   ├── plugin_settings.json
│   │   ├── firefox.css
│   │   ├── plugins/activetask/             # Our own DMS bar widget: the workspace's active task
│   │   └── themes/peaceAndQuiet/theme.json
│   └── Code/
│       ├── settings.json
│       └── extensions.txt
└── wallpapers/
    └── 205.png                             # Active wallpaper
```
