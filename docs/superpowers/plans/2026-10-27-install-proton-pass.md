# Install Proton Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new machine gets the Proton Pass desktop app from `install.sh`, and `doctor.sh` reports when it is missing.

**Architecture:** `install.sh`'s `install_deb` moves into `lib/common.sh`, beside `install_release_binary`, and takes an optional SHA512: with one, it refuses a download that doesn't match and returns non-zero, which stops `install.sh` (it runs under `set -euo pipefail`). Proton Pass is installed by that one call, with `PROTON_PASS_VERSION` / `PROTON_PASS_SHA512` pinned in `lib/manifest.sh` like `WORKTRUNK_*` and `DOTENVX_*`. `doctor.sh`, `capture/packages.sh` and the README learn the new package.

**Tech Stack:** bash, dpkg/apt, `sha512sum` (coreutils), curl (which also reads `file://` URLs, so the tests use it), Docker with `ubuntu:26.04` to stand in for a fresh machine.

**Spec:** Taskwarrior task `39aa28f4-0f1f-4624-a7db-56823500695d`. Its description and notes are the spec (`task rc.json.array=on 39aa28f4-0f1f-4624-a7db-56823500695d export`). There is no separate spec file.

## Global Constraints

- Pin `PROTON_PASS_VERSION="1.43.0"` and `PROTON_PASS_SHA512` in `lib/manifest.sh`, like `WORKTRUNK_*` and `DOTENVX_*`.
- SHA512 for 1.43.0, from `https://proton.me/download/PassDesktop/linux/x64/version.json` (checked against the downloaded file on 2026-10-27): `ac19002dd7e5e6110fd5ca5d342d2cacbd2528d95966e83c1ac8df928e86506927d9cad1ffafaa1b542bb6ebf13aaa8f7b5e6d6499531a62aa82bbf82a706c62`
- .deb URL: `https://proton.me/download/pass/linux/proton-pass_${PROTON_PASS_VERSION}_amd64.deb`. The package name is `proton-pass`.
- Use the official .deb, not Flathub's `me.proton.Pass`. That build is community-made and unverified, and the repo has no Flatpak.
- In `install.sh`: download the pinned .deb, check its `sha512sum`, `dpkg -i` it, then `apt-get install -f`. Skip it when it's already installed (any version: newer versions arrive through the app's own update notice).
- A bad checksum stops the install.
- Out of scope: auto-updating it, and a Flatpak setup.
- Commits: Conventional Commits (`<type>(<scope>): <summary>`, imperative, lowercase, ≤72 chars), ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Facts the engineer needs

- **No test suite.** This repo has no test runner, and earlier plans keep their check scripts in a scratch directory, uncommitted. Do the same: set `SCRATCH` to a fresh `mktemp -d` once and reuse it.
- **What the .deb is** (inspected on 2026-10-27): package `proton-pass` 1.43.0, Electron 44.4.3. It has **no maintainer scripts at all** (`control` only), so unlike VS Code it adds no apt repo and needs no debconf answer. It installs `/usr/bin/proton-pass` (a symlink to `/usr/lib/proton-pass/Proton Pass`) and `/usr/share/applications/proton-pass.desktop` (`Exec=proton-pass %U`, no Wayland flags). It depends on `libgtk-3-0, libnotify4, libnss3, libxtst6, xdg-utils, libatspi2.0-0, libdrm2, libgbm1, libxcb-dri3-0` and one of a trash helper (`libglib2.0-bin` satisfies it).
- **A latent bug this plan fixes.** Today's `install_deb` runs `sudo dpkg -i` and *then* `sudo apt-get install -f -y`. Under `set -e`, `dpkg -i` fails when a dependency is missing, and that failure aborts `install.sh` before `apt-get -f` gets to fix it. VS Code never hit this because its deps were already present. Proton Pass will hit it on a bare system. The new helper tolerates the `dpkg -i` failure, runs `apt-get -f`, and then checks the package really is installed.
- **Wayland.** Electron 38 and later default to `--ozone-platform=auto`, which picks Wayland when `WAYLAND_DISPLAY` is set, so no flag is needed. Confirmed on this machine with 1.43.0 under niri: its child processes carry `--ozone-platform=wayland`, and `xlsclients` lists no Proton client. Task 3 re-checks this. Only if it ever regresses would the fix be a `~/.config/proton-pass-flags.conf`-style flag or a desktop-entry override with `--ozone-platform=wayland`; record that, don't build it.
- **This machine already has Proton Pass 1.43.0** (installed by hand), so a host run exercises the skip path. The real install path is exercised in a container in Task 3. **Do not remove the host's copy.**

---

### Task 1: Checksum-pinned `install_deb` in `lib/common.sh`

**Files:**
- Modify: `lib/common.sh` (new section after `install_release_binary`, around line 80)
- Modify: `install.sh:176-190` (delete the local `install_deb`)
- Test: `$SCRATCH/test-install-deb.sh` (scratch, not committed)

**Interfaces:**
- Produces: `install_deb <package> <url> [<sha512>]`. It returns 0 when the package is already installed (and does nothing) or when it installed it. It returns 1 when the download fails, when a sha512 was given and doesn't match (nothing installed), or when the package still isn't installed after apt's fix-up.
- Consumes: `pkg_installed`, `info` and `warn` from `lib/common.sh`.

- [ ] **Step 1: Write the failing test**

```bash
SCRATCH=$(mktemp -d); echo "$SCRATCH"
cat > "$SCRATCH/test-install-deb.sh" <<'EOF'
#!/usr/bin/env bash
# Exercises install_deb with sudo and pkg_installed stubbed, so nothing on the
# machine is touched. Usage: test-install-deb.sh <repo>
REPO="$1"; T=$(mktemp -d); fails=0
source "$REPO/lib/common.sh"

printf 'not really a deb\n' > "$T/fixture.deb"
URL="file://$T/fixture.deb"
GOOD=$(sha512sum "$T/fixture.deb" | cut -d' ' -f1)
BAD=$(printf '0%.0s' {1..128})

# Fake dpkg state: a package counts as installed when $T/state/<name> exists,
# and "sudo dpkg -i" creates it for the package under test.
mkdir -p "$T/state"
pkg_installed() { [ -f "$T/state/$1" ]; }
sudo() { echo "$*" >> "$T/sudo.log"; [ "$1 $2" = "dpkg -i" ] && touch "$T/state/$PKG"; return 0; }

check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
reset() { rm -rf "$T/state"/* "$T/sudo.log"; touch "$T/sudo.log"; }

reset; PKG=already; touch "$T/state/already"
install_deb already "file:///nonexistent" "$BAD" >/dev/null; rc=$?
check "installed: skips and returns 0" '[ $rc -eq 0 ] && [ ! -s "$T/sudo.log" ]'

reset; PKG=good
install_deb good "$URL" "$GOOD" >/dev/null; rc=$?
check "good sha: returns 0" '[ $rc -eq 0 ]'
check "good sha: dpkg -i then apt-get -f" 'grep -q "^dpkg -i " "$T/sudo.log" && grep -qx "apt-get install -f -y" "$T/sudo.log"'
check "good sha: temp .deb removed" '! ls /tmp/good-*.deb >/dev/null 2>&1'

reset; PKG=bad
out=$(install_deb bad "$URL" "$BAD" 2>&1); rc=$?
check "bad sha: returns 1" '[ $rc -eq 1 ]'
check "bad sha: nothing installed" '[ ! -s "$T/sudo.log" ]'
check "bad sha: says so" 'grep -q "Checksum mismatch" <<<"$out"'
check "bad sha: temp .deb removed" '! ls /tmp/bad-*.deb >/dev/null 2>&1'

reset; PKG=nosha
install_deb nosha "$URL" >/dev/null; rc=$?
check "no sha (DEB_PACKAGES): installs" '[ $rc -eq 0 ] && grep -q "^dpkg -i " "$T/sudo.log"'

reset; PKG=missing
install_deb missing "file:///nonexistent" >/dev/null 2>&1; rc=$?
check "download fails: returns 1" '[ $rc -eq 1 ] && [ ! -s "$T/sudo.log" ]'

reset; PKG=never
sudo() { echo "$*" >> "$T/sudo.log"; [ "$1 $2" = "dpkg -i" ] && return 1; return 0; }
install_deb never "$URL" >/dev/null 2>&1; rc=$?
check "dpkg -i fails: still runs apt-get -f" 'grep -qx "apt-get install -f -y" "$T/sudo.log"'
check "not installed after: returns 1" '[ $rc -eq 1 ]'

# A bad checksum must stop install.sh, which runs under set -euo pipefail.
bash -c 'set -euo pipefail; source "$1/lib/common.sh"
         pkg_installed() { return 1; }; sudo() { :; }
         install_deb bad "$2" "$3"; echo REACHED' _ "$REPO" "$URL" "$BAD" > "$T/sete.out" 2>&1; rc=$?
check "bad sha under set -e: stops the script" '[ $rc -ne 0 ] && ! grep -q REACHED "$T/sete.out"'

rm -rf "$T"
[ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
EOF
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash "$SCRATCH/test-install-deb.sh" "$PWD"`
Expected: FAIL lines and `install_deb: command not found` errors, because `install_deb` still lives in `install.sh`. The run ends with `N FAILED`.

- [ ] **Step 3: Move `install_deb` into `lib/common.sh` with the checksum**

In `lib/common.sh`, insert this new section straight after the closing `}` of `install_release_binary` and before `# ─── moving config files about`:

```bash
# ─── .deb downloads ───────────────────────────────────────────────────────────
# Download a .deb and install it, letting apt fetch whatever it depends on.
# Skipped when the package is already installed, at any version: DEB_PACKAGES
# update through the apt repo their postinst adds, and Proton Pass through its
# own update notice, so a re-run must never reinstall an older copy over them.
#
# Given a sha512 — pinned in lib/manifest.sh for a .deb with no apt repo behind
# it — a download that doesn't match is refused and the call fails, which stops
# install.sh under set -e rather than carrying on without the package.
#
#   install_deb <package> <url> [<sha512>]
install_deb() {
    local name="$1" url="$2" sha512="${3:-}"
    if pkg_installed "$name"; then
        info "Already installed: $name"
        return 0
    fi
    info "Downloading $name..."
    local tmp
    tmp=$(mktemp /tmp/"${name}"-XXXXXX.deb)
    if ! curl -fsSL -o "$tmp" "$url"; then
        warn "Could not download $url"
        rm -f "$tmp"; return 1
    fi
    if [ -n "$sha512" ] && ! echo "$sha512  $tmp" | sha512sum -c --quiet - >/dev/null 2>&1; then
        warn "Checksum mismatch for $url — not installed"
        rm -f "$tmp"; return 1
    fi
    # dpkg -i fails when a dependency is missing, leaving the package unpacked
    # but unconfigured; apt-get -f then installs the dependency and finishes the
    # job. Under set -e an unguarded dpkg -i would stop install.sh before that.
    sudo dpkg -i "$tmp" || true
    sudo apt-get install -f -y
    rm -f "$tmp"
    if ! pkg_installed "$name"; then
        warn "$name did not install — see above"
        return 1
    fi
    info "Installed: $name"
}
```

In `install.sh`, delete the local definition: the whole `install_deb() { … }` block (lines 176–190 today, from `install_deb() {` through its closing `}` and the blank line after it). Leave the `debconf-set-selections` line and the `DEB_PACKAGES` loop as they are. `install.sh` already sources `lib/common.sh` at the top, so the loop now calls the shared helper.

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
bash "$SCRATCH/test-install-deb.sh" "$PWD"
bash -n install.sh lib/common.sh
grep -n "install_deb" install.sh lib/common.sh
```
Expected: every line `PASS …`, then `ALL PASS`. `bash -n` is silent. grep shows the definition only in `lib/common.sh`, with the single call in `install.sh`'s `DEB_PACKAGES` loop.

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh install.sh
git commit -m "$(cat <<'EOF'
refactor(install): share install_deb and let it pin a sha512

Move install_deb into lib/common.sh beside install_release_binary and
give it an optional sha512, so a .deb with no apt repo behind it can be
pinned and refused when it doesn't match. A failed check returns
non-zero, which stops install.sh under set -e.

Also stop a missing dependency aborting the install: dpkg -i failed
under set -e before apt-get -f could fetch the dependency.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Install Proton Pass, and declare it everywhere the manifest is read

**Files:**
- Modify: `lib/manifest.sh` (versions section, after `DOTENVX_SHA256`)
- Modify: `install.sh` (`.deb` section, after the `DEB_PACKAGES` loop at the end of it, before `# ─── 3. snap packages`)
- Modify: `doctor.sh` (after the `DEB_PACKAGES` loop, around line 82)
- Modify: `capture/packages.sh` (the `printf` building `/tmp/capture-apt-repo.txt`)
- Modify: `README.md` (install step 5, around line 64; "One list of what's installed", around line 383)

**Interfaces:**
- Consumes: `install_deb <package> <url> [<sha512>]` from Task 1.
- Produces: `PROTON_PASS_VERSION` and `PROTON_PASS_SHA512` in `lib/manifest.sh`. The package name `proton-pass` is used literally in `install.sh`, `doctor.sh` and `capture/packages.sh`, the way `wt` and `dotenvx` are.

- [ ] **Step 1: Write the failing check**

```bash
cat > "$SCRATCH/check-declared.sh" <<'EOF'
#!/usr/bin/env bash
# Usage: check-declared.sh <repo>
REPO="$1"; fails=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
source "$REPO/lib/manifest.sh"
check "manifest pins 1.43.0" '[ "${PROTON_PASS_VERSION:-}" = 1.43.0 ]'
check "manifest pins its sha512" '[ "${PROTON_PASS_SHA512:-}" = ac19002dd7e5e6110fd5ca5d342d2cacbd2528d95966e83c1ac8df928e86506927d9cad1ffafaa1b542bb6ebf13aaa8f7b5e6d6499531a62aa82bbf82a706c62 ]'
check "install.sh installs it with the pin" 'grep -q "install_deb proton-pass .*PROTON_PASS_VERSION.*PROTON_PASS_SHA512" "$REPO/install.sh"'
check "doctor.sh checks it" 'grep -q "pkg_installed proton-pass" "$REPO/doctor.sh"'
check "capture/packages.sh declares it" 'grep -q "proton-pass" "$REPO/capture/packages.sh"'
check "README install steps mention it" 'sed -n "/^The script will:/,/^### 4/p" "$REPO/README.md" | grep -q "Proton Pass"'
check "README manifest section mentions it" 'grep -q "^\`lib/manifest.sh\` holds.*Proton Pass" "$REPO/README.md"'
check "scripts still parse" 'bash -n "$REPO/install.sh" "$REPO/doctor.sh" "$REPO/capture/packages.sh" "$REPO/lib/manifest.sh"'
[ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
EOF
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash "$SCRATCH/check-declared.sh" "$PWD"`
Expected: every check except `scripts still parse` is a FAIL, ending `7 FAILED`.

- [ ] **Step 3: Pin it in `lib/manifest.sh`**

Insert after the `DOTENVX_SHA256=…` line, with a blank line before it, in the versions section:

```bash
# Proton Pass — the password manager's desktop app. Proton ships a versioned
# .deb with no maintainer scripts and no apt repo, so it fits neither
# APT_PACKAGES nor DEB_PACKAGES (a vendor "latest" link, updated through apt
# afterwards); install.sh checks it against this sha512, the one Proton
# publishes in https://proton.me/download/PassDesktop/linux/x64/version.json.
# The official .deb rather than Flathub's me.proton.Pass, which is
# community-built and unverified. The pin is for a first install only: newer
# versions arrive through the app's own update notice, and a re-run of
# install.sh leaves whatever version is installed alone.
PROTON_PASS_VERSION="1.43.0"
PROTON_PASS_SHA512="ac19002dd7e5e6110fd5ca5d342d2cacbd2528d95966e83c1ac8df928e86506927d9cad1ffafaa1b542bb6ebf13aaa8f7b5e6d6499531a62aa82bbf82a706c62"
```

- [ ] **Step 4: Install it from `install.sh`**

Directly after the `DEB_PACKAGES` loop's closing `done` (still inside the "Installing .deb packages" section), add:

```bash

# Proton Pass has no apt repo, so it is pinned and checked rather than listed
# in DEB_PACKAGES — see lib/manifest.sh. A mismatched download stops the install.
install_deb proton-pass \
    "https://proton.me/download/pass/linux/proton-pass_${PROTON_PASS_VERSION}_amd64.deb" \
    "$PROTON_PASS_SHA512"
```

Don't guard it with `|| warn`. The spec says a bad checksum stops the install, and `set -euo pipefail` does that for an unguarded call.

- [ ] **Step 5: Check it in `doctor.sh`**

Directly after the `DEB_PACKAGES` loop's closing `done` in "Checking installation completeness", add:

```bash

if pkg_installed proton-pass; then
    ok "proton-pass installed"
else
    issue "proton-pass not installed"
    note "  Install with: bash install.sh (pinned $PROTON_PASS_VERSION, see lib/manifest.sh)"
fi
```

- [ ] **Step 6: Declare it in `capture/packages.sh`**

Replace:

```bash
# The .debs install through dpkg, so apt-mark counts them as manual too: declare
# them here or they show up as undeclared.
printf '%s\n' "${APT_PACKAGES[@]}" "${APT_BUILD_PACKAGES[@]}" \
    "${DEB_PACKAGES[@]%%|*}" | sort -u > /tmp/capture-apt-repo.txt
```

with:

```bash
# The .debs install through dpkg, so apt-mark counts them as manual too: declare
# them here or they show up as undeclared. proton-pass is one of them, pinned
# separately in lib/manifest.sh.
printf '%s\n' "${APT_PACKAGES[@]}" "${APT_BUILD_PACKAGES[@]}" \
    "${DEB_PACKAGES[@]%%|*}" proton-pass | sort -u > /tmp/capture-apt-repo.txt
```

- [ ] **Step 7: Mention it in `README.md`**

Install step 5 currently reads:

```
5. Install VS Code from its official `.deb`, which adds Microsoft's apt repo for updates (the `.deb` rather than the snap because the snap forces X11)
```

Change it to:

```
5. Install VS Code from its official `.deb`, which adds Microsoft's apt repo for updates (the `.deb` rather than the snap because the snap forces X11), and Proton Pass from its official `.deb`, pinned and checked against Proton's SHA512 since it has no apt repo (it updates itself through the app's own notice)
```

In "One list of what's installed", change:

```
and the version pins for Node, swww, Iosevka, bluetui, worktrunk and dotenvx.
```

to:

```
and the version pins for Node, swww, Iosevka, bluetui, worktrunk, dotenvx and Proton Pass.
```

- [ ] **Step 8: Run the checks to verify they pass**

Run:
```bash
bash "$SCRATCH/check-declared.sh" "$PWD"
bash "$SCRATCH/test-install-deb.sh" "$PWD"
bash capture/packages.sh | sed -n '/NOT declared/,/^$/p' | grep -c proton-pass
```
Expected: both scripts end with `ALL PASS`. The `grep -c` prints `0`, because `proton-pass` no longer shows as undeclared. Before this task it was listed there, since this machine has it installed by hand.

- [ ] **Step 9: Commit**

```bash
git add lib/manifest.sh install.sh doctor.sh capture/packages.sh README.md
git commit -m "$(cat <<'EOF'
feat(install): install Proton Pass from its official .deb

Proton ships only a versioned .deb with no apt repo, so pin 1.43.0 and
the SHA512 Proton publishes in version.json, like worktrunk and dotenvx.
A re-run skips it once installed, at any version, since the app brings
its own updates. The official .deb rather than Flathub's me.proton.Pass,
which is community-built and unverified.

doctor.sh reports it missing, and capture/packages.sh counts it as
declared.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Verify on a fresh system, on this machine, and under niri

No code changes unless a check fails. This task proves the "Done when" notes of the spec.

**Files:**
- Test: `$SCRATCH/fresh-install.sh` (scratch, not committed)

**Interfaces:**
- Consumes: `install_deb` (Task 1), `PROTON_PASS_VERSION` / `PROTON_PASS_SHA512` (Task 2).

- [ ] **Step 1: Fresh install, re-run skip and bad checksum, in a bare Ubuntu 26.04 container**

This runs the real helper against the real download, with real dpkg and apt, on a system that has none of Proton Pass's dependencies, so it also exercises the `dpkg -i` → `apt-get -f` fix-up. It runs as root, so `sudo` is a pass-through.

```bash
cat > "$SCRATCH/fresh-install.sh" <<'EOF'
#!/usr/bin/env bash
# Runs inside ubuntu:26.04 with the repo mounted read-only at /repo.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
sudo() { "$@"; }
source /repo/lib/common.sh
source /repo/lib/manifest.sh
URL="https://proton.me/download/pass/linux/proton-pass_${PROTON_PASS_VERSION}_amd64.deb"

echo "── fresh install"
install_deb proton-pass "$URL" "$PROTON_PASS_SHA512"
dpkg-query -W proton-pass
test -x /usr/bin/proton-pass

echo "── re-run"
install_deb proton-pass "$URL" "$PROTON_PASS_SHA512" | grep -q "Already installed: proton-pass"
echo "skipped"

echo "── bad checksum"
dpkg -r proton-pass >/dev/null
if ( install_deb proton-pass "$URL" "$(printf '0%.0s' {1..128})" ); then
    echo "FAIL: bad checksum installed"; exit 1
fi
if pkg_installed proton-pass; then echo "FAIL: still installed"; exit 1; fi
echo "refused"
echo "FRESH OK"
EOF
docker run --rm -v "$PWD:/repo:ro" -v "$SCRATCH:/scratch:ro" ubuntu:26.04 bash /scratch/fresh-install.sh
```

Expected: `install_deb`'s `[+] Downloading proton-pass...`, then dpkg reporting unmet dependencies (this is expected), then apt installing them and `[+] Installed: proton-pass`. Then `proton-pass	1.43.0`, `skipped`, `[!] Checksum mismatch … — not installed`, `refused`, and finally `FRESH OK`. If `ubuntu:26.04` can't be pulled, use `ubuntu:latest` and say so in the report.

- [ ] **Step 2: Re-run skip on this machine**

This machine already has 1.43.0. Run only the .deb step with the real `sudo`. Nothing is downloaded or changed:

```bash
bash -c 'source lib/common.sh; source lib/manifest.sh
         install_deb proton-pass "https://proton.me/download/pass/linux/proton-pass_${PROTON_PASS_VERSION}_amd64.deb" "$PROTON_PASS_SHA512"'
```

Expected: `[+] Already installed: proton-pass`, with no sudo prompt.

- [ ] **Step 3: doctor.sh passes**

Run: `bash doctor.sh 2>&1 | grep proton-pass`
Expected: `[✓] proton-pass installed`. No `[✗]` line mentions proton-pass. Other, unrelated issues doctor reports on this machine aren't this task's concern, but list them in the report.

- [ ] **Step 4: Runs natively on Wayland under niri**

Start it if it isn't running (`pgrep -f "/usr/lib/proton-pass/Proton Pass" || (proton-pass >/dev/null 2>&1 &)`, then wait a few seconds), and run:

```bash
pgrep -af "Proton Pass" | grep -o "ozone-platform=[a-z]*" | sort -u
xlsclients 2>/dev/null | grep -i proton || echo "no X11 client"
niri msg -j windows | jq -r '.[] | select(.app_id=="proton-pass") | .title'
```

Expected: `ozone-platform=wayland` (an empty `ozone-platform=` line may also appear, from the zygote, and is fine), `no X11 client`, and `Proton Pass`. If the window instead shows up in `xlsclients`, it is on Xwayland. In that case don't build a fix. Add a note to the task saying the fix needed is to launch it with `--ozone-platform=wayland` (for example, a desktop-entry override in `~/.local/share/applications/proton-pass.desktop`):
`niritasks task note 39aa28f4-0f1f-4624-a7db-56823500695d "Xwayland: …"`

- [ ] **Step 5: Report**

No commit. Report the output of Steps 1–4. Clean up with `rm -rf "$SCRATCH"`.
