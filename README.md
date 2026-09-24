# ubuntu-setup

A dotfiles repo and bootstrap script for my Ubuntu + Niri setup. Clone this on a new machine and run `install.sh` to get a working environment.

## What's included

| Category | Files |
|---|---|
| Shell | `.bashrc`, `.profile` |
| Terminal multiplexer | tmux (`.tmux.conf` + TPM-managed plugins) |
| Window manager | Niri config + swappable window-rules/layout profiles (`Mod+Alt+R`) |
| Bar | waybar (`config.jsonc` + `style.css`), started by niri |
| Notifications | mako |
| Launcher | fuzzel (`Mod+Space`) |
| Terminal | Ghostty (deb from the danklinux PPA, not the snap) |
| Editor | Sublime Text (installed), VS Code (settings + extensions) |
| Task manager | Taskwarrior (workspace-scoped shortcuts live in [niri-tasks](https://github.com/pauldaywork/niri-tasks)) |
| Containers | Docker (Ubuntu's `docker.io` + compose/buildx, user in `docker` group) |
| Wallpaper | Wallpaper collection + the active choice, drawn by swww (systemd user unit) so animated GIFs animate |

The bar, notifications and launcher were one package until recently:
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), a
Quickshell desktop that supplied all three plus a wallpaper picker and
matugen theming. It was dropped in favour of the smaller pieces above — see
[Life after DankMaterialShell](#life-after-dankmaterialshell) for what that
gained and what it cost.

## Setting up a new machine

### 1. Install Ubuntu

Install Ubuntu 26.04 LTS (Resolute Raccoon) — the PPAs used here target this release.

### 2. Clone this repo

You'll need git first:

```bash
sudo apt install git
git clone git@github.com:pauldaywork/ubuntu-setup.git ~/Projects/ubuntu-setup
```

If you don't have your SSH key yet, clone with HTTPS instead — `install.sh` generates one near the end and prints the public half for you to paste into GitHub.

### 3. Run the install script

```bash
cd ~/Projects/ubuntu-setup
bash install.sh
```

All machines use `Mod+Up`/`Mod+Down` to focus the workspace above/below and `Mod+Ctrl+Up`/`Mod+Ctrl+Down` to move the current column to it. Laptops get extra niri config — the built-in display's `eDP-1` output block, the brightness keys, and `Super+Alt+Comma` / `Super+Alt+Period` to turn the built-in display off/on when an external monitor is connected — plus battery and brightness on the top bar. Desktops get the desk's monitors and their 4K modes instead (`desktop.kdl`, with `Mod+Ctrl+0` to drop the HDMI matrix to 1080p@60), and a login screen layout for the same monitor — so a laptop never has a desk's resolutions forced on whatever screen it is plugged into. A machine that changes type has the other type's files removed. Use `Mod+J`/`Mod+K` to move focus between windows vertically, and `Mod+Ctrl+J`/`Mod+Ctrl+K` to move a window vertically within its workspace.

**You don't have to ask for it.** The installer reads the DMI chassis type (and falls back to looking for a battery), and records the answer in `~/.config/niri/.machine-type` so every later run agrees with the first. `--laptop` and `--desktop` override the guess, and the override is recorded too:

```bash
bash install.sh --laptop     # force it on
bash install.sh --desktop    # force it off, and keep it off
```

This used to hang on remembering the flag: the installer copied the repo's `config.kdl` over the live one and *then* appended the include, so a single re-run without `--laptop` deleted those binds with no error and nothing to notice until you reached for one. The config is now assembled with the include already in it before anything is written, and `doctor.sh` flags a machine that has a battery but no laptop include, an include that disagrees with the recorded machine type, or an include whose target file is missing, which niri refuses to load at all.

The script will:

1. Remove DankMaterialShell if it's installed — transitional, and a no-op on a machine that never had it (see [Life after DankMaterialShell](#life-after-dankmaterialshell))
2. Add PPAs for Niri/Ghostty, Sublime Text, and Google Chrome
3. Install all apt packages, from the list in `lib/manifest.sh`
4. Enable the Docker service and add you to the `docker` group (takes effect on next login)
5. Install the NVIDIA container toolkit, but only if an NVIDIA GPU is actually present (read from sysfs, so it works before any driver is)
6. Install apps that ship as `.deb`s — Obsidian, VS Code and ChatGPT — via their official downloads (VS Code and ChatGPT add their own apt repos for updates; VS Code is the `.deb` rather than the snap because the snap forces X11)
7. Install snap packages (Firefox, CMake)
8. Install Rust via the official rustup.rs script (not the rustup snap — its confinement causes friction with `cargo install` and linking against system libraries)
9. Build and install swww, the wallpaper daemon (see [Animated wallpapers](#animated-wallpapers)), and bluetui, which the waybar bluetooth module opens, then install the Iosevka Term font Ghostty uses into `~/.local/share/fonts`
10. Install Bun via the official installer
11. Install NVM + Node.js v24.18.0
12. Install Claude Code via npm
13. Copy all config files to their correct locations, install the swww systemd unit, create `~/Projects/`, and copy the wallpapers to `~/Documents/Wallpapers/`
14. Clone [niri-tasks](https://github.com/pauldaywork/niri-tasks) to `~/Projects/niri-tasks` and build it — this runs straight after the config copy, so its installer can replace the `niri-tasks.kdl` stub that was just seeded
15. Install TPM (tmux plugin manager) and fetch tmux plugins
16. Install VS Code extensions from `config/Code/extensions.txt`
17. Prompt for your git name and email
18. Generate a new SSH key and print the public key so you can add it to GitHub

### 4. After the script finishes

- **Reboot** to start Niri (also picks up `docker` group membership)
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
ubuntu-setup/
├── README.md                               # This file: how to set a machine up, and why it is built this way
├── CONTEXT.md                              # The glossary — deploy vs install vs capture vs seed
├── AGENTS.md                               # Points coding agents at docs/agents/
│
├── install.sh                              # Run on a new machine: packages, then everything below
├── configure.sh                            # Just the config files + wallpapers (no app installs)
├── doctor.sh                               # Diagnose drift on an already-set-up machine
├── extra.sh                                # Optional: Steam, OpenCode, LM Studio, NVIDIA
│
├── capture/                                # machine ──> repo, one script per thing
│   ├── packages.sh                         # reports apt/snap not in the manifest
│   ├── wallpapers.sh                       # new images + which one is selected
│   ├── vscode-extensions.sh                # regenerates extensions.txt
│   └── niri.sh                             # the live config.kdl
│
├── lib/                                    # Shared by the scripts above
│   ├── common.sh                           # info/warn/ok/issue, pkg_installed, and copy/pull
│   ├── manifest.sh                         # What gets installed: apt, .deb + snap lists, version pins
│   └── paths.sh                            # The one list of which file goes where
│
├── home/                                   # Mirrors ~/
│   ├── .bashrc
│   ├── .profile
│   ├── .taskrc
│   ├── .tmux.conf
│   └── .local/bin/chatgpt                  # Starts ChatGPT on Wayland from a terminal
│
├── config/                                 # Mirrors ~/.config/
│   ├── niri/
│   │   ├── config.kdl                      # Includes niri-tasks.kdl; configure.sh seeds a stub for it
│   │   ├── laptop.kdl                      # eDP-1 + brightness/display keys; laptops only (auto-detected)
│   │   ├── desktop.kdl                     # The desk's monitors, their 4K modes, Mod+Ctrl+0; desktops only
│   │   └── window-rules/
│   │       ├── toggle.sh                   # Cycles the profile (Mod+Alt+R)
│   │       ├── normal.kdl                  # Fully opaque windows
│   │       └── focus.kdl                   # Unfocused windows fade out
│   ├── waybar/                             # config.jsonc + style.css
│   │                                       #   + laptop.jsonc: battery/backlight, laptops only
│   ├── mako/config
│   ├── fuzzel/fuzzel.ini                   # The launcher only; the pickers bring their own configs
│   ├── ghostty/config.ghostty
│   ├── applications/                       # → ~/.local/share/applications/  (desktop entries)
│   │   ├── org.gnome.Settings.desktop      # Shadows the stock entry so Settings runs outside GNOME
│   │   └── chatgpt.desktop                 # Shadows the stock entry to start ChatGPT on Wayland
│   └── Code/                               # settings.json + extensions.txt
│
├── wallpaper/                              # A feature, not a mirror: these land in four directories
│   ├── apply.sh                            # → ~/.config/niri/wallpaper-apply.sh   Paints the selection
│   ├── pick.sh                             # → ~/.config/niri/wallpaper-pick.sh    The picker (Mod+Alt+B)
│   ├── picker.ini                          # → ~/.config/fuzzel/wallpaper-picker.ini  (fuzzel reads it)
│   ├── swww-daemon.service                 # → ~/.config/systemd/user/
│   ├── active                              # Seeds ~/.config/niri/wallpaper-active; never overwrites it
│   ├── CREDITS.md                          # Who made each image; not installed
│   └── images/                             # → ~/Documents/Wallpapers/  (GIFs animate, via swww)
│
├── system/                                 # Outside $HOME, so install.sh puts these in place with sudo
│   └── monitors.xml                        # → /etc/xdg/  The login screen's monitor layout; desktops only
│
├── docs/                                   # Not installed anywhere; read by people and agents
│   ├── adr/
│   │   └── 0001-one-way-deploy.md          # Why the repo deploys and capture/ stays manual
│   └── agents/                             # Per-repo config for the engineering skills
│       ├── issue-tracker.md                # Issues are markdown under .scratch/ (gitignored)
│       ├── triage-labels.md                # The five triage states
│       └── domain.md                       # Read CONTEXT.md and docs/adr/ before exploring
│
└── notes/                                  # Working notes; not installed anywhere
```

Two rules keep this predictable:

- **`home/` and `config/` mirror their destinations.** `config/ghostty/config.ghostty`
  installs to `~/.config/ghostty/config.ghostty`. Two exceptions: VS Code lands in
  `~/.config/Code/User/`, and `config/applications/` lands in
  `~/.local/share/applications/` — a desktop entry only counts where XDG looks for
  it, and that is not under `~/.config`.
- **Anything whose files land in more than one place gets its own directory**
  instead of being scattered to match. `wallpaper/` is the only one — its two
  scripts, its fuzzel picker config, its systemd unit and its images would
  otherwise be scattered across four destinations to match where each one goes.

`lib/paths.sh` is what actually decides where each file goes, so the tree is free
to be organised for reading rather than for the installer's benefit.

### The vocabulary, and the decisions

Two files carry what the rest of this README assumes you have picked up.

**`CONTEXT.md`** is the glossary, and nothing else — no mechanism, no paths. It
exists because this repo has two nouns that sound alike and two directions that
sound alike: packages and config files are both "installed", and deploying and
capturing both move files between the same two places. It settles those.
**Deploy** is repo → machine for config files, **install** is packages,
**capture** is machine → repo, and **seed** is writing a file only if it is
absent — what the installer does for a wallpaper or a window-rules profile,
where it has to guarantee a choice exists without overriding the one you made.

**`docs/adr/`** records decisions that are hard to reverse and surprising
without the history. There is one so far: [ADR-0001](docs/adr/0001-one-way-deploy.md)
on the one-way deploy, which is the long version of [Which direction things
move](#which-direction-things-move) below — what `update.sh` was, why deleting
it was justified by measuring first, and why the missing capture scripts are the
decision rather than an omission.

`AGENTS.md` and `docs/agents/` are for coding agents: where issues are tracked
for this repo, the triage vocabulary, and the instruction to read `CONTEXT.md`
and the ADRs before exploring.



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

---

## Life after DankMaterialShell

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) was a whole
Quickshell desktop arriving as one apt package: the bar, notifications, the
spotlight launcher, a wallpaper picker, matugen theming, and the niri colour and
monitor config generated from it. It was replaced by smaller pieces — two of
which, fuzzel and swww, were already installed here for other reasons.

| DMS gave | Now |
|---|---|
| Bar | waybar (`config/waybar/`) |
| Notifications | mako (`config/mako/config`) |
| Spotlight launcher (`Mod+Space`) | fuzzel — already in the manifest for the project picker |
| Wallpaper picker + cycling | `wallpaper/pick.sh` (`Mod+Alt+B`), a fuzzel picker with thumbnails, over `~/.config/niri/wallpaper-active` |
| `dms/colors.kdl`, `dms/outputs.kdl`, … | Written out in `config/niri/config.kdl` |
| Taskwarrior bar widget | *nothing* — see below |

Net, the repo lost about 1,900 lines and gained about 840. But the line count is
the least of it. What actually changed is that **nothing on this machine writes
its own config any more.** That removed a whole category of machinery: the
`merge` path kind and `merge_json`, the `capture/dms-settings.sh` round-trip, the
`inotify` watch on a state file owned by another process, and every use of
`python3` in the repo — all of which existed to read or write JSON some other
application considered its own.

**What this cost, plainly.** Notification *history* is gone; mako has
`makoctl restore`, which brings back the most recently dismissed notification and
nothing more. The taskwarrior bar widget is gone and nothing packaged replaces
it — task state is untouched (`task` on the command line, and niri-tasks'
`Mod+Alt+T`/`L`/`P` and its active-task overlay, which were always separate from
the widget), but the at-a-glance count in the bar is not coming back. The
click-through audio, network and bluetooth popovers are gone; waybar's modules
shell out to `wpctl`, `nmtui` and `bluetui` instead. Wallpapers no longer retint the
desktop. And the monitor layout is no longer detected per-machine — `config.kdl`
names the outputs and modes explicitly, so different hardware needs an edit
(`install.sh` warns about this at the end).

**Migrating an existing machine** is `install.sh`, which removes the `dms`
package as step 0, or by hand:

```bash
sudo apt install waybar mako-notifier
bash configure.sh
sudo apt remove dms
```

then log out and back in. `configure.sh` clears DMS's `~/.config` and
`~/.local/state` trees, but only once the package is actually gone — it is also
run on its own, and deleting a running application's settings out from under it
would be rude. That step 0 is transitional: a machine installed from scratch
today never gets DMS in the first place, so it can be deleted once every machine
has been through one install.

## Where settings live

Three places, and knowing which is which saves an afternoon. The short version:
**the desktop's behaviour is this repo, how apps look is `gsettings`, and
hardware is the Settings app.**

| What | Where | Why there |
|---|---|---|
| Keyboard, touchpad, mouse | `input {}` in `config/niri/config.kdl` | niri reads this directly; nothing else is consulted |
| Keybindings | `binds {}` in the same file | same |
| Monitors, resolution, scale | `output` blocks in `laptop.kdl` (`eDP-1`) and `desktop.kdl` (the desk's monitors); the login screen's in `system/monitors.xml` | niri applies these at startup and wins over anything set at runtime |
| Bar, notifications, launcher | `config/waybar/`, `config/mako/config`, `config/fuzzel/` | plain files this repo owns outright |
| Wallpaper | `Mod+Alt+B`, over `~/.config/niri/wallpaper-active` | see Animated wallpapers below |
| GTK theme, dark mode, cursor, fonts | `gsettings set org.gnome.desktop.interface …` | apps read these live through the settings portal |
| Network, Bluetooth, Sound, Power, Printers, Users, Date & Time | Settings app | these talk to system services, not to GNOME |

### The Settings app is half a Settings app

`gnome-control-center` is installed and works, with two caveats worth knowing
before you trust a panel.

It did not start at all until this repo shipped
`config/applications/org.gnome.Settings.desktop`. The stock entry carries
`OnlyShowIn=GNOME`, which hides it from fuzzel under niri, and the binary itself
exits with *"Running gnome-control-center is only supported under GNOME and
Unity"* because it reads `XDG_CURRENT_DESKTOP`. The override drops the first and
puts `env XDG_CURRENT_DESKTOP=GNOME` in front of the second. It also sets
`DBusActivatable=false`, without which a launcher would activate the app over
D-Bus and never read that `Exec` line at all.

The deeper caveat is that **most panels are applied by `gnome-settings-daemon`,
which does not run here.** So:

- **Works** — Network, Bluetooth, Sound, Power, Printers, Users, Date & Time,
  Online Accounts. NetworkManager, BlueZ, PipeWire, UPower and friends are
  system services and do not care what desktop is running.
- **Does nothing** — Mouse, Touchpad, Keyboard (repeat and shortcuts),
  Accessibility, Night Light. These write GSettings keys that only
  gnome-settings-daemon reads, and it is not there to read them. The change
  appears to take and has no effect. Input belongs in `config.kdl`.
- **Only until you log out** — Displays. niri implements
  `org.gnome.Mutter.DisplayConfig`, so the panel really does drive your outputs,
  but the `output` blocks in `config.kdl` are applied at startup and will quietly
  undo it.
- **Absent** — Appearance, Multitasking, Search, Extensions. These are GNOME
  Shell panels and there is no Shell. Appearance lives in `gsettings`; the
  background is swww's.

Appearance is worth a line of its own, because it is the one that looks like it
should be broken and is not. `xdg-desktop-portal-gnome` runs here, and it serves
the settings portal, so `gsettings set org.gnome.desktop.interface color-scheme
'prefer-dark'` reaches every GTK app without a settings daemon in sight.

## Animated wallpapers

niri draws no background of its own, so something has to. Most of this collection
is animated GIFs, and [swww](https://github.com/LGFae/swww) is what animates them
— `swaybg` and friends decode one frame and stop.

The images are other artists' work — see [`wallpaper/CREDITS.md`](wallpaper/CREDITS.md).

| Piece | Role |
|---|---|
| `swww-daemon.service` | Holds the background layer surface and plays the animation |
| `wallpaper/apply.sh` | Reads the selection and paints it, from the daemon's `ExecStartPost` |
| `~/.config/niri/wallpaper-active` | One line: the path of the image to paint |
| `layer-rule` on `^swww-daemon$` | `place-within-backdrop true`, so the background stays put instead of scrolling with the workspaces |

**To change wallpaper**, point `wallpaper-active` at another image in
`~/Documents/Wallpapers` and restart the daemon:

```bash
echo ~/Documents/Wallpapers/205.png > ~/.config/niri/wallpaper-active
systemctl --user restart swww-daemon.service
```

Then `bash capture/wallpapers.sh` to record the choice in the repo, so a fresh
machine comes up with the same background. `configure.sh` seeds
`wallpaper-active` from `wallpaper/active` but never overwrites a selection you
have already made — the installer's job is to make sure there *is* one, not to
have the last word on which.

The whole image folder is installed, not just the selected one, so there is
always something to point at. swww is built from a git tag by `install.sh`;
`doctor.sh` checks the daemon, the script, and that what is actually on screen
matches what `wallpaper-active` names — run it first if the background ever goes
black or goes stale.

The reasoning lives next to what it explains: why this is a systemd unit and not
`spawn-at-startup`, and the `place-within-backdrop` rule, are in
`config/niri/config.kdl`; why the paint happens in `ExecStartPost` is in
`swww-daemon.service`; and the transition knobs, the startup retry and the
per-filetype scaling filter are commented at the top of `wallpaper/apply.sh`.

### What this replaced

Until recently DankMaterialShell owned the wallpaper: it had the picker, it
stored the choice in `session.json`, and it drove matugen to retint the whole
desktop from the selected image. But it painted the background with a QML
`Image`, which decodes one frame, so a GIF showed up as a still — and [upstream
declined to animate it
in-shell](https://github.com/AvengeMedia/DankMaterialShell/issues/793), pointing
at the escape hatch instead. So DMS's wallpaper layer was switched off, swww drew
the background, and a 164-line `wallpaper-sync.sh` sat on `session.json` with
inotify forwarding every change across.

Almost none of that script was about wallpapers. It was about tracking another
application's state: re-deriving the selection each time the file moved (it lived
in `wallpaperPath`, a per-mode variant, or a per-monitor map depending on two
other settings), ignoring the rewrites that were really launcher history or night
mode, and comparing the daemon's pid each pass to catch a restart that had
restored swww's own stale cache.

With the selection in a file this repo writes, there is nothing to follow. The
watch loop, its systemd unit and the `inotify-tools` dependency are all gone.

**What went with it:** there is no automatic cycling. `Mod+Alt+B` is back, but
as a picker rather than a stepper — `wallpaper/pick.sh` lists
`~/Documents/Wallpapers` in fuzzel with ffmpeg-generated thumbnails (the first
frame, for the animated GIFs) and writes the choice to
`~/.config/niri/wallpaper-active` for `wallpaper-apply.sh` to paint. Wallpapers
also no longer retint the desktop — matugen re-derived the entire palette from
the current image, and the colours in `config/waybar/style.css` and
`config/mako/config` are now fixed values, the last ones it produced.

---

## One list of what's installed

`lib/manifest.sh` holds the apt packages, the `.deb` downloads, the snaps, and the version pins for Node, swww, Iosevka and Obsidian. `install.sh` installs from it; `doctor.sh` checks against it. They each kept their own copy before, with a comment on doctor's asking whoever edited one to remember the other — a promise no repo keeps, and a diagnostic that drifts from the installer is worse than none, since it invents problems and misses real ones.

`lib/common.sh` holds what all five scripts print with (`info`, `warn`, `ok`, `issue`, `section`) plus `pkg_installed` and `snap_install`. `pkg_installed` is the one worth not copy-pasting: `dpkg -s` exits 0 for packages in the `rc` state — removed, config files left behind — so it matches on the status field instead.

Build-only packages are tagged separately as `APT_BUILD_PACKAGES` (`liblz4-dev`, `libwayland-dev`, `wayland-protocols` for swww; `libgtk-4-dev` and `libgtk4-layer-shell-dev` for niri-tasks). `install.sh` installs them; `doctor.sh` deliberately doesn't check them. They're only needed to *compile* swww — the binary links `liblz4.so.1` from `liblz4-1`, a different package — so a machine that built swww and later cleaned up its build deps is perfectly healthy, and flagging it would be doctor crying wolf. The thing that actually matters, swww being installed and running, is checked directly.

---

## Which direction things move

The repo deploys to the machine. That is the only automatic direction:

```bash
bash configure.sh        # repo ──> machine
```

Edit configs **in the repo** and deploy them. That is why 18 of the 19 rows in
`lib/paths.sh` are byte-identical to the repo at any moment — nothing edits them
out on the machine, so nothing has to be captured back. (The exception is
ghostty, whose `command =` line `configure.sh` rewrites after copying.
`config.kdl` isn't a row at all: it's assembled with the machine-type include
before it's written, so it differs from the repo's copy by design.)

### capture/ — the few things the machine owns

Some settings can only be changed on the machine: a package manager records them,
a daemon keeps the state, or you tried something against the running compositor.
Those get a script each, and you run the one you need rather than a single command
that sweeps everything.

| Script | Pulls in |
|---|---|
| `capture/packages.sh` | Reports apt/snap packages installed but not in `lib/manifest.sh` |
| `capture/wallpapers.sh` | New images from `~/Documents/Wallpapers`, and which one is selected |
| `capture/vscode-extensions.sh` | Regenerates `config/Code/extensions.txt` |
| `capture/niri.sh` | The live `config.kdl`, for a layout change tried against the running compositor |

All take `--dry-run` to show what they would do, and `--yes` to skip the prompt
that protects uncommitted repo edits.

```bash
bash capture/wallpapers.sh --dry-run
bash capture/packages.sh
git diff                                # review before committing
```

Note that **none of these touch `lib/paths.sh`**. Everything `capture/` deals
in is something the path table never held. That was not true while
DankMaterialShell was here: its `settings.json` was a live file a GUI owned, it
needed a merge rather than a copy on the way out, and `capture/dms-settings.sh`
existed to bring it back.

**One row in the table is still not ours alone**, and it is worth knowing which.
VS Code rewrites `~/.config/Code/User/settings.json` whenever you change a
setting in its UI, and it prunes keys it considers dead. Deploying copies the
repo's version flat over the top, and no capture script brings yours back — so
change VS Code settings in the repo, or expect `doctor.sh` to tell you they
differ and decide then. Every other row really is written only by this repo.

There is deliberately **no** capture script for `.bashrc`, the window-rules,
waybar or ghostty. You would change those in a text editor, so change them in the
repo. A tool that moves files both ways is how you end up unable to say which
side is authoritative — which is what the old `update.sh` became.

`capture/packages.sh` reports rather than writes, because it is the one that
cannot tell what belongs: 143 packages are manually installed here and the
manifest declares 27, but most of the difference is Ubuntu's own base system.
`capture/packages-ignore.txt` filters the noise down to a reviewable list, and
`--add` / `--ignore` triage it one at a time.

### Re-running the installer is a no-op

`configure.sh` compares before it writes: a file that already matches is neither copied nor backed up. `config.kdl` is assembled first — the repo's copy plus the `laptop.kdl` or `desktop.kdl` include — so it can be compared as the finished article rather than copied and then appended to, which is what used to make it differ on every single run.

The upshot is that a re-run on an in-sync machine says "Nothing needed replacing — no backup taken" and touches nothing. `~/.config-backups` also keeps only the **5** most recent snapshots now; it grew to nine directories of near-identical files before anything pruned it. Directories in there that aren't named like a timestamp are left alone.

Every row in `lib/paths.sh` is a plain copy. There used to be a fourth kind,
`merge`, for a file the application owned and grew keys in — DankMaterialShell's
`settings.json` climbed a `configVersion` with each release, and copying the
repo's snapshot flat over a newer live file deleted every key the snapshot
predated (147 of them on this machine, including the display profiles and the
whole battery section). Nothing left writes its own config, so the kind and the
`merge_json` that implemented it are both gone.

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
| Desktop | waybar and mako actually running — neither is a systemd unit, so nothing else would notice. A missing bar is obvious; a missing notification daemon is not |
| Wallpaper | swww installed, its unit enabled and running, `wallpaper-apply.sh` present, **and that what's on screen is what `wallpaper-active` names** — the one check that catches a missed paint |
| Machine-type config | A machine with a battery whose `config.kdl` lacks the laptop include, an include that disagrees with the recorded machine type, or one pointing at a file that isn't there. Either type's files installed on the other (`laptop.jsonc` would put the battery module back on the bar). On a desktop, `/etc/xdg/monitors.xml` matching the repo |
| Dotfiles | `PATH`/env references in `.bashrc` and `.profile` that point at paths which no longer exist, skipping ones guarded by a file test |
| Config drift | Every file in `lib/paths.sh`: installed, matching the repo, and executable where the kind says so. `config.kdl` is compared separately, with the machine-type include stripped from both sides. Files `configure.sh` rewrites after copying — ghostty — are checked for presence but not content |
| niri-tasks | That `wt` is installed, the `niri-tasks.kdl` include exists (niri refuses to load a config whose include is missing), and the active-task overlay service is running |
| Leftovers | Files this repo used to install and no longer does — the workspace-task scripts, the fuzzel picker theme, the retired wallpaper-sync pair, and DankMaterialShell's config trees once the package itself is gone. Deleting them from the repo doesn't delete them from a machine that already has them |

The wallpaper row is the one worth running after a reboot: every other check can be green while the screen shows a stale image, because swww restores its own cache when it starts.
