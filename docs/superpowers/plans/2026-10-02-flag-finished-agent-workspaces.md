# Flag Workspaces With a Finished Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a Claude Code agent finishes, its workspace's tab in the bottom dock gets a yellow border. The border goes once that workspace's terminal is focused.

**Architecture:** This uses the terminal bell and window urgency, with no new state. A Claude Code `Stop` hook writes BEL to the `claude` process's tty, which is a herdr pane. herdr forwards pane bells to its attached client, which writes BEL to Ghostty. Ghostty's `attention` bell feature asks niri for activation only while its window is unfocused. niri turns that request into window urgency, which makes the workspace urgent and clears when the window is focused. waybar's `niri/workspaces` module already puts `urgent` on that button. The stylesheet turns that into a yellow ring.

**Tech Stack:** POSIX sh, jq, Claude Code hooks (`~/.claude/settings.json`), herdr 0.9.1, Ghostty 1.3.1, niri 26.04, waybar GTK CSS.

**Spec:** Taskwarrior task `96a76e99-571d-47a9-a342-a58a2d4d64ca` (read it with `task rc.json.array=on 96a76e99-571d-47a9-a342-a58a2d4d64ca export`). Its description and annotations are the spec.

## Global Constraints

- Show it through niri window urgency, not a custom waybar module or state file.
- "Checked" means focusing the workspace's terminal window, which is when niri clears urgency. Don't track which herdr pane was looked at.
- The urgent style becomes a yellow border instead of red text, for any urgent workspace.
- Main agent only: subagents finishing must not flag anything.
- Out of scope: per-pane tracking inside herdr, desktop notifications or sounds, and agents other than Claude.
- Done when: an agent finishing on another workspace puts a yellow border on that workspace's tab, focusing that workspace's terminal clears it, and an agent finishing in the window you're looking at shows nothing.
- Commit style in this repo is a plain imperative sentence with no `feat:` prefix (e.g. `Switch power profile from the laptop bar`).

## What the research found (spec step 1)

The spec asks first whether herdr forwards a pane's bell to Ghostty. It does, and the rest of the bell path already works. These were checked against source and the live machine:

- **herdr v0.9.1 forwards bells.** `src/pane.rs` `publish_terminal_bells` queues `AppEvent::TerminalBell` for **any** pane that rings, visible or not. `src/server/headless/notifications.rs` sends it to the foreground client as `ServerMessage::TerminalBell`. `src/client/mod.rs` then writes that many `\x07` bytes to its own stdout, which is Ghostty. With no client attached the bell is dropped, which is fine because there is then no window to flag.
- **herdr's own "done" signals don't produce a bell.** `ui.sound` plays an mp3 and `ui.toast` draws a toast (`NotifyKind::Sound/Toast/SystemToast` in `src/protocol/wire.rs`). Neither reaches Ghostty as a bell, so they're no help here.
- **Ghostty 1.3.1 already has `attention` on.** The default is `bell-features = no-system,no-audio,attention,title,no-border`. In `src/apprt/gtk/class/window.zig` the bell handler skips attention when `gtk.Window.isActive()`, so a bell in the focused window does nothing. Otherwise it calls `winproto().setUrgent(true)`. On Wayland that is an `xdg_activation_v1` activation, which niri turns into window urgency. The skip gives us "finishing in the window you're looking at shows nothing" for free.
- **niri 26.04** shows `is_urgent` in `niri msg -j windows` and clears it when the window is focused. It also has `set-window-urgent --id`, which Task 2 uses to test the style without the bell.
- **Claude Code rings no bell when a turn finishes.** Its notifications fire for permission prompts and after 60 s of idle input, not on finishing. So something has to ring the bell, and that's the Stop hook.
- **Hooks have no controlling terminal.** From a Claude Code subprocess, `: > /dev/tty` fails with "No such device or address". But the `claude` process that spawned it has one (`ps -o tty= -p $PPID` gives `pts/N`). The hook walks up its ancestors to the first one with a tty and writes BEL to `/dev/pts/N`.

**One deliberate change from the spec's steps:** the spec treats the bell (step 1) and a Stop hook that calls `niri msg action set-window-urgent` (step 2) as alternatives. The bell route needs a Stop hook too, because nothing rings the bell on finish. But the hook only rings the bell. It doesn't look up the niri workspace, find the window or check focus, because herdr, Ghostty and niri already do that. `Stop` fires for the main agent only, since subagents fire `SubagentStop`. That covers "main agent only" with no code.

## Background the engineer needs

- **Managed files.** `lib/paths.sh` holds `DOTFILES_MAP`, rows of `<repo path>|<path under $HOME>|<kind>`. `exec` copies the file and sets the executable bit. `configure.sh` deploys every row.
- **`~/.claude/settings.json` is not a managed file.** Claude Code and herdr both write to it. herdr added its own `SessionStart` hook, which points at `~/.claude/hooks/herdr-agent-state.sh`. Never copy over it. Add our `Stop` entry with jq only when it's missing, the way `configure.sh` already installs the herdr plugins as explicit steps.
- **Don't edit `~/.claude/hooks/herdr-agent-state.sh`.** herdr overwrites it ("add custom hooks beside this file instead"). Our hook goes beside it as its own file.
- **Hooks are read when a session starts.** A Claude session that's already running won't fire the new hook. Test end to end with a fresh `claude`.
- **Don't run the whole `configure.sh` from a worktree.** Deploy the files this plan touches by hand, as the steps show.
- **The dock** is the bottom waybar, `waybar-dock.service`. It shares `~/.config/waybar/style.css` with the top bar and reloads when the file changes. If it doesn't, run `systemctl --user restart waybar-dock.service`.
- **Squashed buttons.** The dock draws each workspace in three module copies (`#workspaces.before`, `.current`, `.after`). It hides the buttons a copy shouldn't show by setting padding, margin and label size to zero, because GTK has no `display: none`. A real `border` would still draw 2 px on each squashed button and leave yellow slivers across the bar. An **inset `box-shadow`** takes up no layout space and draws nothing on a zero-width box, so that's what the ring uses. `#workspaces button` already sets `box-shadow: none`, so the urgent rule must out-rank it.

---

### Task 1: Ring the terminal bell when a Claude agent finishes

**Files:**
- Create: `config/claude/hooks/ring-bell-on-stop.sh`
- Modify: `lib/paths.sh` (add a row after the `config/claude/skills/worktree-setup/SKILL.md` row, around line 105)
- Modify: `configure.sh` (a new section after the `# herdr-speak` block, before the `# The DankMaterialShell theme path rewrite` comment)
- Modify: `config/ghostty/config.ghostty` (make `bell-features` explicit)

**Interfaces:**
- Consumes: nothing.
- Produces: the deployed hook `~/.claude/hooks/ring-bell-on-stop.sh` and a `hooks.Stop` entry in `~/.claude/settings.json`. When a Claude agent finishes in a Ghostty window that isn't focused, niri marks that window urgent (`is_urgent: true` in `niri msg -j windows`). Task 2 styles the result.

There's no test harness in this repo. The failing test is a run against the live compositor that shows the window isn't flagged before the hook exists.

- [ ] **Step 1: Write the urgency check (the failing test)**

Save this as `$SCRATCH/bell-check.sh`, where `$SCRATCH` is any scratch directory outside the repo. It finds this herdr session's Ghostty window and runs two cases:

- **Focused:** ring with the window focused, and it must not become urgent.
- **Away:** move to another workspace, ring, and it must become urgent. Then focus the window again, and it must clear.

It moves your focus for about three seconds and puts it back.

```sh
#!/bin/sh
# usage: bell-check.sh <command that rings the bell>
set -eu
ring="$1"
ws=$(niri msg -j workspaces | jq --arg n "$HERDR_SESSION" '.[] | select(.name == $n) | .id')
win=$(niri msg -j windows | jq --argjson ws "$ws" '[.[] | select(.workspace_id == $ws and .app_id == "com.mitchellh.ghostty")][0].id')
urgent() { niri msg -j windows | jq --argjson id "$win" '.[] | select(.id == $id) | .is_urgent'; }
echo "workspace $HERDR_SESSION ($ws), ghostty window $win"

niri msg action focus-window --id "$win"; sleep 0.5
sh -c "$ring" </dev/null; sleep 1
echo "focused: urgent=$(urgent) (want false)"

niri msg action focus-workspace-down; sleep 0.5
sh -c "$ring" </dev/null; sleep 1
away=$(urgent)
niri msg action focus-window --id "$win"; sleep 1
echo "away:    urgent=$away (want true)"
echo "back:    urgent=$(urgent) (want false)"
```

If `win` comes out `null`, check the app id with `niri msg -j windows | jq '.[].app_id'` and fix the `select`.

- [ ] **Step 2: Run it with nothing ringing to confirm the baseline**

Run: `sh "$SCRATCH/bell-check.sh" true`
Expected: `focused: urgent=false`, `away: urgent=false`, `back: urgent=false`. Nothing flags yet.

- [ ] **Step 3: Write the hook**

Create `config/claude/hooks/ring-bell-on-stop.sh`:

```sh
#!/bin/sh
# Claude Code Stop hook: ring the terminal bell when the main agent finishes a
# turn, so the workspace it runs on gets flagged in the dock.
#
# The bell does the rest without our help. herdr forwards any pane's bell to
# the Ghostty window attached to the session. Ghostty (bell-features attention)
# asks niri for attention only while that window is unfocused. niri marks the
# window, and so its workspace, urgent until the window is focused, and the
# dock styles urgent workspaces. Stop doesn't fire for subagents, which have
# SubagentStop.
#
# Hooks run without a controlling terminal, so /dev/tty isn't there. The claude
# process that spawned us has one, so walk up to the first ancestor with a tty
# and ring that.

cat >/dev/null

pid=$PPID
while [ "${pid:-1}" -gt 1 ]; do
    tty=$(ps -o tty= -p "$pid" | tr -d ' ')
    case "$tty" in
        ''|'?') pid=$(ps -o ppid= -p "$pid" | tr -d ' ') ;;
        *) printf '\a' >"/dev/$tty" 2>/dev/null; exit 0 ;;
    esac
done
exit 0
```

`cat >/dev/null` drains the hook's JSON input so Claude never writes into a closed pipe. Every path exits 0, so a hook that can't find a tty never shows up as an error in Claude.

- [ ] **Step 4: Run the check with the hook to confirm it passes**

Run: `sh "$SCRATCH/bell-check.sh" "sh $PWD/config/claude/hooks/ring-bell-on-stop.sh"`

The Bash tool's shell has no tty of its own, so the walk reaches the `claude` process. That's the same situation as a real hook.

Expected: `focused: urgent=false`, `away: urgent=true`, `back: urgent=false`.

If `away` is `false`, check each link on its own. `printf '\a' > /dev/$(ps -o tty= -p $PPID | tr -d ' ')` with this window unfocused should flag it. If it doesn't, the break is in herdr, Ghostty or niri rather than the hook, so stop and report it.

- [ ] **Step 5: Add the path-table row**

In `lib/paths.sh`, below `"config/claude/skills/worktree-setup/SKILL.md|.claude/skills/worktree-setup/SKILL.md|copy"`, add:

```bash
    # Rings the bell when a Claude agent finishes, so its workspace is flagged
    # in the dock. Registered in ~/.claude/settings.json by configure.sh, which
    # Claude and herdr also write, so that file isn't in this table.
    "config/claude/hooks/ring-bell-on-stop.sh|.claude/hooks/ring-bell-on-stop.sh|exec"
```

- [ ] **Step 6: Add the registration step to `configure.sh`**

Insert this after the `# herdr-speak` block's closing `fi`, before `# The DankMaterialShell theme path rewrite`:

```bash
# Claude Code Stop hook
# Registers ring-bell-on-stop.sh, deployed from the path table above, so a
# finished agent flags its workspace in the dock. settings.json is Claude's own
# file, and herdr adds its SessionStart hook to it as well, so this adds our one
# entry when it's missing and leaves everything else alone.
CLAUDE_SETTINGS="$USER_HOME/.claude/settings.json"
BELL_HOOK="$USER_HOME/.claude/hooks/ring-bell-on-stop.sh"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[ -s "$CLAUDE_SETTINGS" ] || echo '{}' >"$CLAUDE_SETTINGS"
if jq -e --arg h "$BELL_HOOK" '[.hooks.Stop[]?.hooks[]?.command] | any(contains($h))' \
    "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
    info "Claude Code Stop hook already registered"
elif jq --arg cmd "'$BELL_HOOK'" \
        '.hooks.Stop += [{"hooks": [{"type": "command", "command": $cmd, "timeout": 5}]}]' \
        "$CLAUDE_SETTINGS" >"$CLAUDE_SETTINGS.tmp" \
    && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"; then
    info "Registered the Claude Code Stop hook"
else
    rm -f "$CLAUDE_SETTINGS.tmp"
    warn "Could not register the Claude Code Stop hook — finished agents won't flag their workspace"
fi
```

If `settings.json` isn't valid JSON, both jq calls fail and the step warns without touching the file.

- [ ] **Step 7: Test the registration step against a scratch home**

This runs the exact block from `configure.sh` against a copy of the live settings. It runs it twice and checks that there's one entry and herdr's hook survives:

```bash
mkdir -p "$SCRATCH/home/.claude" && cp ~/.claude/settings.json "$SCRATCH/home/.claude/settings.json"
sed -n '/^# Claude Code Stop hook$/,/^fi$/p' configure.sh >"$SCRATCH/register.sh"
for i in 1 2; do USER_HOME="$SCRATCH/home" bash -c 'source lib/common.sh; source "$0"' "$SCRATCH/register.sh"; done
jq '[.hooks.Stop[].hooks[].command], [.hooks.SessionStart[].hooks[].command]' "$SCRATCH/home/.claude/settings.json"
```

Expected: the first run prints `Registered the Claude Code Stop hook` and the second prints `already registered`. The jq output shows exactly one Stop command, `'<scratch>/home/.claude/hooks/ring-bell-on-stop.sh'`, and the herdr `SessionStart` command still there. Then check a home with no settings file at all:

```bash
rm -rf "$SCRATCH/empty" && USER_HOME="$SCRATCH/empty" bash -c 'source lib/common.sh; source "$0"' "$SCRATCH/register.sh"
jq -c . "$SCRATCH/empty/.claude/settings.json"
```

Expected: `{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"'…/empty/.claude/hooks/ring-bell-on-stop.sh'","timeout":5}]}]}}`

- [ ] **Step 8: Make Ghostty's bell features explicit**

The dock flag now depends on `attention`, which is on by default. Writing it out keeps a future edit from dropping it without anyone noticing. In `config/ghostty/config.ghostty`, after the `app-notifications = …` line, add:

```
# A bell in an unfocused window asks niri for attention, which marks the window
# (and its workspace) urgent until it is focused. The dock shows that as a
# yellow ring, and Claude's Stop hook rings the bell when an agent finishes, so
# keep `attention`. These are Ghostty's defaults, written out for that reason.
bell-features = no-system,no-audio,attention,title,no-border
```

Then run: `ghostty +validate-config --config-file=config/ghostty/config.ghostty`
Expected: no output and exit 0.

- [ ] **Step 9: Deploy to this machine and check it end to end with a real agent**

```bash
install -Dm755 config/claude/hooks/ring-bell-on-stop.sh ~/.claude/hooks/ring-bell-on-stop.sh
cp config/ghostty/config.ghostty ~/.config/ghostty/config.ghostty && pkill -USR2 -u "$USER" -x ghostty
USER_HOME="$HOME" bash -c 'source lib/common.sh; source "$0"' "$SCRATCH/register.sh"
jq '.hooks.Stop' ~/.claude/settings.json
```

Expected: `Registered the Claude Code Stop hook`, and the Stop entry points at `/home/<you>/.claude/hooks/ring-bell-on-stop.sh`.

A fresh `claude -p` reads the new settings and fires Stop when it finishes. Its hook walks up to this pane's `claude` tty, the same as Step 4. `HERDR_ENV` is unset for it. Otherwise herdr's own SessionStart hook would report the nested session as this pane's agent and confuse the herdr session you're working in:

Run: `sh "$SCRATCH/bell-check.sh" "env -u HERDR_ENV claude -p 'Reply with the single word ok.' >/dev/null"`
Expected: `focused: urgent=false`, `away: urgent=true`, `back: urgent=false`.

- [ ] **Step 10: Commit**

```bash
git add config/claude/hooks/ring-bell-on-stop.sh lib/paths.sh configure.sh config/ghostty/config.ghostty
git commit -m "Ring the terminal bell when a Claude agent finishes"
```

---

### Task 2: Show an urgent workspace as a yellow ring in the dock

**Files:**
- Modify: `config/waybar/style.css` (the `@define-color` block at lines 22–30, and the `/* Urgent is the one state…` rule at about lines 190–194)

**Interfaces:**
- Consumes: niri window urgency. Task 1 produces it from a finished agent. This task raises it directly with `niri msg action set-window-urgent --id`, so it doesn't depend on Task 1 being deployed.
- Produces: nothing other tasks use.

- [ ] **Step 1: Capture the current urgent style (the failing test)**

Pick a window on a workspace that's named and not focused, and make it urgent:

```bash
niri msg -j workspaces | jq -r '.[] | "\(.id) \(.name) focused=\(.is_focused)"'
win=$(niri msg -j windows | jq '[.[] | select(.is_focused | not)][0].id'); echo "$win"
niri msg action set-window-urgent --id "$win"; sleep 1
grim "$SCRATCH/urgent-before.png"
```

Open `urgent-before.png` and look at the bottom dock. That workspace's name is red text with no ring. Leave the window urgent for Step 3.

- [ ] **Step 2: Replace the urgent rule**

In `config/waybar/style.css`, add a colour after `@define-color error        #f38ba8;`:

```css
@define-color attention  #f9e2af;
```

(Catppuccin Mocha yellow, the same palette that `warning` and `error` come from.)

Replace:

```css
/* Urgent is the one state that still stands out beside the card. */
#workspaces button.urgent,
#workspaces button.urgent:hover {
    color: @error;
}
```

with:

```css
/* Urgent is the one state that still stands out beside the card: a yellow
 * ring, for a workspace with something to look at. A Claude agent finishing
 * there rings the bell, Ghostty asks niri for attention, and niri clears it
 * when the workspace's terminal is focused.
 * An inset shadow rather than a border: it takes no room, so the name doesn't
 * shift when the ring comes and goes, and it draws nothing on the zero-width
 * buttons the side copies squash away (see "Slicing the sides"). A border would
 * leave a yellow sliver for every one of those. */
#workspaces button.urgent,
#workspaces button.urgent:hover {
    box-shadow: inset 0 0 0 2px @attention;
    border-radius: 8px;
}
```

- [ ] **Step 3: Deploy and check it passes**

```bash
cp config/waybar/style.css ~/.config/waybar/style.css; sleep 1
grim "$SCRATCH/urgent-after.png"
```

If the dock didn't redraw, run `systemctl --user restart waybar-dock.service; sleep 2` and capture again.

Open `urgent-after.png`. Expected:
- the urgent workspace's name is in the usual white with a rounded yellow ring around it;
- nothing yellow anywhere else on the dock, no slivers between names, and no ring on the card in the centre;
- the names are where they were in `urgent-before.png`.

Then clear it and check the ring goes:

```bash
niri msg action unset-window-urgent --id "$win"; sleep 1
grim "$SCRATCH/urgent-cleared.png"
```

Expected: the dock looks the way it does with nothing urgent.

- [ ] **Step 4: Commit**

```bash
git add config/waybar/style.css
git commit -m "Ring urgent workspaces in yellow in the dock"
```

- [ ] **Step 5: Acceptance check with a real agent (by the user)**

Ask the user to:
1. Start a fresh `claude` in a herdr pane on workspace A, give it a short task, and switch to workspace B before it finishes. When it finishes, A's tab in the dock gets a yellow ring.
2. Switch to A and focus its terminal. The ring goes.
3. Run another short task on A and stay on it. No ring appears.

Report what they saw. If step 1 shows no ring, run Task 1's `bell-check.sh` again to see which link failed.
