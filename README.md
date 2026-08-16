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
| Task manager | Taskwarrior (workspace-scoped shortcuts live in [niri-tasks](https://github.com/pauldaywork/niri-tasks)) |
| Containers | Docker (Ubuntu's `docker.io` + compose/buildx, user in `docker` group) |
| Wallpaper | Wallpaper collection + the active choice, drawn by swww (systemd user units) so animated GIFs animate |

## Setting up a new machine

### 1. Install Ubuntu

Install Ubuntu 26.04 LTS (Resolute Raccoon) — the PPAs used here target this release.

### 2. Clone this repo

You'll need git first:

```bash
sudo apt install git
git clone git@github.com:yourusername/backup-os.git ~/Documents/Code/backup-os
```

If you don't have your SSH key yet, clone with HTTPS instead — `install.sh` generates one near the end and prints the public half for you to paste into GitHub.

### 3. Run the install script

```bash
cd ~/Documents/Code/backup-os
bash install.sh
```

Laptops get extra niri config on top — `Super+Alt+Comma` / `Super+Alt+Period` to turn the built-in display off/on when an external monitor is connected, plus `Mod+Up`/`Mod+Down` to focus the workspace above/below and `Mod+Ctrl+Up`/`Mod+Ctrl+Down` to move the current column to it.

**You don't have to ask for it.** The installer reads the DMI chassis type (and falls back to looking for a battery), and records the answer in `~/.config/niri/.machine-type` so every later run agrees with the first. `--laptop` and `--desktop` override the guess, and the override is recorded too:

```bash
bash install.sh --laptop     # force it on
bash install.sh --desktop    # force it off, and keep it off
```

This used to hang on remembering the flag: the installer copied the repo's `config.kdl` over the live one and *then* appended the include, so a single re-run without `--laptop` deleted those binds with no error and nothing to notice until you reached for one. The config is now assembled with the include already in it before anything is written, and `doctor.sh` flags a machine that has a battery but no laptop include — or an include whose target file is missing, which niri refuses to load at all.

The script will:

1. Remove a leftover `mako-notifier` install if present (DMS owns notifications now, and the two fight over the notification socket)
2. Add PPAs for Niri, DankMaterialShell, Sublime Text, and Google Chrome
3. Install all apt packages, from the list in `lib/manifest.sh`
4. Enable the Docker service and add you to the `docker` group (takes effect on next login)
5. Install the NVIDIA container toolkit, but only if an NVIDIA GPU is actually present (read from sysfs, so it works before any driver is)
6. Install apps without an apt repo (Obsidian) via their official installers
7. Install snap packages (Firefox, VS Code, CMake)
8. Install Rust via the official rustup.rs script (not the rustup snap — its confinement causes friction with `cargo install` and linking against system libraries)
9. Build and install swww, the wallpaper daemon (see [Animated wallpapers](#animated-wallpapers))
10. Install Bun via the official installer
11. Install NVM + Node.js v24.18.0
12. Install Claude Code via npm
13. Copy all config files to their correct locations, install the wallpaper systemd units, create `~/Projects/`, and copy the wallpapers to `~/Documents/Wallpapers/`
14. Clone [niri-tasks](https://github.com/pauldaywork/niri-tasks) to `~/Projects/niri-tasks` and build it — this runs straight after the config copy, so its installer can replace the `niri-tasks.kdl` stub that was just seeded
15. Install TPM (tmux plugin manager) and fetch tmux plugins
16. Install DMS plugins (the third-party taskwarrior widget)
17. Install VS Code extensions from `config/Code/extensions.txt`
18. Prompt for your git name and email
19. Generate a new SSH key and print the public key so you can add it to GitHub

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

## Repo structure

```
backup-os/
├── install.sh                              # Run on a new machine: packages, then everything below
├── configure.sh                            # Just the config files + wallpapers (no app installs)
├── doctor.sh                               # Diagnose drift on an already-set-up machine
├── extra.sh                                # Optional: Steam, OpenCode, LM Studio, NVIDIA
│
├── capture/                                # machine ──> repo, one script per thing
│   ├── dms-settings.sh                     # DMS GUI settings
│   ├── packages.sh                         # reports apt/snap not in the manifest
│   ├── wallpapers.sh                       # new images + which one is selected
│   ├── vscode-extensions.sh                # regenerates extensions.txt
│   └── niri.sh                             # the live config.kdl
│
├── lib/                                    # Shared by the scripts above
│   ├── common.sh                           # info/warn/ok/issue, pkg_installed, and copy/pull/merge_json
│   ├── manifest.sh                         # What gets installed: apt + snap lists, version pins
│   └── paths.sh                            # The one list of which file goes where
│
├── home/                                   # Mirrors ~/
│   ├── .bashrc
│   ├── .profile
│   ├── .taskrc
│   └── .tmux.conf
│
├── config/                                 # Mirrors ~/.config/
│   ├── niri/
│   │   ├── config.kdl                      # Includes niri-tasks.kdl; configure.sh seeds a stub for it
│   │   ├── window-rules/
│   │   │   ├── toggle.sh                   # Cycles the profile (Mod+Alt+R)
│   │   │   ├── normal.kdl                  # Fully opaque windows
│   │   │   └── focus.kdl                   # Unfocused windows fade out
│   │   └── dms/laptop.kdl                  # Installed on laptops only (auto-detected)
│   ├── ghostty/config.ghostty
│   ├── DankMaterialShell/                  # settings, plugin settings, firefox.css, theme
│   └── Code/                               # settings.json + extensions.txt
│
├── wallpaper/                              # A feature, not a mirror: these land in three places
│   ├── wallpaper-sync.sh                   # → ~/.config/niri/   Forwards DMS's choice to swww
│   ├── swww-daemon.service                 # → ~/.config/systemd/user/
│   ├── wallpaper-sync.service              # → ~/.config/systemd/user/
│   ├── active                              # Which image DMS had selected, per capture/wallpapers.sh
│   └── images/                             # → ~/Documents/Wallpapers/  (GIFs animate, via swww)
│
└── notes/                                  # Working notes; not installed anywhere
```

Two rules keep this predictable:

- **`home/` and `config/` mirror their destinations.** `config/ghostty/config.ghostty`
  installs to `~/.config/ghostty/config.ghostty`. The one exception is VS Code,
  which lands in `~/.config/Code/User/`.
- **Anything whose files land in more than one place gets its own directory**
  instead of being scattered to match. `wallpaper/` is the only one — its script,
  its two systemd units and its images would otherwise sit in three separate trees.

`lib/paths.sh` is what actually decides where each file goes, so the tree is free
to be organised for reading rather than for the installer's benefit.



---

## Niri window-rules / layout profiles

Niri is set up with two swappable profiles — `normal` (fully opaque windows) and `focus` (unfocused windows fade out, with its own gaps/border/layout tuning) — defined in `config/niri/window-rules/normal.kdl` and `focus.kdl`. Each file is a self-contained `layout { ... }` + `window-rule { ... }` block; `config.kdl` includes whichever one is active via the `~/.config/niri/window-rules-active.kdl` symlink.

Press **`Mod+Alt+R`** to cycle between profiles. This runs `config/niri/window-rules/toggle.sh`, which:

1. Repoints the `window-rules-active.kdl` symlink at the next profile
2. Records the choice in `~/.config/niri/.window-rules-profile`
3. Forces an immediate reload with `niri msg action load-config-file`
4. Shows a notification (if `notify-send` is available) naming the new profile

The symlink and state file are machine-local, not tracked in git — `configure.sh` seeds them to `focus` only if they don't already exist, so re-running install won't reset a profile you've already picked. To add another profile, drop a new `.kdl` file in `config/niri/window-rules/` and add its name to the `profiles=(...)` array in `window-rules/toggle.sh`.

---

## Workspace tasks and project workspaces

`Mod+Alt+P` to open a project on its own named workspace, `Mod+Alt+T` to add a
task to it, `Mod+Alt+L` to list and act on that workspace's tasks — all of that
lives in **[niri-tasks](https://github.com/pauldaywork/niri-tasks)** now, not here.

It used to be fifteen shell scripts under `config/niri/` plus a DankMaterialShell
plugin, enumerated by hand in `configure.sh`, `doctor.sh` and what was then `update.sh`.
It is one binary (`wt`) and one repo, which `install.sh` clones to
`~/Projects/niri-tasks` and builds straight after the config copy — early enough
that its installer can replace the include stub that step just seeded.

What this repo still owns:

- `config.kdl` carries `include "niri-tasks.kdl"`, and `configure.sh` seeds
  an **empty stub** at that path. niri refuses to load a config whose include is
  missing, so the stub is what lets this repo install on a machine that does not
  want niri-tasks. Its installer symlinks the real file over the stub.
- Ghostty's `command =` is set to `wt tmux-session` when `wt` is on `PATH`, and
  to plain `tmux` when it is not.

## Animated wallpapers

DMS paints the background with a QML `Image`, which decodes one frame — so a GIF
picked in its wallpaper tab shows up as a still, and [upstream won't change that
in-shell](https://github.com/AvengeMedia/DankMaterialShell/issues/793). So DMS's
own wallpaper layer is switched off (the empty `screenPreferences.wallpaper`
array in its `settings.json`) and [swww](https://github.com/LGFae/swww) draws the
background instead.

| Piece | Role |
|---|---|
| `swww-daemon.service` | Holds the background layer surface and plays the animation |
| `wallpaper-sync.service` → `wallpaper/wallpaper-sync.sh` | Watches DMS's `session.json` and forwards each change to swww |
| `layer-rule` on `^swww-daemon$` | `place-within-backdrop true`, so the background stays put instead of scrolling with the workspaces |

**Pick wallpapers exactly as before** — the DMS tab is still the UI, and matugen
theming still follows them. swww is built from a git tag by `install.sh`;
`doctor.sh` checks all three pieces plus the DMS toggle, so run it first if the
background ever goes black.

The reasoning lives next to what it explains, rather than here: why these are
systemd units and not `spawn-at-startup`, and the `place-within-backdrop` rule,
are in `config/niri/config.kdl`; the restart deadlock is in
`swww-daemon.service`; and the transition knobs, the re-apply guard and the
per-filetype scaling filter are all commented at the top of `wallpaper-sync.sh`.

### Rotation

**`Mod+Alt+B`** steps to the next wallpaper. For automatic rotation, **Settings →
Wallpaper → Automatic Cycling**, then either **Interval** (5 seconds to 12 hours,
default 5 minutes) or **Time** (once a day at a set clock time).

The one thing about cycling that isn't obvious, and is the reason the wallpapers
live where they do: **the folder it cycles through is the directory of the
current wallpaper.** It is not a separate setting — keeping them all in
`~/Documents/Wallpapers` is what makes them a rotation set. It also needs at
least two images there to do anything, and sorts them alphabetically.

Cycling never touched the rendering layer, so switching DMS's wallpaper off
changed nothing about it: `dms` keeps the schedule and writes the choice to
`session.json`, and `wallpaper-sync.sh` carries it to swww like any other change.

---

## One list of what's installed

`lib/manifest.sh` holds the apt packages, the snaps, and the version pins for Node, swww and Obsidian. `install.sh` installs from it; `doctor.sh` checks against it. They each kept their own copy before, with a comment on doctor's asking whoever edited one to remember the other — a promise no repo keeps, and a diagnostic that drifts from the installer is worse than none, since it invents problems and misses real ones.

`lib/common.sh` holds what all five scripts print with (`info`, `warn`, `ok`, `issue`, `section`) plus `pkg_installed` and `snap_install`. `pkg_installed` is the one worth not copy-pasting: `dpkg -s` exits 0 for packages in the `rc` state — removed, config files left behind — so it matches on the status field instead.

Build-only packages are tagged separately as `APT_BUILD_PACKAGES` (`liblz4-dev`, `libwayland-dev`, `wayland-protocols`). `install.sh` installs them; `doctor.sh` deliberately doesn't check them. They're only needed to *compile* swww — the binary links `liblz4.so.1` from `liblz4-1`, a different package — so a machine that built swww and later cleaned up its build deps is perfectly healthy, and flagging it would be doctor crying wolf. The thing that actually matters, swww being installed and running, is checked directly.

---

## Which direction things move

The repo deploys to the machine. That is the only automatic direction:

```bash
bash configure.sh        # repo ──> machine
```

Edit configs **in the repo** and deploy them. That is why 14 of the 17 managed
files are byte-identical to the repo at any moment — nothing edits them out on
the machine, so nothing has to be captured back.

### capture/ — the few things the machine owns

Some settings can only be changed on the machine: a GUI writes them, a package
manager records them, a daemon keeps the state. Those get a script each, and you
run the one you need rather than a single command that sweeps everything.

| Script | Pulls in |
|---|---|
| `capture/dms-settings.sh` | DankMaterialShell's GUI settings — bar layout, widget config |
| `capture/packages.sh` | Reports apt/snap packages installed but not in `lib/manifest.sh` |
| `capture/wallpapers.sh` | New images from `~/Documents/Wallpapers`, and which one is selected |
| `capture/vscode-extensions.sh` | Regenerates `config/Code/extensions.txt` |
| `capture/niri.sh` | The live `config.kdl`, for when DMS's keybind UI has written to it |

All take `--dry-run` to show what they would do, and `--yes` to skip the prompt
that protects uncommitted repo edits.

```bash
bash capture/dms-settings.sh --dry-run
bash capture/packages.sh
git diff                                # review before committing
```

There is deliberately **no** capture script for `.bashrc`, the window-rules, the
theme or ghostty. You would change those in a text editor, so change them in the
repo. A tool that moves files both ways is how you end up unable to say which
side is authoritative — which is what the old `update.sh` became.

`capture/packages.sh` reports rather than writes, because it is the one that
cannot tell what belongs: 132 packages are manually installed here and the
manifest declares 27, but most of the difference is Ubuntu's own base system.
`capture/packages-ignore.txt` filters the noise down to a reviewable list, and
`--add` / `--ignore` triage it one at a time.

### Re-running the installer is a no-op

`configure.sh` compares before it writes: a file that already matches is neither copied nor backed up, and a JSON merge that would change nothing leaves the live file alone. `config.kdl` is assembled first — the repo's copy plus the laptop include where that applies — so it can be compared as the finished article rather than copied and then appended to, which is what used to make it differ on every single run.

The upshot is that a re-run on an in-sync machine says "Nothing needed replacing — no backup taken" and touches nothing. `~/.config-backups` also keeps only the **5** most recent snapshots now; it grew to nine directories of near-identical files before anything pruned it. Directories in there that aren't named like a timestamp are left alone.

### DMS settings are merged, not replaced

`configure.sh` copies most files straight over the live one. The two DankMaterialShell JSON files are the exception: they're merged, because DMS owns and rewrites them. Every DMS release adds keys and bumps `configVersion`, so the copy in this repo is only ever a snapshot of whenever `capture/dms-settings.sh` last ran — and copying it flat over a newer live file deletes every key the snapshot has never heard of.

The merge takes our value for every key we carry and leaves live-only keys alone. `configVersion` deliberately comes from *our* file, i.e. the older number, so DMS re-runs its migrations over the result on next load and forward-migrates anything our snapshot holds in an old shape. Only top-level keys merge — nested structures like `barConfigs` are replaced wholesale, which is correct, since the bar layout is the thing being installed.

`capture/dms-settings.sh` holds `configVersion` and `displayProfiles` at the repo's values for exactly that reason: capturing the live `configVersion` would stop those migrations running, and a laptop's monitor layout installed onto a desktop is worse than none. It also lists any key it drops, since taking a live snapshot removes whatever DMS has migrated away from.

## Diagnosing an existing setup

If a tool on your current machine ever gets moved or reinstalled by hand (e.g. nvm relocated but `~/.bashrc` still points at the old path), `install.sh` isn't the right tool to fix it — it copies the repo's config over your live one, which can undo local state you didn't mean to touch. Use `doctor.sh` instead:

```bash
bash doctor.sh          # report-only: lists drift between what's installed and what your dotfiles expect
bash doctor.sh --fix    # same, but offers to interactively repair dangling PATH/env references (with a backup)
```

It only ever edits dotfile references, and only after you confirm each one. If it finds the same tool installed two different ways (e.g. both snap and apt/rustup.rs), it reports that and prints the command to remove the redundant one — it won't uninstall anything on its own.

What it checks:

| Area | What it looks for |
|---|---|
| Packages | Everything in `lib/manifest.sh` — the same list `install.sh` installs from, so the two can't drift. Build-only packages are excluded on purpose |
| Docker | Group membership, service running, and `docker-ce` conflicting with Ubuntu's `docker.io` |
| Toolchains | rustup, bun, nvm (and that `NVM_DIR` points where nvm actually is), Node, Claude Code, TPM |
| Wallpaper | swww installed, both user units enabled and running, DMS's built-in wallpapers still disabled, **and that what's on screen is what DMS has selected** — the one check that catches a missed paint |
| Laptop config | A machine with a battery whose `config.kdl` lacks the laptop include, or an include pointing at a file that isn't there |
| Dotfiles | `PATH`/env references in `.bashrc` and `.profile` that point at paths which no longer exist, skipping ones guarded by a file test |
| Config drift | Every file in `lib/paths.sh`: installed, matching the repo, and executable where the kind says so. `config.kdl` is compared separately, with the laptop include stripped from both sides. Files `configure.sh` rewrites after copying — ghostty — are checked for presence but not content |
| niri-tasks | That `wt` is installed, the `niri-tasks.kdl` include exists (niri refuses to load a config whose include is missing), and the active-task overlay service is running |
| Leftovers | Files this repo used to install and no longer does — the workspace-task scripts, the fuzzel picker theme, the old DMS plugin. Deleting them from the repo doesn't delete them from a machine that already has them |

The wallpaper row is the one worth running after a reboot: every other check can be green while the screen shows a stale image, because swww restores its own cache when it starts.
