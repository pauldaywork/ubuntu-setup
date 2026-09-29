# Hidden Focus-Mode Windows Draw No Backdrop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the niri "focus" window-rules profile, windows hidden for being unfocused (opacity 0) leave the wallpaper untouched, with no noise, saturation or blur patch where they sit.

**Architecture:** One edit to one config file. The `is-focused=false` rule in `config/niri/window-rules/focus.kdl` resets every background-effect field to its neutral value, so niri skips drawing the effect for those windows. The rest of the file keeps its structure, and the all-windows rule still gives the focused window its blur, noise and saturation.

**Tech Stack:** niri 26.04 KDL config, `niri validate`, `niri msg`, `grim` for screenshots.

**Spec:** Taskwarrior task `db7b1096-6ce6-4d49-8746-7dd6fd35e210` (read it with `task rc.json.array=on db7b1096-6ce6-4d49-8746-7dd6fd35e210 export`). Its description and annotations are the spec.

## Global Constraints

- Only the focus profile changes. `config/niri/window-rules/normal.kdl` stays as it is.
- Fix it in the `is-focused=false` rule's `background-effect`. Don't move the effect into an `is-focused=true` rule. That keeps the file's structure.
- Out of scope: the normal profile, the fuzzel launcher layer-rule, the waybar card blur.
- Done when: in focus mode the wallpaper where hidden windows sit looks untouched, the focused window keeps its blur/noise/saturation, and `niri validate` passes.

## Why this works (verified against niri v26.04 source)

The spec says the niri docs are silent and the source hasn't been checked. It has now been checked (tag `v26.04`):

- `src/layout/tile.rs`: `self.window.render_background_effect(...)` is called without `win_alpha`, so the opacity window rule does **not** fade the background effect. A window at `opacity 0.0` still draws its backdrop effect at full strength. That is the bug.
- `src/render_helpers/background_effect.rs`, `Options::is_visible()`:
  ```rust
  self.xray
      || self.blur
      || self.noise.is_some_and(|x| x > 0.)
      || self.saturation.is_some_and(|x| x != 1.)
  ```
  and `render()` returns early when this is false. So the effect is skipped entirely only when **all four** are neutral: `xray false`, `blur false`, `noise 0`, `saturation 1`.
- With only `blur false`, `noise 0.05`, `saturation 1.4` and `xray true` still come from the earlier all-windows rule. A later rule can override a value but not unset it. So the hidden window still draws an xray copy of the wallpaper, saturated and with noise added.

**One deliberate change from the spec's steps:** the spec says to try `xray false` only "if a patch remains". The source shows that with `xray true` left on, niri still renders an xray pass for every hidden window. At noise 0 and saturation 1 that pass should look identical to the wallpaper, but it is still a draw. `xray false` makes `is_visible()` false, so niri renders nothing for those windows. The plan sets `xray false` from the start. It stays inside the `is-focused=false` rule, as the spec decided. If the reviewer wants the spec's order instead, drop the `xray false` line in Step 3 and add it back only if Step 6 shows a patch.

## Background the engineer needs

- **Deploy path.** `lib/paths.sh` lists `config/niri/window-rules/focus.kdl` → `~/.config/niri/window-rules/focus.kdl` as a `copy` kind. `~/.config/niri/window-rules-active.kdl` is a symlink to whichever profile is active, and `config.kdl` does `include "window-rules-active.kdl"`. Deploying this one file is just a copy. Don't run the whole `configure.sh` from a worktree for this; the spec allows copying the file over.
- **Profile check.** `cat ~/.config/niri/.window-rules-profile` prints `focus` or `normal`. Mod+Alt+F (`window-rules/toggle.sh`) switches between them. The fix is only visible in `focus`.
- **Reload.** `niri msg action load-config-file` reloads the config (this is what `toggle.sh` calls).
- **Values are floats.** The file writes `noise 0.05` and `saturation 1.4`, so write `0.0` and `1.0` to match.
- **Commit style** in this repo: a plain imperative sentence, no `feat:` prefix (e.g. `Switch power profile from the laptop bar`).

---

### Task 1: Neutralise the background effect on hidden focus-mode windows

**Files:**
- Modify: `config/niri/window-rules/focus.kdl` (the last `window-rule`, `match is-focused=false`, at the end of the file)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing other tasks use. This is the only task.

There is no automated test harness for how the compositor draws. The "failing test" is a baseline screenshot showing the patch, and the "passing test" is the same shot after the fix plus `niri validate`.

- [ ] **Step 1: Confirm the setup and capture the baseline (the failing test)**

Make sure focus mode is active and at least two windows are open on the current workspace, so at least one is hidden beside the centred focused column:

```bash
cat ~/.config/niri/.window-rules-profile   # expect: focus  (if "normal", press Mod+Alt+F)
niri msg windows | grep -c '^Window'       # expect: 2 or more on this workspace
```

Take the baseline screenshot:

```bash
mkdir -p "$SCRATCH" && grim "$SCRATCH/before.png"
```

(`$SCRATCH` is any scratch directory outside the repo.) Open `before.png` and look at the wallpaper to the left and right of the focused window, where the hidden windows sit. Expected: a rectangle with rounded corners that is visibly more saturated and grainier than the wallpaper around it. If you see no patch at all, stop and report that. The bug isn't reproducing, so the fix can't be checked.

- [ ] **Step 2: Confirm the repo and live copies match before editing**

```bash
diff config/niri/window-rules/focus.kdl ~/.config/niri/window-rules/focus.kdl && echo SAME
```

Expected: `SAME`. If they differ, someone has changed the live file by hand. Stop and report it instead of overwriting it in Step 4.

- [ ] **Step 3: Edit the `is-focused=false` rule**

In `config/niri/window-rules/focus.kdl`, replace the last rule:

```kdl
window-rule {
    match is-focused=false
    background-effect {
        blur false
    }
    opacity 0.0
}
```

with:

```kdl
// Hidden windows must switch every effect back to neutral, not just blur. The
// rule above still gives them xray, noise and saturation (a later rule can
// override a value but not unset it), and niri draws the background effect
// without the window's opacity, so at opacity 0 those still paint a grainy,
// oversaturated patch on the wallpaper. With all four neutral, niri skips the
// effect entirely.
window-rule {
    match is-focused=false
    background-effect {
        xray false
        blur false
        noise 0.0
        saturation 1.0
    }
    opacity 0.0
}
```

Leave everything else in the file, and all of `normal.kdl`, untouched.

- [ ] **Step 4: Validate the profile on its own, then deploy it and validate the live config**

```bash
niri validate -c config/niri/window-rules/focus.kdl
```

Expected: last line `config is valid`, exit 0.

```bash
cp config/niri/window-rules/focus.kdl ~/.config/niri/window-rules/focus.kdl
niri validate
niri msg action load-config-file
```

Expected: `niri validate` ends with `config is valid`, and `load-config-file` exits 0 with no error notification from niri.

- [ ] **Step 5: Capture the after screenshot (the passing test)**

Use the same workspace and window layout as Step 1:

```bash
grim "$SCRATCH/after.png"
```

- [ ] **Step 6: Check both halves of "done"**

Open `before.png` and `after.png` side by side.

1. **Hidden windows:** where the hidden windows sit, `after.png` should show only the wallpaper, with no rectangle, grain or colour shift. If a patch is still there, stop and report it with both screenshots. The source analysis above predicts it can't happen, so that would mean it is wrong.
2. **Focused window:** the focused window should look the same as in `before.png`: 75% opacity, blurred and grainy wallpaper behind it, boosted saturation. Move focus to another column (Mod+Left/Right, or click it) and check that the new focused window gets the effect and the old one disappears cleanly.

- [ ] **Step 7: Check the normal profile is unaffected**

```bash
git diff --stat
```

Expected: only `config/niri/window-rules/focus.kdl` changed (the plan file too, if it isn't committed yet). Optionally press Mod+Alt+F to switch to normal, check that all windows are visible with their blur, then press Mod+Alt+F again to return to focus.

- [ ] **Step 8: Commit**

```bash
git add config/niri/window-rules/focus.kdl
git commit -m "Stop hidden focus-mode windows painting a patch on the wallpaper

The is-focused=false rule turned blur off but left xray, noise and
saturation inherited from the all-windows rule, and niri draws the
background effect regardless of window opacity. Reset all four so niri
skips the effect for hidden windows.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
