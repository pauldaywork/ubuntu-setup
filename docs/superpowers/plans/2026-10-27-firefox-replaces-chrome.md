# Firefox Replaces Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Firefox, installed as a .deb from Mozilla's APT repo with uBlock Origin preinstalled by enterprise policy, the machine's browser, and remove Google Chrome from the repo and from this machine.

**Architecture:** install.sh adds Mozilla's repo and an apt pin, installs `firefox` from `lib/manifest.sh`, removes Ubuntu's Firefox snap, copies a repo-tracked `system/firefox-policies.json` to `/etc/firefox/policies/policies.json`, and makes `firefox.desktop` the default browser. doctor.sh checks each of those. Chrome's repo block, package, Mod+B bind, shortcut-page pattern and README lines are deleted.

**Tech Stack:** bash (install.sh, doctor.sh, lib/manifest.sh), apt pinning, Firefox enterprise policies (`ExtensionSettings`), xdg-utils, niri KDL config, Python (shortcuts/build.py).

**Spec:** Taskwarrior task `426dbb5f-8eb4-4efe-82ef-954e4036ddc2`. Read it with `task rc.json.array=on 426dbb5f-8eb4-4efe-82ef-954e4036ddc2 export`. Its description and notes are the spec.

## Global Constraints

- Firefox comes as a .deb from Mozilla's APT repo (`packages.mozilla.org`), with an apt pin at priority 1000 so it beats Ubuntu's snap-transitional package. Remove the snap if it is there.
- Add-ons are preinstalled with the enterprise policy `ExtensionSettings` (`force_installed`, AMO `install_url` by add-on id) in a repo-tracked policies.json installed to `/etc/firefox/policies/`.
- The add-on list is **uBlock Origin only** (`uBlock0@raymondhill.net`). It comes from this machine's snap profile, `~/snap/firefox/common/.mozilla/firefox/rtcdwxmu.default/extensions.json`. The user chose to leave out Proton Pass (a password manager; the spec excludes auth add-ons), GNOME Shell integration (does nothing under niri) and the en-US language pack (built into the .deb), and built-in add-ons are excluded anyway.
- Nothing is read or imported from Chrome: no extensions, bookmarks, history or passwords. Nothing from the Firefox profile beyond the add-on list is copied: no logins, cookies or settings.
- The repo assumes a clean install (commit 89409be). install.sh gets no code for migrating this machine. Chrome comes off this machine through manual one-off commands (Task 2), and doctor reports it if it is still there, the way it already reports `docker-ce`.
- Commits use Conventional Commits, e.g. `feat(install): …`, and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Match the surrounding code: `section`/`info`/`warn` in install.sh, `ok`/`issue`/`note` in doctor.sh, and a comment above each block that says *why*.

## Facts checked while planning (2026-10-27)

- Mozilla's signing key `https://packages.mozilla.org/apt/repo-signing-key.gpg` has fingerprint `35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`, the one Mozilla publishes.
- The repo is `https://packages.mozilla.org/apt`, suite `mozilla`, component `main`. Its newest firefox is `158.0.1~build1`.
- Ubuntu's transitional package is `1:1snap1-0ubuntu8` (installed here, with candidate `1:1snap1-0ubuntu9.1`). Its epoch `1:` makes it compare *higher* than Mozilla's versions, so two things follow:
  - The pin must be ≥1000, because only a priority of 1000 or more lets apt downgrade.
  - `apt install -y` refuses a downgrade without `--allow-downgrades` ("Packages were downgraded and -y was used without --allow-downgrades"). A fresh Ubuntu desktop has the transitional package installed, so install.sh needs that flag.
- apt's `Pin: origin <host>` matches the archive's hostname, so `Pin: origin packages.mozilla.org` is right even though the repo's Release file says `Origin: namespaces/moz-fx-…`.
- `https://addons.mozilla.org/firefox/downloads/latest/uBlock0@raymondhill.net/latest.xpi` returns a 301 to the slug URL, which then 302s to the current xpi. The id form works.
- Firefox on Linux reads system-wide policies from `/etc/firefox/policies/policies.json` (policy-templates docs).
- `xdg-settings` comes from `xdg-utils`. Under niri (`XDG_CURRENT_DESKTOP=niri`) it uses its generic path through `xdg-mime`/`~/.config/mimeapps.list`. It currently returns `google-chrome.desktop`.
- On this machine Chrome's apt source is `/etc/apt/sources.list.d/google-chrome.sources` (deb822, written by Chrome's own postinst), signed by `/usr/share/keyrings/google-chrome.gpg`, with `/etc/cron.daily/google-chrome`. The `.list` and keyring that install.sh writes are not what's live here.
- `shellcheck` is not installed. Syntax checks use `bash -n`.

## File structure

| File | Change |
|---|---|
| `doctor.sh` | New "Browser" block in section 1: Firefox is Mozilla's .deb, no Firefox snap, no Chrome, policies.json matches the repo, default browser is Firefox |
| `system/firefox-policies.json` | **New.** The `ExtensionSettings` policy (uBlock Origin) |
| `install.sh` | Drop the Chrome repo block. Add the Mozilla repo and pin. Add `--allow-downgrades` to the apt install. New Firefox section (remove snap, install policies, default browser). Drop "Log into Chrome" from the closing hint |
| `lib/manifest.sh` | `google-chrome-stable` → `firefox`, plus `xdg-utils` |
| `config/niri/config.kdl` | Mod+B spawns `firefox` |
| `shortcuts/build.py` | The `google-chrome` pattern becomes `firefox` |
| `config/fuzzel/fuzzel.ini` | The comment's example list loses "Chrome" |
| `README.md` | What's included, install steps, after-install, repo tree, doctor table |

---

### Task 1: doctor.sh checks the browser (red first)

The checks come first so they can be watched failing on this machine, which today has Chrome, the Firefox snap and no policies.

**Files:**
- Modify: `doctor.sh`. Insert after the `DEB_PACKAGES` loop that ends at line 82 (`done`) and before the Iosevka check.

**Interfaces:**
- Consumes: `pkg_installed` (lib/common.sh), `ok`/`issue`/`note`, `$DOTFILES`.
- Produces: the check reads `$DOTFILES/system/firefox-policies.json` (created in Task 2) and expects it at `/etc/firefox/policies/policies.json`. It expects the default browser to be `firefox.desktop`.

- [ ] **Step 1: Add the Browser checks**

Insert into `doctor.sh` right after the `DEB_PACKAGES` loop:

```bash
# Firefox is Mozilla's .deb, pinned over Ubuntu's snap-transitional package —
# see the Mozilla repo block in install.sh. The transitional package satisfies
# the APT_PACKAGES check above just as well, so tell them apart by version:
# Ubuntu's is 1:1snap1-…, Mozilla's a plain release number.
FIREFOX_VERSION=$(dpkg-query -W -f='${Version}' firefox 2>/dev/null)
if [[ "$FIREFOX_VERSION" == *snap* ]]; then
    issue "firefox is Ubuntu's snap-transitional package ($FIREFOX_VERSION), not Mozilla's .deb"
    note "  Check /etc/apt/preferences.d/mozilla exists, then: sudo apt install -y --allow-downgrades firefox"
elif [ -n "$FIREFOX_VERSION" ]; then
    ok "firefox $FIREFOX_VERSION installed from Mozilla's repo"
fi

if snap list firefox &>/dev/null; then
    issue "The Firefox snap is still installed alongside the .deb"
    note "  Remove with: sudo snap remove firefox"
fi

if pkg_installed google-chrome-stable; then
    issue "Google Chrome is installed — Firefox replaced it"
    note "  Remove with: sudo apt purge -y google-chrome-stable && sudo rm -f /etc/apt/sources.list.d/google-chrome.*"
fi

# The add-ons are force-installed by policy, so a matching policies.json is
# what decides whether Firefox has them.
FIREFOX_POLICIES=/etc/firefox/policies/policies.json
if cmp -s "$DOTFILES/system/firefox-policies.json" "$FIREFOX_POLICIES"; then
    ok "$FIREFOX_POLICIES matches the repo"
else
    issue "$FIREFOX_POLICIES is missing or differs from system/firefox-policies.json"
    note "  Fix with: sudo install -D -m 644 $DOTFILES/system/firefox-policies.json $FIREFOX_POLICIES"
fi

DEFAULT_BROWSER=$(xdg-settings get default-web-browser 2>/dev/null)
if [ "$DEFAULT_BROWSER" = firefox.desktop ]; then
    ok "Firefox is the default browser"
else
    issue "Default browser is ${DEFAULT_BROWSER:-unset}, not firefox.desktop"
    note "  Fix with: xdg-settings set default-web-browser firefox.desktop"
fi
```

- [ ] **Step 2: Check syntax**

Run: `bash -n doctor.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Run it and watch the checks fail**

Run: `bash doctor.sh 2>&1 | grep -E -i "firefox|chrome|policies|default browser"`
Expected on this machine before Task 2 (all ✗):
- `firefox is Ubuntu's snap-transitional package (1:1snap1-0ubuntu8), not Mozilla's .deb`
- `The Firefox snap is still installed alongside the .deb`
- `Google Chrome is installed — Firefox replaced it`
- `/etc/firefox/policies/policies.json is missing or differs …`
- `Default browser is google-chrome.desktop, not firefox.desktop`

- [ ] **Step 4: Commit**

```bash
git add doctor.sh
git commit -m "feat(doctor): check Firefox is the deb, default and policied" -m "Report the snap-transitional package, a leftover Firefox snap or
Chrome, a policies.json that differs from the repo's, and a default
browser other than Firefox.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: install.sh installs Firefox and drops Chrome; this machine follows

**Files:**
- Create: `system/firefox-policies.json`
- Modify: `install.sh:48-56` (Chrome repo block → Mozilla repo + pin), `install.sh:76` (apt install line), new section after the apt step (before `# ─── Docker permissions`), `install.sh:453-457` (closing hint)
- Modify: `lib/manifest.sh:600-602` area (`google-chrome-stable` → `firefox`), plus `xdg-utils`

**Interfaces:**
- Consumes: `section`/`info`/`warn`, `pkg_installed`, `$DOTFILES`.
- Produces: `/etc/apt/keyrings/packages.mozilla.org.asc`, `/etc/apt/sources.list.d/mozilla.sources`, `/etc/apt/preferences.d/mozilla`, `/etc/firefox/policies/policies.json` (a copy of `system/firefox-policies.json`), and `firefox.desktop` as the default browser. Task 1's doctor checks read these.

- [ ] **Step 1: Write the policy file**

Create `system/firefox-policies.json`:

```json
{
  "policies": {
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/uBlock0@raymondhill.net/latest.xpi"
      }
    }
  }
}
```

Validate it: `jq -e '.policies.ExtensionSettings | keys == ["uBlock0@raymondhill.net"]' system/firefox-policies.json` → `true`.

- [ ] **Step 2: Replace the Chrome repo block with Mozilla's**

In `install.sh`, replace lines 48–56 (from `# Google Chrome` through its closing `fi`) with:

```bash
# Firefox — Mozilla's own .deb rather than Ubuntu's snap, so it updates through
# apt like everything else and runs unconfined. Ubuntu's `firefox` is a transitional package that installs the snap, and its
# 1: epoch makes it outrank every Mozilla version, so the pin has to be 1000:
# only that priority lets apt pick a lower version. The key is checked against
# the fingerprint Mozilla publishes before apt is told to trust it.
MOZILLA_KEY=/etc/apt/keyrings/packages.mozilla.org.asc
MOZILLA_FPR=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
if [ ! -f /etc/apt/sources.list.d/mozilla.sources ]; then
    info "Adding Mozilla's Firefox repo"
    tmp=$(mktemp)
    wget -qO "$tmp" https://packages.mozilla.org/apt/repo-signing-key.gpg
    if ! gpg --show-keys --with-colons "$tmp" | grep -q "^fpr:*$MOZILLA_FPR:"; then
        rm -f "$tmp"
        echo "Mozilla's signing key does not have fingerprint $MOZILLA_FPR — stopping" >&2
        exit 1
    fi
    sudo install -m 644 "$tmp" "$MOZILLA_KEY"
    rm -f "$tmp"
    sudo tee /etc/apt/sources.list.d/mozilla.sources > /dev/null <<EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $MOZILLA_KEY
EOF
fi
sudo tee /etc/apt/preferences.d/mozilla > /dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
```

The pin is written on every run (it is three fixed lines) so an edited pin comes back.

- [ ] **Step 3: Let the apt install downgrade the transitional package**

Replace `install.sh` lines 74–76:

```bash
# The list itself lives in lib/manifest.sh, so doctor.sh can check the same one.
# APT_BUILD_PACKAGES is what swww needs to compile; see the note there.
sudo apt install -y "${APT_PACKAGES[@]}" "${APT_BUILD_PACKAGES[@]}"
```

with:

```bash
# The list itself lives in lib/manifest.sh, so doctor.sh can check the same one.
# APT_BUILD_PACKAGES is what swww needs to compile; see the note there.
# --allow-downgrades is for firefox alone: swapping Ubuntu's transitional
# package (1:1snap1-…) for Mozilla's is a downgrade by version number, and -y
# refuses one without the flag. Only the 1000 pin can make apt choose a lower
# version, so nothing else in the list is affected.
sudo apt install -y --allow-downgrades "${APT_PACKAGES[@]}" "${APT_BUILD_PACKAGES[@]}"
```

- [ ] **Step 4: Add the Firefox section after the apt step**

Insert just before `# ─── Docker permissions ───…` in `install.sh`:

```bash
# ─── Firefox ──────────────────────────────────────────────────────────────────
# The .deb is in by now, so the snap that Ubuntu ships can go without leaving
# the machine without a browser. snap remove keeps a snapshot of its profile
# (`snap saved`) for 31 days.
section "Setting up Firefox"

if snap list firefox &>/dev/null; then
    info "Removing the Firefox snap"
    sudo snap remove firefox
fi

# Add-ons are force-installed by enterprise policy, so a new profile gets them
# on first launch and they can't be removed by accident. Password managers and
# login add-ons are deliberately left out — those get signed into by hand.
FIREFOX_POLICIES=/etc/firefox/policies/policies.json
if cmp -s "$DOTFILES/system/firefox-policies.json" "$FIREFOX_POLICIES"; then
    info "$FIREFOX_POLICIES already matches the repo"
else
    sudo install -D -m 644 "$DOTFILES/system/firefox-policies.json" "$FIREFOX_POLICIES"
    info "Installed $FIREFOX_POLICIES — Firefox applies it at its next start"
fi

if [ "$(xdg-settings get default-web-browser 2>/dev/null)" != firefox.desktop ]; then
    info "Making Firefox the default browser"
    xdg-settings set default-web-browser firefox.desktop
fi
```

- [ ] **Step 5: Fix the closing hint**

Replace `install.sh` lines 455–457:

```bash
echo "  2. Run 'claude' to log into Claude Code"
echo "  3. Log into Chrome as needed"
echo "  4. Run 'bash extra.sh' if you want NVIDIA drivers"
```

with:

```bash
echo "  2. Run 'claude' to log into Claude Code"
echo "  3. Run 'bash extra.sh' if you want NVIDIA drivers"
```

- [ ] **Step 6: Update the manifest**

In `lib/manifest.sh`, replace:

```bash
    # apps (from external repos)
    taskwarrior
    google-chrome-stable
```

with:

```bash
    # apps (from external repos)
    taskwarrior
    # firefox — Mozilla's .deb, not Ubuntu's same-named snap-transitional
    # package; the pin install.sh writes decides which one this resolves to.
    firefox
    # xdg-settings, which install.sh uses to make Firefox the default browser.
    # Comes with ubuntu-desktop-minimal; named for the same reason as fuzzel.
    xdg-utils
```

- [ ] **Step 7: Check syntax and that Chrome is gone from these files**

Run: `bash -n install.sh && bash -n lib/manifest.sh && grep -n -i chrome install.sh lib/manifest.sh`
Expected: no syntax errors, and grep prints nothing (exit 1).

- [ ] **Step 8: Take Chrome off this machine (one-off, not repo code)**

These need sudo. Ask the user to run them with the `!` prefix:

```bash
! sudo apt purge -y google-chrome-stable
! sudo rm -f /etc/apt/sources.list.d/google-chrome.sources /etc/apt/sources.list.d/google-chrome.list /usr/share/keyrings/google-chrome.gpg /etc/apt/keyrings/google-chrome-keyring.gpg
```

Then check: `dpkg -l google-chrome-stable 2>/dev/null | grep ^ii; ls /etc/apt/sources.list.d | grep -i chrome; ls /etc/cron.daily | grep -i chrome` prints nothing.

- [ ] **Step 9: Run install.sh on this machine**

The installer is meant to be safe to re-run ("Re-running the installer is a no-op" in the README), and this run is the real test of the new steps. It needs sudo and may prompt, so ask the user to run it:

```bash
! bash install.sh
```

Expected in its output: `Adding Mozilla's Firefox repo`, apt replacing `firefox 1:1snap1-…` with `158.x~buildN`, `Removing the Firefox snap`, `Installed /etc/firefox/policies/policies.json`, `Making Firefox the default browser`, and no failure. Then check:

- `apt-cache policy firefox | head -4` shows Installed: `158…~build…` and Candidate the same, at priority 1000 from `packages.mozilla.org`
- `snap list firefox` → error "no matching snaps installed"
- `xdg-settings get default-web-browser` → `firefox.desktop`

- [ ] **Step 10: doctor goes green on the browser checks**

Run: `bash doctor.sh 2>&1 | grep -E -i "firefox|chrome|policies|default browser"`
Expected: only ✓ lines: `firefox 158… installed from Mozilla's repo`, `/etc/firefox/policies/policies.json matches the repo`, `Firefox is the default browser`. No Chrome or snap lines.

- [ ] **Step 11: Firefox has the add-on**

Ask the user to start Firefox (`firefox &`, or Mod+B once Task 3 is deployed) and confirm two things: `about:policies` lists `ExtensionSettings` with `uBlock0@raymondhill.net` under Active, and `about:addons` shows uBlock Origin installed and enabled. Then check from the shell: `jq -r '.addons[] | select(.id=="uBlock0@raymondhill.net") | .active' ~/.mozilla/firefox/*/extensions.json` → `true`.

- [ ] **Step 12: Commit**

```bash
git add system/firefox-policies.json install.sh lib/manifest.sh
git commit -m "feat(install): install Firefox from Mozilla's repo instead of Chrome" -m "Add Mozilla's APT repo with a 1000 pin over Ubuntu's snap-transitional
package, remove the Firefox snap, force-install uBlock Origin through a
repo-tracked enterprise policy and make Firefox the default browser.
Chrome's repo and package are gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Mod+B, the shortcut page and the docs say Firefox

**Files:**
- Modify: `config/niri/config.kdl:673`
- Modify: `shortcuts/build.py:199`
- Modify: `config/fuzzel/fuzzel.ini:29`
- Modify: `README.md` (lines 14–19 table, 60, step list, 82, tree at 173–174, doctor table at ~472)

**Interfaces:**
- Consumes: `firefox` on PATH (Task 2). `shortcuts/build.py --out DIR` writes `DIR/shortcuts.tsv` with one line per shortcut, the category in the third column.
- Produces: nothing later tasks use.

- [ ] **Step 1: Point Mod+B at Firefox**

In `config/niri/config.kdl` replace:

```kdl
    Mod+B hotkey-overlay-title="Open Browser" { spawn "google-chrome-stable"; }
```

with:

```kdl
    Mod+B hotkey-overlay-title="Open Browser" { spawn "firefox"; }
```

- [ ] **Step 2: Watch the shortcut page put Mod+B in the wrong category**

Run:
```bash
d=$(mktemp -d); python3 shortcuts/build.py --out "$d" >/dev/null && grep "Open browser" "$d/shortcuts.tsv"
```
Expected (red): the Mod+B line ends in `Screen & session	niri msg action spawn -- firefox`, not `Launch`.

- [ ] **Step 3: Update the Launch pattern**

In `shortcuts/build.py` replace:

```python
        if re.search(r"fuzzel|ghostty|google-chrome|shortcuts", text) and "wallpaper" not in text:
```

with:

```python
        if re.search(r"fuzzel|ghostty|firefox|shortcuts", text) and "wallpaper" not in text:
```

- [ ] **Step 4: Re-run and see it pass**

Run the same command as Step 2.
Expected: `Mod+B             Open browser … Launch	niri msg action spawn -- firefox`.

- [ ] **Step 5: Fix the fuzzel comment**

In `config/fuzzel/fuzzel.ini` replace `# hicolor: applications that ship their own icon (Chrome, Firefox, Code) drew` with `# hicolor: applications that ship their own icon (Firefox, Code) drew`.

- [ ] **Step 6: Update the README**

1. **What's included** table: after the `| Editor | …` row, add:
   ```markdown
   | Browser | Firefox (Mozilla's `.deb`, pinned over Ubuntu's snap), with uBlock Origin force-installed by enterprise policy (`system/firefox-policies.json`) |
   ```
2. **Install step 1** (line 60): `1. Add PPAs for Niri/Ghostty, Google Chrome and the GitHub CLI` becomes `1. Add PPAs and repos for Niri/Ghostty, Firefox (Mozilla's, pinned over Ubuntu's snap) and the GitHub CLI`.
3. **Install steps**: after step 2 (`Install all apt packages …`), insert a step and renumber the rest:
   `3. Remove Ubuntu's Firefox snap, install the add-on policy to `/etc/firefox/policies/`, and make Firefox the default browser`
4. **After the script finishes**: delete the line `- **Log into** Chrome as normal`.
5. **Repo tree**: under `system/`, the current lines are
   ```
   ├── system/                                 # Outside $HOME, so install.sh puts these in place with sudo
   │   └── monitors.xml                        # → /etc/xdg/  The login screen's monitor layout; desktops only
   ```
   Make them:
   ```
   ├── system/                                 # Outside $HOME, so install.sh puts these in place with sudo
   │   ├── firefox-policies.json               # → /etc/firefox/policies/policies.json  Add-ons Firefox force-installs
   │   └── monitors.xml                        # → /etc/xdg/  The login screen's monitor layout; desktops only
   ```
6. **Doctor table** (`| Area | What it looks for |`): after the `| Docker | … |` row, add:
   ```markdown
   | Browser | Firefox is Mozilla's `.deb` and not the snap-transitional package, no Firefox snap or Chrome left over, `/etc/firefox/policies/policies.json` matching the repo, and Firefox as the default browser |
   ```

- [ ] **Step 7: Chrome is gone from the repo**

Run: `git grep -n -i chrome -- ':!docs/superpowers'`
Expected: no output. Past plans under `docs/superpowers/` are history and stay as written.

- [ ] **Step 8: Deploy and check end to end**

Ask the user to run `! bash configure.sh`, which deploys config.kdl and rebuilds the shortcut page. Then:
- `bash doctor.sh` → Summary `No issues found`, or only issues unrelated to this task (say which). The README-tree check must pass, and config drift must report config.kdl in sync.
- `niri msg action spawn -- firefox` (what Mod+B runs) opens Firefox. Ask the user to confirm Mod+B opens it.

- [ ] **Step 9: Commit**

```bash
git add config/niri/config.kdl shortcuts/build.py config/fuzzel/fuzzel.ini README.md
git commit -m "feat(niri): open Firefox on Mod+B and document the switch" -m "Mod+B and the shortcut page's Launch category now name Firefox, and
the README covers the Mozilla repo, the add-on policy and the doctor
check. Chrome is gone from the repo.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
