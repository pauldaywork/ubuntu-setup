# Plan: Resolve remaining doctor.sh issues

**Created:** 2026-08-14
**Status:** Task 1 complete (2026-08-14). Tasks 2 and 3 open.
**Scope:** Finish the docker-ce → docker.io migration, de-duplicate Ghostty, and correct doctor.sh's `--fix` message.

---

## Context

The docker-ce → docker.io swap (commits `aac720b`, `d5539a0`) is mostly done. Of the four issues
`doctor.sh` reported on 2026-08-13, two closed on their own once the packages were installed:

| Original issue | Status |
|---|---|
| Missing apt packages (docker.io, docker-compose-v2, docker-buildx) | Partly closed — only `docker-compose-v2` outstanding (Task 1) |
| docker service not running | **Closed** — docker.io brought its own unit |
| Ghostty installed via both snap and deb | Open (Task 2) |
| `--fix` message advertises a repair that doesn't exist | Open (Task 3) |

The old docker-ce repo files (`/etc/apt/sources.list.d/docker.sources`, `docker.list.bak`,
`/etc/apt/keyrings/docker.asc`) have already been removed. `/var/lib/docker` was never touched,
so images and volumes survived the swap.

---

## Task 1 — Swap docker-compose-plugin for docker-compose-v2 ✅ DONE

> **Completed 2026-08-14.** The file conflict below was not hypothetical — `apt install
> docker-compose-v2` failed with `Sub-process /usr/bin/dpkg returned an error code (1)` on three
> separate attempts (08-13 11:58, 08-14 10:58 ×2) before `docker-compose-plugin` was removed. The
> removal at 10:59:08 unblocked the install at 10:59:18. Final state verified: `docker-compose-v2`
> 2.40.3 owns `/usr/libexec/docker/cli-plugins/docker-compose`, `docker compose version` reports
> 2.40.3, `docker-compose-plugin` is fully gone, `dpkg --audit` clean.
>
> Note for future swaps: apt reports this failure as a generic dpkg subprocess error. The package
> silently stays uninstalled while the rest of the transaction succeeds — which is why doctor.sh kept
> reporting `docker-compose-v2` missing alongside a successful docker.io install.

**Problem.** `docker compose` is currently served by `docker-compose-plugin` 5.1.4, left behind from
the docker-ce repo. That repo is gone, so the package is orphaned (apt priority 100, no upgrade
path, no security updates). `install.sh` specifies Ubuntu's `docker-compose-v2` instead.

**The trap.** Both packages ship the identical file `/usr/libexec/docker/cli-plugins/docker-compose`,
and `docker-compose-v2` declares only `Provides: docker-compose` — no `Conflicts` or `Replaces`
against `docker-compose-plugin`. A plain `apt install docker-compose-v2` therefore **fails at dpkg
unpack** with a file-overwrite error. `apt-get -s` does not predict this, because file conflicts
surface at unpack time rather than during dependency solving.

**Fix.** One transaction, using apt's `pkg-` suffix so the removal is sequenced before the unpack:

```bash
sudo apt install -y docker-compose-v2 docker-compose-plugin-
```

The trailing `-` on `docker-compose-plugin` means "remove this". No file conflict, and no window
where compose is unavailable.

**Verify.**

```bash
docker compose version          # expect: Docker Compose version v2.40.3 (was v5.1.4)
dpkg -S /usr/libexec/docker/cli-plugins/docker-compose   # expect: docker-compose-v2
```

**Rollback.** The docker-ce repo is gone, so `docker-compose-plugin` cannot be reinstalled from apt.
If v2 turns out to be a problem, the recovery path is Docker's upstream install docs, not apt. This
is a one-way door — but a low-stakes one, since compose v2.40.3 is current upstream and the file it
replaces is a standalone binary with no state.

**Downgrade note.** The version number goes *down* (5.1.4 → 2.40.3). That is expected, not a
regression: Docker's repo versions the plugin package independently of Compose itself, while Ubuntu
tracks the upstream Compose version. 2.40.3 is the newer Compose.

---

## Task 2 — Make the deb Ghostty canonical, drop the snap

**Problem.** Ghostty is installed twice: snap v1.3.1 (installed by `install.sh:176`) and deb
1.3.1ppa11 from the `avengemedia/danklinux` PPA. `/usr/bin` precedes `/snap/bin` in PATH, so the
**deb is what actually runs** — the snap has been dead weight.

**Decision.** Keep the deb. It comes from a PPA `install.sh` already adds for niri (`install.sh:46`),
so it needs no new repo; it avoids classic-snap confinement; and it matches what's already running.

### 2a. This machine

```bash
sudo snap remove ghostty
```

Safe to run from inside a Ghostty window — the running process is `/usr/bin/ghostty`, the deb copy,
so the session is unaffected. `snap remove` also saves an automatic snapshot of snap user data;
Ghostty keeps its config in `~/.config/ghostty/` (outside the snap), so nothing of value is in it.

### 2b. `install.sh`

- Remove `snap_install ghostty --classic` (line 176).
- Add `ghostty` to `APT_PACKAGES`, grouped with the other danklinux-PPA packages:

```diff
 APT_PACKAGES=(
     # window manager + shell
     niri
     dms
+    ghostty
```

### 2c. `doctor.sh`

- Remove `ghostty:classic` from `SNAP_PACKAGES` (line 106).
- Add `ghostty` to `APT_PACKAGES` (line 54ff), mirroring install.sh.
- **Keep** `check_duplicate "ghostty"` (line 272). Its advice — "to drop the snap copy (keeping the
  other)" — is now exactly right, so it stays useful as drift detection if a snap reappears.

### 2d. `README.md`

- Line 57: drop Ghostty from "Install snap packages (Firefox, VS Code, Ghostty, CMake)".
- Line 13 (`| Terminal | Ghostty |`) and line 137 (config path) need no change.

**Verify.**

```bash
command -v ghostty        # expect /usr/bin/ghostty
snap list ghostty         # expect "no matching snaps installed"
./doctor.sh               # ghostty duplicate check should pass
```

**No config migration needed.** Both copies read `~/.config/ghostty/config.ghostty`, which
`install-config.sh:85` already manages. The deb has been serving that config all along.

---

## Task 3 — Correct doctor.sh's `--fix` message

**Problem.** `doctor.sh:280` prints:

> Re-run with `--fix` to interactively repair dangling PATH/env references.

But `confirm_fix` is only wired into the NVM_DIR check (`doctor.sh:239`). There is no repair path for
the dangling-reference section at all, so the message sends you to a flag that will not touch what it
names.

**Decision.** Correct the message rather than implement the repair. Rationale:

1. There is no single correct repair for a dangling reference — delete the line, comment it out, or
   repoint it? The NVM_DIR case is automatable only because doctor.sh knows the right target.
2. `doctor.sh:2-10` states the script never changes software on its own; those checks "only print a
   suggested command". Rewriting `.bashrc` lines belongs in that human-judgment category.
3. Since the guard fix (`aa9a05e`), the check fires only on genuinely unconditional broken
   references — currently zero on this machine. Building an interactive editor for `.bashrc`, where a
   bad edit costs a working login shell, is a poor trade for how rarely it would run.

**Fix.** Narrow the message to what `--fix` actually repairs — do not delete it, since the flag is
real:

```diff
-    $FIX || note "Re-run with --fix to interactively repair dangling PATH/env references."
+    $FIX || note "Re-run with --fix to interactively repair a misconfigured NVM_DIR."
```

**Accepted trade-off.** A genuinely broken dotfile reference still has to be hand-edited, with no
guided path. Acceptable given how rarely the check fires; revisit if it starts firing across
machines, in which case a narrow "comment out the line" repair is ~15 lines on top of the existing
`backup`/`confirm_fix` scaffolding.

---

## Execution order

Tasks are independent; this order groups the sudo work first.

1. **Task 1** — compose swap (one command, needs sudo)
2. **Task 2a** — `snap remove ghostty` (needs sudo)
3. **Task 2b–2d** — edit install.sh, doctor.sh, README.md
4. **Task 3** — edit doctor.sh
5. Run `./doctor.sh` — expect **no issues found**
6. Commit 2b–2d and 3 together

Steps 1 and 2a need an interactive password; sudo is not passwordless in this environment, so they
must be run by hand (`! <command>` runs them inside a Claude Code session).

---

## Optional tidy-up (not blocking)

Left over from the migration, all harmless:

- **`rc`-state packages** — `containerd.io`, `docker-ce`, and `mako-notifier` are removed but retain
  config files. Purge with `sudo apt purge -y containerd.io docker-ce mako-notifier` if you want a
  clean `dpkg -l`. Note this would make doctor.sh's mako check report differently only in wording —
  `pkg_installed` already treats `rc` as not installed.
- **29 autoremove candidates** — orphaned dependencies (`python3-numpy`, `libgtkmm`, `slirp4netns`,
  and others) accumulated across the docker churn and earlier installs. Review before running:
  `apt-get -s autoremove` lists them. Some (e.g. `cmake-data`) may be wanted by the cmake snap.

## Definition of done

- [x] `docker compose version` reports v2.40.3, owned by `docker-compose-v2`
- [x] `docker-compose-plugin` no longer installed
- [ ] `snap list ghostty` reports nothing; `command -v ghostty` is `/usr/bin/ghostty`
- [ ] `install.sh` installs ghostty via apt, not snap
- [ ] `doctor.sh` package lists match `install.sh`
- [ ] `--fix` message names only the NVM_DIR repair
- [ ] `./doctor.sh` exits with "No issues found"
- [ ] Changes committed

---

## Affects the laptop too

Tasks 2b–2d and 3 change the shared scripts, so the laptop inherits them on its next
`git pull` + `install.sh` run. The laptop will *not* self-heal the machine-level drift, though —
if it also has both Ghostty copies or the orphaned compose plugin, Tasks 1 and 2a must be run there
as well. `./doctor.sh` on that machine will say which apply.
