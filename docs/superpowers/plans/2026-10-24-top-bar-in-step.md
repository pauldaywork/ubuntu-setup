# Top Bar In Step On Every Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mod+Alt+M shows the top bar on every screen at once and hides it on every screen at once, so the screens never get out of step.

**Architecture:** waybar draws one top bar per screen, and today SIGUSR1 *toggles* each one separately, so a bar created later (screen plugged in or turned back on, crash restart) starts hidden while the others show, and every press after that swaps them. Instead the top bar gets absolute actions — SIGUSR1 = show, SIGUSR2 = hide — and the Mod+Alt+M bind decides which to send from a marker file in `$XDG_RUNTIME_DIR`. The signal goes only to `waybar.service`'s main process via `systemctl --user kill --kill-whom=main`, never to the dock's waybar or to terminals the bar launched.

**Tech Stack:** waybar 0.15.0 (`on-sigusr1` / `on-sigusr2` accept `show`, `hide`, `toggle`, `reload`, `noop` — see `man 5 waybar`), niri `spawn-sh` binds, systemd 259 (`systemctl --user kill --kill-whom=main -s <SIG>`), POSIX sh.

**Spec:** Taskwarrior task `c2eb1b42-2348-4ed7-a2af-ec700212fd82` — its description and notes (`task rc.json.array=on c2eb1b42-2348-4ed7-a2af-ec700212fd82 export`). No separate spec file.

## Global Constraints

- Top bar config: `"on-sigusr1": "show"` and `"on-sigusr2": "hide"` in `config/waybar/config.jsonc`.
- Mod+Alt+M picks show or hide by checking a marker file in `$XDG_RUNTIME_DIR`; the file is gone at each login, so the bar still starts hidden (`"start_hidden": true` stays).
- Signal with `systemctl --user kill --kill-whom=main -s SIGUSR1|SIGUSR2 waybar.service`, not `killall`.
- A screen added while the bar is showing gets no bar until the next press — no watching niri for screen changes.
- `systemctl reload waybar` (SIGUSR2) now hides the bar; document "restart it instead".
- Out of scope: remembering bar visibility across logins; the dock bars' visibility.
- Binds stay on one line (`shortcuts/build.py` reads each bind's command from one line); the hotkey title stays `"Top Bar: Toggle"`.
- Commits: Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Facts the engineer needs

- **How to see whether the top bar is showing.** waybar hides a bar by sinking it to the bottom layer; its config puts it on the top layer when shown. So, per screen:

  ```bash
  niri msg -j layers | jq -r '.[] | select(.namespace=="waybar-top") | "\(.output) \(.layer)"'
  ```

  prints `eDP-1 Top` when shown and `eDP-1 Bottom` when hidden (one line per screen).
- **Two waybar processes.** `waybar.service` (the distro's unit, `/usr/lib/systemd/user/waybar.service`, `ExecReload=kill -SIGUSR2 $MAINPID`) runs `config.jsonc` — the top bar only. `waybar-dock.service` runs `config/waybar/dock-watch.sh`, which runs a second waybar on `dock.jsonc`. The dock bars set `"on-sigusr1": "noop"` because `killall` used to reach them; keep that as a guard against a hand-typed `killall -SIGUSR1 waybar`, but fix the comments that say Mod+Alt+M reaches them.
- **Deploying.** `./configure.sh` copies `config/waybar/*` to `~/.config/waybar/` and assembles `~/.config/niri/config.kdl` from `config/niri/config.kdl`. niri reloads its config on change; waybar must be restarted (`systemctl --user restart waybar`).
- **No test suite.** This repo has no test runner. Verification is the deployed config validating (`niri validate`), waybar staying up, and the layer check above before and after each press.

---

### Task 1: Absolute show/hide for the top bar, signalled only to its process

**Files:**
- Modify: `config/waybar/config.jsonc:31-42` (the `start_hidden` comment, plus two new keys)
- Modify: `config/niri/config.kdl:666-672` (Mod+Alt+M comment and bind)
- Modify: `config/waybar/dock.jsonc:15-17` and `config/waybar/dock.jsonc:56-60` (comments only)
- Modify: `config/waybar/dock-watch.sh:11-16` (comment only)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: marker file `$XDG_RUNTIME_DIR/waybar-top-shown` (exists ⇔ the last press showed the bar); `waybar.service`'s top bar reacting to SIGUSR1 = show, SIGUSR2 = hide. Task 2 checks these by hand.

- [ ] **Step 1: Record the current (broken) baseline**

Deploy nothing yet. Run:

```bash
niri msg -j layers | jq -r '.[] | select(.namespace=="waybar-top") | "\(.output) \(.layer)"'
grep -n 'on-sigusr' config/waybar/config.jsonc
```

Expected: one `waybar-top` line per screen; the grep prints nothing (the top bar has no `on-sigusr*` keys yet, so SIGUSR1 toggles and SIGUSR2 reloads).

- [ ] **Step 2: Give the top bar absolute show and hide**

In `config/waybar/config.jsonc`, replace this block:

```jsonc
    // Start hidden, and Mod+Alt+M reveals it. Only this bar: the workspace row
    // at the bottom (dock.jsonc) is how you tell where you are, so it comes up
    // whenever there is a workspace worth naming.
    //
    // Visibility is not persisted anywhere — waybar.service starts it fresh
    // each session, so a new process always starts from what this file says
    // and never from how you left the bar last time. The same goes for a
    // reload, so the bar disappears again after one, which looks like a crash
    // if you are not expecting it. Reload with `systemctl --user restart
    // waybar`: SIGUSR2, waybar's own reload, has aborted it.
    "start_hidden": true,
```

with:

```jsonc
    // Start hidden, and Mod+Alt+M reveals it. Only this bar: the workspace row
    // at the bottom (dock.jsonc) is how you tell where you are, so it comes up
    // whenever there is a workspace worth naming.
    //
    // waybar draws one of these per screen, and a bar it makes later — for a
    // screen plugged in or turned back on, or after a crash restart — starts
    // hidden too. So the signals below are absolute, not waybar's default
    // toggle, which flipped each screen's bar separately and left them out of
    // step for good after one such bar appeared. Mod+Alt+M (config.kdl) keeps
    // track of which one to send. A screen added while the bar is showing gets
    // no bar until the next press, which hides it everywhere; the one after
    // shows it everywhere.
    //
    // Visibility is not persisted anywhere — waybar.service starts it fresh
    // each session, so a new process always starts from what this file says
    // and never from how you left the bar last time.
    //
    // SIGUSR2 is hide here, not waybar's reload, so `systemctl --user reload
    // waybar` (which sends it) just hides the bar. Restart it instead:
    // `systemctl --user restart waybar`. The reload had aborted it anyway.
    "start_hidden": true,
    "on-sigusr1": "show",
    "on-sigusr2": "hide",
```

- [ ] **Step 3: Rewrite the Mod+Alt+M bind**

In `config/niri/config.kdl`, replace:

```kdl
    // waybar toggles its own visibility on SIGUSR1. DMS took a bar index here
    // because it could run several; one waybar process draws both bars now, and
    // the signal reaches the process rather than a bar, so every bar acts on it.
    // Which ones actually respond is therefore decided over in
    // config/waybar/config.jsonc: the dock sets "on-sigusr1": "noop" so that this
    // hides the top bar and leaves the workspace row where it is.
    Mod+Alt+M hotkey-overlay-title="Top Bar: Toggle" { spawn-sh "killall -SIGUSR1 waybar"; }
```

with:

```kdl
    // Shows or hides the top bar on every screen at once. The top bar shows on
    // SIGUSR1 and hides on SIGUSR2 (config/waybar/config.jsonc), rather than
    // toggling, so that one screen's bar can never be up while another's is
    // down. The marker in $XDG_RUNTIME_DIR says which was sent last; it is gone
    // at each login, when the bar starts hidden again. After a crash restart
    // the bar is hidden but the marker may say shown, and then the first press
    // hides (nothing to see) and the second shows.
    //
    // systemctl kill --kill-whom=main signals waybar.service's own process and
    // nothing else: not the dock's waybar, which runs under waybar-dock.service
    // and would reload on SIGUSR2, and not the terminals the bar's buttons
    // opened, which live in the same unit and would get it from a plain
    // systemctl kill.
    Mod+Alt+M hotkey-overlay-title="Top Bar: Toggle" { spawn-sh "f=\"$XDG_RUNTIME_DIR/waybar-top-shown\"; if [ -e \"$f\" ]; then rm -f \"$f\"; s=SIGUSR2; else touch \"$f\"; s=SIGUSR1; fi; systemctl --user kill --kill-whom=main -s \"$s\" waybar.service"; }
```

- [ ] **Step 4: Fix the dock comments that say Mod+Alt+M reaches them**

In `config/waybar/dock.jsonc`, replace:

```jsonc
// Both processes read the same style.css: waybar finds it next to whichever
// config -c names. Mod+Alt+M's `killall -SIGUSR1 waybar` reaches this process
// too, which is why both bars here keep "on-sigusr1": "noop".
```

with:

```jsonc
// Both processes read the same style.css: waybar finds it next to whichever
// config -c names. Mod+Alt+M signals only waybar.service's process, not this
// one; both bars here still keep "on-sigusr1": "noop" so that a hand-typed
// `killall -SIGUSR1 waybar` cannot hide them either.
```

and replace:

```jsonc
    // Mod+Alt+M hides the top bar, and it does that by sending SIGUSR1 — which
    // goes to every waybar process, this one included. noop opts this bar out,
    // and the card bar below as well; the top bar keeps the default "toggle"
    // and is the only one that responds.
    "on-sigusr1": "noop",
```

with:

```jsonc
    // Mod+Alt+M shows and hides the top bar by signalling waybar.service's
    // process alone, so it never reaches this one. noop is for a hand-typed
    // `killall -SIGUSR1 waybar`, which would: it opts this bar out, and the
    // card bar below as well.
    "on-sigusr1": "noop",
```

Leave the second `"on-sigusr1": "noop"` (the card bar, around line 163) and its surroundings unchanged.

In `config/waybar/dock-watch.sh`, replace:

```bash
# It has to be the whole process. The card is blurred by a niri layer-rule
# against its surface, so hiding it with CSS would leave a blurred card-shaped
# ghost, and waybar's two signals cannot say show *and* hide to these bars
# while Mod+Alt+M keeps SIGUSR1 for the top bar. A process that exists or
# does not is also the one state that cannot desync: every decision below
# re-checks reality rather than remembering it.
```

with:

```bash
# It has to be the whole process. The card is blurred by a niri layer-rule
# against its surface, so hiding it with CSS would leave a blurred card-shaped
# ghost. A process that exists or does not is also the one state that cannot
# desync: every decision below re-checks reality rather than remembering it.
```

- [ ] **Step 5: Check nothing still names the old mechanism**

Run:

```bash
grep -rn 'killall' config/ | grep -i waybar
grep -n 'on-sigusr' config/waybar/config.jsonc config/waybar/dock.jsonc
```

Expected: the first grep prints only the two dock.jsonc lines that mention a hand-typed `killall -SIGUSR1 waybar`. The second prints `"on-sigusr1": "show"` and `"on-sigusr2": "hide"` in config.jsonc and the two `"on-sigusr1": "noop"` lines in dock.jsonc.

- [ ] **Step 6: Deploy and validate**

Run:

```bash
./configure.sh
niri validate -c ~/.config/niri/config.kdl
rm -f "$XDG_RUNTIME_DIR/waybar-top-shown"
systemctl --user restart waybar
sleep 2
systemctl --user is-active waybar
journalctl --user -u waybar --since '-1min' --no-pager | grep -i -E 'sigusr|error|warn' || true
niri msg -j layers | jq -r '.[] | select(.namespace=="waybar-top") | "\(.output) \(.layer)"'
```

Expected: `niri validate` reports the config is valid; `active`; no journal line complaining about `on-sigusr1`/`on-sigusr2`; every `waybar-top` line ends in `Bottom` (fresh start, hidden).

- [ ] **Step 7: Run the bind's command and watch every screen follow**

Run the exact command the bind spawns, through niri so it gets niri's environment:

```bash
cmd='f="$XDG_RUNTIME_DIR/waybar-top-shown"; if [ -e "$f" ]; then rm -f "$f"; s=SIGUSR2; else touch "$f"; s=SIGUSR1; fi; systemctl --user kill --kill-whom=main -s "$s" waybar.service'
layers() { niri msg -j layers | jq -r '.[] | select(.namespace=="waybar-top") | "\(.output) \(.layer)"'; }
dock_pid=$(pgrep -f 'waybar -c .*dock.jsonc')
niri msg action spawn-sh -- "$cmd"; sleep 1; layers; ls "$XDG_RUNTIME_DIR/waybar-top-shown"
niri msg action spawn-sh -- "$cmd"; sleep 1; layers; ls "$XDG_RUNTIME_DIR/waybar-top-shown" 2>&1
niri msg action spawn-sh -- "$cmd"; sleep 1; layers
systemctl --user kill --kill-whom=main -s SIGUSR1 waybar.service; sleep 1; layers
echo "dock pid before $dock_pid, after $(pgrep -f 'waybar -c .*dock.jsonc')"
niri msg -j layers | jq -r '.[] | select(.namespace|test("^waybar-(dock|card)$")) | "\(.namespace) \(.output) \(.layer)"'
```

Expected, in order:
1. every `waybar-top` line `Top`, and the marker file is listed;
2. every line `Bottom`, and `ls` says `No such file or directory`;
3. every line `Top` again;
4. still every line `Top` — a second SIGUSR1 is a no-op, not a toggle (this is the fix);
5. the dock pid is unchanged (if the dock was running at all — it runs only while a workspace besides "general" is named), and the dock/card lines, if present, are on the `Top` layer as before.

Finish by pressing Mod+Alt+M once on the keyboard and confirm the bar hides on every screen — that exercises the real bind rather than the copy of its command.

If any step's output differs, stop and debug with superpowers:systematic-debugging before going on.

- [ ] **Step 8: Commit**

```bash
git add config/waybar/config.jsonc config/niri/config.kdl config/waybar/dock.jsonc config/waybar/dock-watch.sh
git commit -m "$(cat <<'EOF'
fix(waybar): keep the top bar in step on every screen

waybar draws one top bar per screen and SIGUSR1 toggled each one
separately, so a bar made later for a screen turned back on, or after a
crash restart, started hidden and every press after that swapped which
screens showed it. The top bar now shows on SIGUSR1 and hides on
SIGUSR2, and Mod+Alt+M picks one from a marker in $XDG_RUNTIME_DIR.

The bind signals only waybar.service's main process, so the dock's
waybar never gets SIGUSR2 (a reload, which has crashed it) and the
terminals the bar opened, which share its unit, get no signal either. `systemctl --user
reload waybar` now hides the bar; restart it instead.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Hand check on two screens (with the user)

This needs a second screen and someone at the keyboard; an agent cannot do it alone. Ask the user to run it, or to plug in a screen and let you drive the commands.

**Files:** none.

**Interfaces:**
- Consumes: Task 1's deployed config, the marker `$XDG_RUNTIME_DIR/waybar-top-shown`, and the `layers` check from Task 1 Step 7.
- Produces: nothing.

- [ ] **Step 1: Two screens, bar in step**

With two screens connected, press Mod+Alt+M a few times. After each press, run:

```bash
niri msg -j layers | jq -r '.[] | select(.namespace=="waybar-top") | "\(.output) \(.layer)"'
```

Expected: both screens' lines always say the same layer — both `Top` (bar visible on both) or both `Bottom`.

- [ ] **Step 2: Turn a screen off and on, with the bar hidden**

Hide the bar (both `Bottom`). On the laptop, turn the built-in screen off and back on (`niri msg output eDP-1 off`, then `niri msg output eDP-1 on`, or Mod+Alt+D). Press Mod+Alt+M.

Expected: the bar appears on both screens; both lines `Top`. Press again: both `Bottom`.

- [ ] **Step 3: Turn a screen off and on, with the bar showing**

Show the bar (both `Top`). Turn the built-in screen off and on again.

Expected: the screen that came back has no visible bar (its line says `Bottom`) — this is the accepted gap in the spec. Press Mod+Alt+M: both `Bottom`. Press again: both `Top`. From here on they stay in step.

- [ ] **Step 4: Dock untouched**

With a workspace besides "general" named (so the dock is up), press Mod+Alt+M several times.

Expected: the workspace row and card at the bottom never flicker, vanish or reload, and `pgrep -f 'waybar -c .*dock.jsonc'` prints the same pid throughout.

- [ ] **Step 5: Record the result**

If all four steps pass, the task's "Done when" is met. If any fails, note which and its `layers` output, and go back to Task 1 with superpowers:systematic-debugging. No commit for this task.
