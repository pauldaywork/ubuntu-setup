# Move This Machine Off the Firefox Snap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** This machine runs Mozilla's Firefox `.deb` instead of the snap, and stays on it, so niri-tasks reports under `~/.local/share/niri-tasks/reviews` open instead of showing "Problem loading page".

**Architecture:** Two tasks. Task 1 fixes the repo. `install.sh` already moves a machine to the `.deb`, but unattended-upgrades undoes it. `install.sh` gains a `-1` pin on Ubuntu's `firefox` and a drop-in that lets unattended-upgrades update from `packages.mozilla.org`, and `doctor.sh` checks both. Task 2 is a one-off on this machine. It applies the two new files, moves the snap profile into `~/.mozilla` by hand, swaps the package and snap with the commands `doctor.sh` suggests, and checks the result with `doctor.sh`.

**Tech Stack:** bash, apt (`apt-cache policy`, `apt-config dump`, `/etc/apt/preferences.d`, `/etc/apt/apt.conf.d`), unattended-upgrades 2.12ubuntu9, snapd, xdg-utils.

**Spec:** Taskwarrior task `7360479b-ac77-4961-a7fb-1c27b61cf2c4`. Its description and notes are the spec (`task rc.json.array=on 7360479b-ac77-4961-a7fb-1c27b61cf2c4 export`). There is no separate spec file. **One change from the spec:** the spec puts changes to `install.sh` and `doctor.sh` out of scope. Paul agreed on 2026-10-28 to bring the unattended-upgrades fix into scope, because without it the switch is undone (see "Why the switch didn't stick").

## Global Constraints

- Apply the switch on this machine with the targeted commands `doctor.sh` suggests, not by rerunning all of `install.sh`.
- Move the profile by hand, once: `cp -a ~/snap/firefox/common/.mozilla/firefox ~/.mozilla/`, and only after checking that `~/.mozilla/firefox` does not exist. Never replace what is already there. `install.sh` gets no profile-migration code, because the repo assumes a clean install (89409be).
- Quit every Firefox process before copying the profile.
- Done when: `dpkg-query -W firefox` shows a Mozilla version with no `snap` in it, `snap list firefox` finds nothing, `xdg-settings get default-web-browser` prints `firefox.desktop`, all of `doctor.sh`'s Browser checks pass, Firefox opens with the old bookmarks and logins, and a niri-tasks Report or Explain branch deck opens in a new Firefox window on the task's workspace.
- Commits: Conventional Commits (`<type>(<scope>): <summary>`, imperative, lowercase first word, at most 72 characters), ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Facts the engineer needs

- **Why the snap fails.** Snap Firefox's AppArmor confinement refuses files in hidden home folders (`apparmor="DENIED"` in the journal, 2026-10-28). niri-tasks writes its reports under `~/.local/share/niri-tasks/reviews`.
- **Why the switch didn't stick** (found in `/var/log/apt/history.log`, 2026-10-28). `install.sh` did make the switch: at 2026-10-27 03:18, `apt install` downgraded `firefox` from `1:1snap1-0ubuntu8` to Mozilla's `158.0.1~build1`, and the snap was removed (`snap saved` still lists that snapshot as set 9). Then at 2026-10-28 09:54, `/usr/bin/unattended-upgrade` upgraded `firefox` from `158.0.1~build1` back to `1:1snap1-0ubuntu8`, and that package's postinst installed the snap again. The 1000 pin in `/etc/apt/preferences.d/mozilla` (written 2026-10-27 03:24) was in place the whole time.
- **Why the pin doesn't stop unattended-upgrades.** In `/usr/bin/unattended-upgrade`, `pinning_from_config()` pins every package file from an origin that isn't allowed to `NEVER_PIN` (-32768), and Mozilla's repo isn't allowed. That overrides the 1000. `find_better_version()` then picks any higher version from an allowed origin. Ubuntu's `1:1snap1-0ubuntu8` from `resolute` is allowed (`${distro_id}:${distro_codename}`), and its `1:` epoch makes it higher than every Mozilla version.
- **The two fixes. Each one alone stops the revert.**
  - `Unattended-Upgrade::Origins-Pattern:: "site=packages.mozilla.org";` in `/etc/apt/apt.conf.d/51unattended-upgrades-firefox`. Mozilla's origin is then allowed and keeps its 1000, so the installed Mozilla version outranks Ubuntu's 500, and unattended-upgrades also installs Firefox security updates. `site=` is the matcher to use. unattended-upgrades supports it (`match_whitelist_string`, `what in ("site",)`). Mozilla's `o=` field is an unwieldy `namespaces/moz-fx-productdelivery-pr-38b5/repositories/mozilla`. `Origins-Pattern` entries are added to `Allowed-Origins`; they don't replace them (`get_allowed_origins()`).
  - A second stanza in `/etc/apt/preferences.d/mozilla`: `Package: firefox`, `Pin: release o=Ubuntu`, `Pin-Priority: -1`. Ubuntu's transitional package can then never become a candidate, through apt or anything else. This was checked against a scratch `Dir::Etc::PreferencesParts`: `apt-cache policy firefox` shows both `1:1snap1-0ubuntu9.1` and `1:1snap1-0ubuntu8` at `-1`, and the candidate stays `159.0~build1`.
- **State of this machine on 2026-10-28:**
  - `/etc/apt/sources.list.d/mozilla.sources`, the key and the 1000 pin are present. Apt's candidate is `159.0~build1`.
  - `dpkg-query -W firefox` shows `1:1snap1-0ubuntu8`. `snap list firefox` shows `159.0-1`, rev 9137.
  - The snap profile is `~/snap/firefox/common/.mozilla/firefox` (199M). Its `profiles.ini` has one profile, `i0juz1tb.default` (`Default=1`), no `[Install…]` section, and no `installs.ini`.
  - `~/.mozilla/firefox` does not exist.
  - `~/.config/mozilla/firefox` **does exist**. Firefox 147 and later use the XDG directory when `~/.mozilla/firefox` is absent. That directory was created by the `.deb` on 2026-10-27, and it holds `b6cmama5.default-release` (150M), which `installs.ini` locks to install hash `4F96D1932A9F858E`, the `/usr/lib/firefox` install. That profile is not the old one, but Paul has used it since yesterday.
  - Two Firefox processes are running: the snap (`/snap/firefox/9137/usr/lib/firefox/firefox`) and yesterday's `.deb` (`/usr/lib/firefox/firefox-bin (deleted)`). The `.deb` one has a Claude sign-in tab open. Ask Paul to finish or close it before quitting.
  - `~/.config/mimeapps.list` `[Default Applications]` points `text/html`, `x-scheme-handler/http`, `https`, `about` and `unknown` at `firefox_firefox.desktop`, the snap's launcher. Outside GNOME and KDE (this is niri), `xdg-settings set default-web-browser` takes the generic path. That path sets `http https about unknown` and `text/html`, so it repoints all five, and no extra `xdg-mime` call is needed.
- **No test suite.** The repo has no test runner. The "tests" here are `doctor.sh` itself: run it before a change and see the new check fail, then make the change and see it pass.

---

### Task 1: Keep unattended-upgrades from restoring the Firefox snap

**Files:**
- Modify: `doctor.sh`. Add a block after the "The Firefox snap is still installed" check (around line 104) and before the Chrome checks.
- Modify: `install.sh:80-84`. Add a stanza to the `preferences.d/mozilla` heredoc, then a new `apt.conf.d` drop-in right after it.
- Modify: `README.md:61` (install step 1) and `README.md:477` (the doctor table's Browser row).

**Interfaces:**
- Produces: `/etc/apt/preferences.d/mozilla` with two stanzas (the existing 1000 pin, then Ubuntu's `firefox` at -1), and `/etc/apt/apt.conf.d/51unattended-upgrades-firefox` with one line. Task 2 writes the same two files on this machine with these exact contents.
- Consumes: `ok`, `issue` and `note` from `lib/common.sh`, which `doctor.sh` already sources.

- [ ] **Step 1: Add the failing doctor checks**

In `doctor.sh`, right after this block:

```bash
if snap list firefox &>/dev/null; then
    issue "The Firefox snap is still installed"
    note "  Remove with: sudo snap remove firefox"
fi
```

insert:

```bash
# unattended-upgrades pins every origin it isn't allowed to upgrade from to
# "never", Mozilla's 1000 pin included, so Ubuntu's 1:1snap1 package looks
# like an upgrade to it, and the package's postinst puts the snap back. It did
# that on 2026-10-28. install.sh allows Mozilla's site and pins Ubuntu's
# firefox to -1. Either one stops it.
if apt-config dump 2>/dev/null |
   grep -F 'Unattended-Upgrade::Origins-Pattern:: "site=packages.mozilla.org";' >/dev/null; then
    ok "unattended-upgrades may update Firefox from packages.mozilla.org"
else
    issue "unattended-upgrades isn't allowed packages.mozilla.org, so it can put the Firefox snap back"
    note "  Fix with: echo 'Unattended-Upgrade::Origins-Pattern:: \"site=packages.mozilla.org\";' | sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox"
fi
UNPINNED_SNAP_FIREFOX=$(apt-cache policy firefox 2>/dev/null |
    awk '$(NF-1) ~ /snap/ && $NF != -1 {print $(NF-1)}' | paste -sd' ')
if [ -z "$UNPINNED_SNAP_FIREFOX" ]; then
    ok "Ubuntu's snap-transitional firefox is pinned to -1"
else
    issue "Ubuntu's snap-transitional firefox isn't pinned to -1: $UNPINNED_SNAP_FIREFOX"
    note "  Add the Pin-Priority: -1 stanza from install.sh to /etc/apt/preferences.d/mozilla"
fi
```

The awk keys on the version-table lines only. `Installed: 1:1snap1-…` and `Candidate: …` have the label, not the version, in `$(NF-1)`.

- [ ] **Step 2: Run doctor and see both checks fail**

Run: `bash doctor.sh 2>&1 | grep -E 'unattended-upgrades|snap-transitional'`

Expected: these three lines, all with `[✗]` (the third check is the existing one, which also fails until Task 2):

```
[✗] firefox is Ubuntu's snap-transitional package (1:1snap1-0ubuntu8), not Mozilla's .deb
[✗] unattended-upgrades isn't allowed packages.mozilla.org, so it can put the Firefox snap back
[✗] Ubuntu's snap-transitional firefox isn't pinned to -1: 1:1snap1-0ubuntu9.1 1:1snap1-0ubuntu8
```

- [ ] **Step 3: Write both files from install.sh**

In `install.sh`, replace:

```bash
sudo tee /etc/apt/preferences.d/mozilla > /dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
```

with:

```bash
# The -1 stanza and the unattended-upgrades drop-in are there because the 1000
# pin alone didn't hold. unattended-upgrades pins every origin outside its
# allowed list to "never", Mozilla's included, so it took Ubuntu's 1:1snap1
# package for an upgrade and swapped it back in, snap and all. Allowing
# Mozilla's site fixes that and gets Firefox its security updates unattended.
# The -1 pin means nothing at all can choose Ubuntu's package again.
sudo tee /etc/apt/preferences.d/mozilla > /dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF
sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox > /dev/null <<'EOF'
Unattended-Upgrade::Origins-Pattern:: "site=packages.mozilla.org";
EOF
```

Also, in the comment above the Mozilla repo block (`install.sh:48-55`), replace `so the pin has to be 1000: only that priority lets apt pick a lower version.` with `so the pin has to be 1000: only that priority lets apt pick a lower version (and see below for why that isn't enough).` Leave the rest of that comment as it is.

- [ ] **Step 4: Syntax-check install.sh**

Run: `bash -n install.sh && echo ok`
Expected: `ok`

Don't run `install.sh`. Task 2 writes the same two files on this machine by hand.

- [ ] **Step 5: Update the README**

In `README.md:61`, replace:

`1. Add PPAs and repos for Niri/Ghostty, Firefox (Mozilla's, pinned over Ubuntu's snap) and the GitHub CLI`

with:

`1. Add PPAs and repos for Niri/Ghostty, Firefox (Mozilla's, pinned over Ubuntu's snap, which is pinned to -1, and allowed to unattended-upgrades so it can't swap the snap back) and the GitHub CLI`

In the doctor table's Browser row (`README.md:477`), replace:

```
| Browser | Firefox is Mozilla's `.deb` and not the snap-transitional package, no Firefox snap,
```

with:

```
| Browser | Firefox is Mozilla's `.deb` and not the snap-transitional package, that package pinned to -1 and unattended-upgrades allowed `packages.mozilla.org` (without them it puts the snap back), no Firefox snap,
```

and leave the rest of the row as it is.

- [ ] **Step 6: Check the README tree lint still passes**

Run: `bash doctor.sh 2>&1 | sed -n '/README structure tree/,$p'`
Expected: no `[✗]` lines. No new repo file was added, so the tree is unchanged.

- [ ] **Step 7: Commit**

```bash
git add install.sh doctor.sh README.md
git commit -m "$(cat <<'EOF'
fix(firefox): keep unattended-upgrades from restoring the snap

unattended-upgrades pins every origin outside its allowed list to
"never", Mozilla's included, so Ubuntu's 1:1snap1 firefox looked like
an upgrade. It swapped the .deb back for the snap on 2026-10-28, a day
after install.sh had made the switch.

install.sh now lets unattended-upgrades update from
packages.mozilla.org, which also gets Firefox its security updates,
and pins Ubuntu's firefox to -1. doctor.sh checks both.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Switch this machine to the .deb and keep the old profile

This task changes the machine, not the repo, so there is nothing to commit. Every `sudo` step needs Paul at the keyboard: ask them to run it with `! <command>`, or run it if the session can sudo. **Stop and report if any check doesn't show what's expected. Don't improvise.**

**Files:** none in the repo. On the machine: `/etc/apt/preferences.d/mozilla`, `/etc/apt/apt.conf.d/51unattended-upgrades-firefox`, `~/.mozilla/firefox` (new), `~/.config/mozilla/firefox` (renamed aside), `~/.config/mimeapps.list`.

**Interfaces:**
- Consumes: the two file contents from Task 1 Step 3, and the doctor checks from Task 1 Step 1.

- [ ] **Step 1: Put the unattended-upgrades guard in place first**

Run these before the switch, so the next unattended run can't undo it:

```bash
sudo tee /etc/apt/preferences.d/mozilla > /dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF
echo 'Unattended-Upgrade::Origins-Pattern:: "site=packages.mozilla.org";' |
    sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox > /dev/null
apt-cache policy firefox | sed -n 2,9p
```

Expected: `Candidate: 159.0~build1` (or a newer Mozilla version), and both `1:1snap1-…` lines end in `-1`.

- [ ] **Step 2: Quit every Firefox**

Ask Paul to finish or close the Claude sign-in tab in the old `.deb` Firefox, and then to quit both Firefoxes (Ctrl+Q in each).

Run: `pgrep -a firefox || echo none`
Expected: `none`. Don't go on while any Firefox process is left: copying a profile that is in use can corrupt `places.sqlite` and `logins.json`.

- [ ] **Step 3: Copy the snap profile into ~/.mozilla**

```bash
test ! -e ~/.mozilla/firefox && echo absent
```

Expected: `absent`. If it prints nothing, stop and report: the spec says never to replace what's there.

```bash
mkdir -p ~/.mozilla
cp -a ~/snap/firefox/common/.mozilla/firefox ~/.mozilla/
diff -rq ~/snap/firefox/common/.mozilla/firefox ~/.mozilla/firefox && echo same
grep -E '^(Path|Default)=' ~/.mozilla/firefox/profiles.ini
```

Expected: `same`, then `Path=i0juz1tb.default` and `Default=1`.

- [ ] **Step 4: Move yesterday's XDG profile aside**

Firefox uses `~/.mozilla/firefox` when it exists. But `~/.config/mozilla/firefox` locks a profile to this exact install (`installs.ini`: `4F96D1932A9F858E` → `b6cmama5.default-release`). Rename it, don't delete it, so Firefox can only find the old profile and nothing from yesterday is lost:

```bash
mv ~/.config/mozilla/firefox ~/.config/mozilla/firefox.deb-2026-10-27
ls ~/.config/mozilla
```

Expected: `firefox.deb-2026-10-27` only.

- [ ] **Step 5: Install Mozilla's .deb**

```bash
sudo apt install -y --allow-downgrades firefox
dpkg-query -W firefox
```

Expected: `firefox	159.0~build1` (or newer), with no `snap` in the version.

- [ ] **Step 6: Remove the snap**

```bash
sudo snap remove firefox
snap list firefox 2>&1
```

Expected: `error: no matching snaps installed`. `snap remove` keeps a snapshot of the snap's data (`snap saved`) for 31 days. The profile is already copied.

- [ ] **Step 7: Make the .deb the default browser**

```bash
xdg-settings set default-web-browser firefox.desktop
xdg-settings get default-web-browser
grep -c firefox_firefox.desktop ~/.config/mimeapps.list
```

Expected: `firefox.desktop`, then `0`. If the count is not 0, run `xdg-mime default firefox.desktop` with the MIME types still listed, and check again.

- [ ] **Step 8: Run doctor**

Run: `bash doctor.sh 2>&1 | sed -n '/firefox/I p'`

Expected: every line is `[✓]`:
- `firefox 159.0~build1 installed (Mozilla's .deb, not the snap-transitional package)`
- `unattended-upgrades may update Firefox from packages.mozilla.org`
- `Ubuntu's snap-transitional firefox is pinned to -1`
- `/etc/firefox/policies/policies.json matches the repo`
- `Firefox is the default browser`

The snap and Chrome checks print nothing when they pass.

- [ ] **Step 9: Check unattended-upgrades leaves Firefox alone**

```bash
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -iE 'firefox|packages that will be upgraded'
```

Expected: no line plans an upgrade of `firefox` to `1:1snap1-…`. A `Packages that will be upgraded:` line that lists `firefox` is only acceptable if a newer Mozilla version is out, and then the debug output names packages.mozilla.org as its origin.

- [ ] **Step 10: Check the old profile came across (Paul)**

Ask Paul to open Firefox with Mod+B and check four things:
- `about:profiles` shows `default` as the profile in use, with Root Directory `~/.mozilla/firefox/i0juz1tb.default`.
- The old bookmarks are there.
- `about:logins` lists the old saved logins.
- uBlock Origin is installed (force-installed by policy).

If `about:profiles` shows a new profile instead, quit Firefox and run `firefox -P`, then choose `default` and tick "Use the selected profile without asking". Don't delete the new profile.

- [ ] **Step 11: Check niri-tasks reports open (Paul)**

Ask Paul to open a niri-tasks Report or Explain branch deck from a task card. Expected: it opens in a new Firefox window on the task's workspace, showing the page and not "Problem loading page". Then confirm that AppArmor no longer refuses it:

```bash
journalctl -k --since '-10 min' | grep -i 'apparmor="DENIED"' | grep -i firefox || echo none
```

Expected: `none`.

- [ ] **Step 12: Report**

Report each Done-when item from Global Constraints with the output that shows it, and say where the old data was kept: the profile at `~/.config/mozilla/firefox.deb-2026-10-27` and the snap snapshot (`snap saved`). Paul can delete those once they're happy.
