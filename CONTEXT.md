# ubuntu-setup

A dotfiles repo and bootstrap for one person's Ubuntu + niri desktop: clone it on
a new machine, run it, and get the same environment. The vocabulary below exists
because this repo has two nouns that sound alike (packages and config files) and
two directions that sound alike (deploying and capturing), and conflating either
pair is how its past bugs happened.

## Language

### The two things a machine is given

**Package**:
Software installed from a package manager, an official installer, or a build —
apt, snap, rustup, nvm, a git tag. Declared in the manifest.
_Avoid_: dependency, app

**Manifest**:
The single declaration of what packages a machine is supposed to have.
_Avoid_: package list, requirements

**Managed file**:
A config file this repo owns outright and is the sole author of. Every managed
file appears in the path table, which pairs its repo location with its live
location.
_Avoid_: dotfile (too narrow — desktop entries and systemd units are managed
files too), tracked file (that means something else in git)

**Path table**:
The one list of managed files, their live destinations, and their kinds. The
single place that decides where anything lands.
_Avoid_: map, DOTFILES_MAP (that's the variable, not the concept), manifest (the
manifest is packages; this is files)

**Kind**:
The deploy rule for one managed file: whether it also gets the executable bit,
and whether it is deployed at all on this machine type.
_Avoid_: type, mode

### The two directions

**Deploy**:
Write managed files from the repo to their live locations. The only automatic
direction, and the reason the repo is authoritative: you edit config in the repo
and deploy it, never the other way round.
_Avoid_: install (that's packages), copy (that's the mechanism), sync (implies
bidirectional, which is exactly what this repo refuses to be)

**Install**:
Put packages on a machine. Strictly about packages; a config file is never
installed, it is deployed.
_Avoid_: set up, provision

**Capture**:
Record into the repo something only the machine could know — what a package
manager recorded, what a daemon holds, what you tried against the running
compositor. Deliberately per-thing and manual, never a sweep.
_Avoid_: pull (that's the internal helper, one file at a time), sync, update,
import

**Seed**:
Write a file only if it is absent, and never overwrite it afterwards. What the
repo does for a selection it must guarantee exists but has no business choosing
— the wallpaper selection, the window-rules profile, the niri-tasks include stub.
_Avoid_: default, initialise, deploy (deploying overwrites; seeding is defined by
not overwriting)

### What can be wrong with a machine

**Drift**:
A disagreement between what the repo declares and what the machine has. Reported,
never silently corrected.
_Avoid_: diff, out of date, broken

**Leftover**:
A file this repo used to deploy and no longer does. Removing it from the repo
does not remove it from a machine that already has it, so leftovers are found by
name rather than by absence from the path table.
_Avoid_: orphan, stale file, cruft

**Machine type**:
Laptop or desktop. Detected once on first run and recorded, so every later run
agrees with the first.
_Avoid_: form factor, platform, profile (a profile is a window-rules profile)

### Desktop concepts

**Selection**:
The machine-local choice of one option from a set the repo ships — which
wallpaper is painted, which window-rules profile is active. Seeded, never
deployed, and changed on the machine rather than in the repo.
_Avoid_: active, current, setting

**Window-rules profile**:
One named, self-contained set of layout and window rules, swappable at runtime.
_Avoid_: theme, layout, mode

**Feature directory**:
A repo directory holding everything for one capability whose files land in more
than one place, organised by what it is rather than by where its pieces go.
Contrast the mirror directories, whose layout repeats their destination's.
_Avoid_: module, bundle

**Mirror directory**:
A repo directory whose internal layout repeats the destination's, so a managed
file's live path can be read off its repo path.
_Avoid_: tree, sync directory
