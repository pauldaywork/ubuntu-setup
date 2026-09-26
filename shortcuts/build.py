#!/usr/bin/env python3
"""Build the shortcut page and its fuzzel search list from the real configs.

Reads niri's binds (config.kdl, laptop.kdl, desktop.kdl and niri-tasks.kdl),
herdr's config.toml and ghostty's config, and writes two files into --out:

  shortcuts.html  the interactive page behind Mod+Alt+Ctrl+/ (page.html + the data)
  shortcuts.tsv   one line per shortcut for fuzzel behind Mod+Alt+/:
                  "<what fuzzel shows>\t<command Enter runs, or nothing>"

configure.sh runs this on every deploy, so the page lists what is bound rather
than what was bound when someone last remembered to update it. herdr is the one
source that isn't a file here: its defaults live in its binary, so they are
copied below from its config reference and pinned to HERDR_VERSION.
"""

import argparse
import datetime
import json
import os
import re
import shlex
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HOME = Path.home()

# ─── niri ─────────────────────────────────────────────────────────────────────

def tokenize(text):
    """KDL tokens, as far as a binds block needs them: words, strings, braces,
    semicolons and newlines. Comments are dropped."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            yield ("nl", None); i += 1
        elif c.isspace():
            i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            i = text.index("*/", i) + 2
        elif c == '"':
            i += 1; out = []
            while text[i] != '"':
                if text[i] == "\\":
                    nxt = text[i + 1]
                    out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt)); i += 2
                else:
                    out.append(text[i]); i += 1
            i += 1
            yield ("str", "".join(out))
        elif c in "{};":
            yield (c, None); i += 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in '{};"':
                j += 1
            yield ("word", text[i:j]); i = j


def binds_blocks(text):
    """The text inside every top-level `binds { … }` in a KDL file."""
    for m in re.finditer(r"^binds\s*\{", text, re.M):
        depth, i, in_str = 1, m.end(), False
        while depth:
            c = text[i]
            if in_str:
                if c == "\\":
                    i += 1
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif text.startswith("//", i):
                i = text.index("\n", i) - 1
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
        yield text[m.end():i - 1]


def parse_binds(text):
    """[(chord, props, [(action, [args])])] for every bind in the file."""
    binds = []
    for block in binds_blocks(text):
        toks = list(tokenize(block))
        i = 0
        while i < len(toks):
            kind, val = toks[i]
            if kind != "word":
                i += 1; continue
            chord, props, i = val, {}, i + 1
            while toks[i][0] != "{":          # properties up to the action block
                k, v = toks[i]
                if k == "word" and "=" in v:
                    key, _, inline = v.partition("=")
                    if inline:
                        props[key] = inline
                    else:
                        i += 1; props[key] = toks[i][1]
                i += 1
            i += 1
            actions, cur = [], None
            while toks[i][0] != "}":
                k, v = toks[i]
                if k in ("word", "str"):
                    if cur is None:
                        cur = (v, []); actions.append(cur)
                    else:
                        cur[1].append(v)
                elif k in (";", "nl"):
                    cur = None
                i += 1
            i += 1
            binds.append((chord, props, actions))
    return binds


# Titles for actions whose bind carries no hotkey-overlay-title.
NIRI_TITLES = {
    "focus-column-left": "Focus column left", "focus-column-right": "Focus column right",
    "focus-window-up": "Focus window above (in column)", "focus-window-down": "Focus window below (in column)",
    "focus-workspace-up": "Focus workspace above", "focus-workspace-down": "Focus workspace below",
    "focus-column-first": "Focus first column", "focus-column-last": "Focus last column",
    "focus-monitor-left": "Focus monitor left", "focus-monitor-right": "Focus monitor right",
    "focus-monitor-up": "Focus monitor above", "focus-monitor-down": "Focus monitor below",
    "move-column-left": "Move column left", "move-column-right": "Move column right",
    "move-window-up": "Move window up (in column)", "move-window-down": "Move window down (in column)",
    "move-column-to-first": "Move column to first", "move-column-to-last": "Move column to last",
    "move-column-to-workspace-up": "Carry column to workspace above",
    "move-column-to-workspace-down": "Carry column to workspace below",
    "move-column-to-monitor-left": "Move column to monitor left", "move-column-to-monitor-right": "Move column to monitor right",
    "move-column-to-monitor-up": "Move column to monitor above", "move-column-to-monitor-down": "Move column to monitor below",
    "move-workspace-up": "Move workspace up", "move-workspace-down": "Move workspace down",
    "toggle-overview": "Overview", "close-window": "Close window",
    "consume-or-expel-window-left": "Consume / expel window left",
    "consume-or-expel-window-right": "Consume / expel window right",
    "consume-window-into-column": "Pull next window into column",
    "expel-window-from-column": "Push bottom window out of column",
    "switch-preset-column-width": "Cycle column widths",
    "switch-preset-window-height": "Cycle window heights",
    "maximize-column": "Maximise column", "fullscreen-window": "Fullscreen",
    "maximize-window-to-edges": "Maximise to screen edges",
    "expand-column-to-available-width": "Fill available width",
    "center-column": "Centre column", "center-visible-columns": "Centre all visible columns",
    "toggle-window-floating": "Toggle floating",
    "switch-focus-between-floating-and-tiling": "Focus floating ↔ tiling",
    "toggle-column-tabbed-display": "Tabbed column",
    "screenshot": "Screenshot (region)", "screenshot-screen": "Screenshot (screen)",
    "screenshot-window": "Screenshot (window)",
    "toggle-keyboard-shortcuts-inhibit": "Let the app have the keyboard (toggle)",
    "quit": "Quit niri", "power-off-monitors": "Power off monitors",
    "show-hotkey-overlay": "Hotkey overlay",
}

# Spawned commands, by what they run.
SPAWN_TITLES = [
    (r"wpctl set-volume .*0\.1\+", "Volume up"), (r"wpctl set-volume .*0\.1-", "Volume down"),
    (r"wpctl set-mute @DEFAULT_AUDIO_SINK@", "Mute"), (r"wpctl set-mute @DEFAULT_AUDIO_SOURCE@", "Mute microphone"),
    (r"playerctl play-pause", "Play / pause"), (r"playerctl stop", "Stop playback"),
    (r"playerctl previous", "Previous track"), (r"playerctl next", "Next track"),
    (r"brightnessctl .*\+10%", "Brightness up"), (r"brightnessctl .*10%-", "Brightness down"),
]

LAYOUT = {"close-window", "consume-or-expel-window-left", "consume-or-expel-window-right",
          "consume-window-into-column", "expel-window-from-column", "switch-preset-column-width",
          "switch-preset-column-width-back", "switch-preset-window-height", "reset-window-height",
          "set-column-width", "set-window-height", "maximize-column", "fullscreen-window",
          "maximize-window-to-edges", "expand-column-to-available-width", "center-column",
          "center-visible-columns", "toggle-window-floating",
          "switch-focus-between-floating-and-tiling", "toggle-column-tabbed-display"}
SESSION = {"quit", "power-off-monitors", "show-hotkey-overlay", "toggle-keyboard-shortcuts-inhibit",
           "screenshot", "screenshot-screen", "screenshot-window"}

# Binds the fuzzel search lists but won't run: ending the session, closing a
# whole workspace, and handing the keyboard to an app are for the real keys.
NO_RUN = {"quit", "toggle-keyboard-shortcuts-inhibit"}


def niri_category(action, args, chord):
    text = " ".join(args)
    if chord.startswith("XF86"):
        return "Hardware keys"
    if action in ("spawn", "spawn-sh"):
        if "niritasks" in text:
            return "Tasks" if " task " in f" {text} " else "Workspace"
        if "unset-workspace-name" in text:
            return "Workspace"
        if re.search(r"fuzzel|ghostty|firefox|shortcuts", text) and "wallpaper" not in text:
            return "Launch"
        return "Screen & session"
    if action in LAYOUT:
        return "Window layout"
    if action in SESSION:
        return "Screen & session"
    if action.startswith(("move-workspace", "focus-workspace")) or action == "toggle-overview":
        return "Workspace"
    return "Focus & move"


def sentence_case(title):
    """"Move Workspace to Monitor Left" → "Move workspace to monitor left", so
    overlay titles read like the rest of the page. Leaves 4K, Mod+Shift+F etc."""
    words = title.split(" ")
    return " ".join([words[0]] + [w.lower() if re.fullmatch(r"[A-Z][a-z]+(-[a-z]+)*:?", w) else w for w in words[1:]])


def niri_title(action, args, props):
    title = props.get("hotkey-overlay-title")
    if title and title != "null":
        return sentence_case(title)
    text = " ".join(args)
    if action in ("spawn", "spawn-sh"):
        for pat, t in SPAWN_TITLES:
            if re.search(pat, text):
                return t
        return text
    if action == "focus-workspace":
        return "Focus workspace N"
    if action == "move-column-to-workspace":
        return "Carry column to workspace N"
    if action == "move-workspace-to-index":
        return "Move workspace to position N"
    if action == "set-column-width":
        return f"Column width {args[0].replace('-', '−')}"
    if action == "set-window-height":
        return f"Window height {args[0].replace('-', '−')}"
    return NIRI_TITLES.get(action, action.replace("-", " ").capitalize())


def niri_run(action, args):
    if action in NO_RUN or (action == "spawn-sh" and "unset-workspace-name" in args[0]):
        return ""
    if action == "spawn":
        args = [os.path.expanduser(args[0])] + args[1:]
    cmd = ["niri", "msg", "action", action]
    return shlex.join(cmd + ["--"] + args if args else cmd)


def niri_entries(files):
    """Group binds that do the same thing into one entry with several chords."""
    entries, by_sig = [], {}
    for path, tool, machine in files:
        if not path.exists():
            continue
        for chord, props, actions in parse_binds(path.read_text()):
            if not actions:
                continue
            action, args = actions[0]
            # "Mod+1…9" is one entry, not nine: fold the digit into the chord.
            digit = re.fullmatch(r"(.*\+)([1-9])", chord)
            sig_args = args
            if digit and args == [digit.group(2)]:
                chord, sig_args = digit.group(1) + "1–9", ["N"]
            sig = (tool, machine, action, tuple(sig_args))
            e = by_sig.get(sig)
            if e is None:
                title = niri_title(action, sig_args, props)
                if digit and sig_args == ["N"]:
                    title = re.sub(r"\s*1 \(…9\)$", " N", title)
                e = {"tool": tool, "cat": niri_category(action, args, chord), "title": title,
                     "keys": [], "machine": machine, "action": action, "run": "" if sig_args == ["N"] else niri_run(action, args)}
                by_sig[sig] = e
                entries.append(e)
            elif props.get("hotkey-overlay-title") not in (None, "null"):
                e["title"] = sentence_case(props["hotkey-overlay-title"])
            # niri reads the files in include order and a later bind of the same
            # chord wins, so take the chord off whatever claimed it earlier.
            for other in entries:
                same_machine = "all" in (machine, other["machine"]) or machine == other["machine"]
                if other is not e and chord in other["keys"] and same_machine:
                    other["keys"].remove(chord)
                    e.setdefault("replaces", []).append(plain(chord))
            if chord not in e["keys"]:
                e["keys"].append(chord)
            if digit and sig_args == ["N"]:
                # Run the 1 of a 1–9 row; there's no way to ask fuzzel for N.
                e["run"] = ""
    entries = [e for e in entries if e["keys"]]
    for e in entries:
        # "Fullscreen (also Mod+Shift+F)" helps niri's overlay, which shows one
        # chord; here every chord is listed, so the aside is just noise.
        e["title"] = re.sub(r"\s*\(also [^)]*\)$", "", e["title"])
        if e.get("replaces"):
            e["note"] = f"Overrides the {', '.join(e.pop('replaces'))} bind in config.kdl"
        if e["action"] == "spawn-sh" and "close" in e["title"].lower() and e["cat"] == "Workspace":
            e["note"] = "Search lists it; run it from its keys"
        elif e["action"] in NO_RUN:
            e["note"] = "Search lists it; run it from its keys"
        if any("+Alt+" in k and "+Ctrl+" not in k for k in e["keys"]) and any(
                "+Ctrl+" in k and "+Alt+" not in k for k in e["keys"]):
            e["twin"] = True
    return entries


def niri_chord(chord):
    return chord.split("+")


# ─── herdr ────────────────────────────────────────────────────────────────────

HERDR_VERSION = "0.9.1"

# (config key, default, category, title) — from docs/next/website/src/data/
# config-reference.json at herdr's v0.9.1 tag. None = unbound by default.
HERDR_DEFAULTS = [
    ("prefix", "ctrl+b", "Session", "Prefix: press it, let go, then the key"),
    ("help", "prefix+?", "Session", "Show every active binding"),
    ("settings", "prefix+s", "Session", "Settings"),
    ("detach", "prefix+q", "Session", "Detach, leaving everything running"),
    ("reload_config", "prefix+shift+r", "Session", "Reload config.toml"),
    ("goto", "prefix+g", "Session", "Session navigator (goto)"),
    ("toggle_sidebar", "prefix+b", "Session", "Toggle sidebar"),
    ("open_notification_target", "prefix+o", "Session", "Jump to the visible notification"),
    ("remote_image_paste", "ctrl+v", "Session", "Paste a clipboard image into a remote session"),
    ("new_workspace", "prefix+shift+n", "Workspaces", "New workspace"),
    ("rename_workspace", "prefix+shift+w", "Workspaces", "Rename workspace"),
    ("close_workspace", "prefix+shift+d", "Workspaces", "Close workspace"),
    ("workspace_picker", "prefix+w", "Workspaces", "Workspace navigation"),
    ("previous_workspace", None, "Workspaces", "Previous workspace"),
    ("next_workspace", None, "Workspaces", "Next workspace"),
    ("switch_workspace", None, "Workspaces", "Switch to workspace 1–9"),
    ("indexed.workspaces", None, "Workspaces", "Modifier for workspace 1–9 without the prefix"),
    ("new_worktree", "prefix+shift+g", "Workspaces", "New git worktree"),
    ("open_worktree", None, "Workspaces", "Open an existing git worktree"),
    ("remove_worktree", None, "Workspaces", "Remove a managed worktree"),
    ("new_tab", "prefix+c", "Tabs", "New tab"),
    ("rename_tab", "prefix+shift+t", "Tabs", "Rename tab"),
    ("previous_tab", "prefix+p", "Tabs", "Previous tab"),
    ("next_tab", "prefix+n", "Tabs", "Next tab"),
    ("switch_tab", "prefix+1..9", "Tabs", "Jump to tab 1–9"),
    ("close_tab", "prefix+shift+x", "Tabs", "Close tab"),
    ("move_tab_previous", None, "Tabs", "Move tab toward the front"),
    ("move_tab_next", None, "Tabs", "Move tab toward the back"),
    ("indexed.tabs", None, "Tabs", "Modifier for tab 1–9 without the prefix"),
    ("split_vertical", "prefix+v", "Panes", "Split side by side"),
    ("split_horizontal", "prefix+minus", "Panes", "Split stacked"),
    ("focus_pane_left", "prefix+h", "Panes", "Focus pane left"),
    ("focus_pane_down", "prefix+j", "Panes", "Focus pane below"),
    ("focus_pane_up", "prefix+k", "Panes", "Focus pane above"),
    ("focus_pane_right", "prefix+l", "Panes", "Focus pane right"),
    ("swap_pane_left", "prefix+shift+h", "Panes", "Swap pane left"),
    ("swap_pane_down", "prefix+shift+j", "Panes", "Swap pane down"),
    ("swap_pane_up", "prefix+shift+k", "Panes", "Swap pane up"),
    ("swap_pane_right", "prefix+shift+l", "Panes", "Swap pane right"),
    ("cycle_pane_next", "prefix+tab", "Panes", "Next pane"),
    ("cycle_pane_previous", "prefix+shift+tab", "Panes", "Previous pane"),
    ("last_pane", None, "Panes", "Last focused pane"),
    ("zoom", "prefix+z", "Panes", "Zoom pane"),
    ("close_pane", "prefix+x", "Panes", "Close pane"),
    ("rename_pane", "prefix+shift+p", "Panes", "Rename pane"),
    ("resize_mode", "prefix+r", "Panes", "Resize mode"),
    ("resize_pane_left", None, "Panes", "Resize pane left"),
    ("resize_pane_down", None, "Panes", "Resize pane down"),
    ("resize_pane_up", None, "Panes", "Resize pane up"),
    ("resize_pane_right", None, "Panes", "Resize pane right"),
    ("copy_mode", "prefix+[", "Panes", "Copy mode"),
    ("edit_scrollback", "prefix+e", "Panes", "Open scrollback in $EDITOR"),
    ("previous_agent", None, "Agents", "Previous agent"),
    ("next_agent", None, "Agents", "Next agent"),
    ("focus_agent", None, "Agents", "Focus agent 1–9"),
    ("indexed.agents", None, "Agents", "Modifier for agent 1–9 without the prefix"),
    ("navigate_workspace_up", "up", "Navigate mode", "Select workspace above"),
    ("navigate_workspace_down", "down", "Navigate mode", "Select workspace below"),
    ("navigate_pane_left", "h", "Navigate mode", "Focus pane left (← too)"),
    ("navigate_pane_down", "j", "Navigate mode", "Focus pane below"),
    ("navigate_pane_up", "k", "Navigate mode", "Focus pane above"),
    ("navigate_pane_right", "l", "Navigate mode", "Focus pane right (→ too)"),
]

# Fixed keys inside herdr's own modes, from its keyboard guide. Not configurable.
HERDR_FIXED = [
    ("Copy mode", "Move", ["h", "j", "k", "l"]),
    ("Copy mode", "Word / big word", ["w", "b", "e", "shift+w", "shift+b", "shift+e"]),
    ("Copy mode", "Paragraph", ["{", "}"]),
    ("Copy mode", "Page", ["pageup", "pagedown", "ctrl+f", "ctrl+u", "ctrl+d"]),
    ("Copy mode", "Search forward / back", ["/", "?"]),
    ("Copy mode", "Next / previous match", ["n", "shift+n"]),
    ("Copy mode", "Start selection", ["v", "space", "shift+v"]),
    ("Copy mode", "Copy selection", ["y", "enter"]),
    ("Copy mode", "Leave (clears selection or search first)", ["q", "esc"]),
    ("Text fields", "Character left / right", ["left", "right", "ctrl+b", "ctrl+f"]),
    ("Text fields", "Start / end of field", ["home", "end", "ctrl+a", "ctrl+e"]),
    ("Text fields", "Word left / right", ["alt+b", "alt+f"]),
    ("Text fields", "Delete previous character", ["backspace", "ctrl+h"]),
    ("Text fields", "Delete next character", ["delete", "ctrl+d"]),
    ("Text fields", "Cut to start / end", ["ctrl+u", "ctrl+k"]),
    ("Text fields", "Cut previous word", ["ctrl+w", "alt+backspace", "ctrl+backspace"]),
    ("Text fields", "Cut next word", ["alt+d"]),
    ("Text fields", "Insert last cut", ["ctrl+y"]),
    ("Keybind help", "Filter the list", ["/"]),
    ("Keybind help", "Clear the filter", ["ctrl+u"]),
]


def as_list(v):
    return v if isinstance(v, list) else [v]


def herdr_entries(config_path):
    cfg = tomllib.loads(config_path.read_text()) if config_path.exists() else {}
    keys = cfg.get("keys", {})
    user = {k: v for k, v in keys.items() if k not in ("command", "indexed")}
    for k, v in keys.get("indexed", {}).items():
        user[f"indexed.{k}"] = v
    commands = keys.get("command", [])
    taken = {c.get("key") for c in commands}
    entries = []
    for key, default, cat, title in HERDR_DEFAULTS:
        e = {"tool": "herdr", "cat": cat, "title": title, "run": "", "config": key}
        if key in user:
            e["keys"] = as_list(user[key]); e["note"] = "Set in your config.toml"
        elif default is None:
            e["keys"] = []; e["unset"] = True; e["note"] = "Unbound by default"
        else:
            e["keys"] = [default]
            if default in taken:
                e["replaced"] = True
                e["note"] = "herdr default, replaced by your worktrunk key below"
        entries.append(e)
    for c in commands:
        entries.append({"tool": "herdr", "cat": "Worktrees (worktrunk)", "keys": [c["key"]],
                        "title": c.get("description", c.get("command", ""))[:1].upper()
                                 + c.get("description", c.get("command", ""))[1:], "run": "",
                        "note": f"Plugin action {c.get('command', '')}"})
    for cat, title, ks in HERDR_FIXED:
        entries.append({"tool": "herdr", "cat": cat, "title": title, "keys": ks, "run": ""})
    prefix = user.get("prefix", "ctrl+b")
    return entries, prefix


# ─── ghostty ──────────────────────────────────────────────────────────────────

GHOSTTY_TITLES = {
    "new_window": "New window", "new_tab": "New tab",
    "increase_font_size": "Bigger text", "decrease_font_size": "Smaller text",
    "reset_font_size": "Reset text size", "text:\\n": "Newline without sending (for agent prompts)",
}


def ghostty_entries(path):
    entries = []
    if not path.exists():
        return entries
    for line in path.read_text().splitlines():
        m = re.match(r"\s*keybind\s*=\s*(.+)$", line)
        if not m:
            continue
        trigger, _, action = m.group(1).partition("=")
        title = GHOSTTY_TITLES.get(action) or GHOSTTY_TITLES.get(action.split(":")[0]) \
            or action.replace("_", " ").capitalize()
        entries.append({"tool": "ghostty", "cat": "Terminal", "title": title,
                        "keys": [trigger.strip()], "run": "", "note": f"ghostty: {action}"})
    return entries


# ─── output ───────────────────────────────────────────────────────────────────

PRETTY = {"Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Page_Up": "PgUp", "Page_Down": "PgDn",
          "BracketLeft": "[", "BracketRight": "]", "Comma": ",", "Period": ".", "Minus": "−",
          "Equal": "=", "Slash": "/", "WheelScrollUp": "Wheel↑", "WheelScrollDown": "Wheel↓",
          "WheelScrollLeft": "Wheel←", "WheelScrollRight": "Wheel→", "XF86AudioRaiseVolume": "Vol+",
          "XF86AudioLowerVolume": "Vol−", "XF86AudioMute": "Mute", "XF86AudioMicMute": "Mic mute",
          "XF86AudioPlay": "Play", "XF86AudioStop": "Stop", "XF86AudioPrev": "Prev", "XF86AudioNext": "Next",
          "XF86MonBrightnessUp": "Bright+", "XF86MonBrightnessDown": "Bright−",
          "minus": "−", "plus": "+", "zero": "0", "1..9": "1–9", "pageup": "PgUp", "pagedown": "PgDn",
          "left": "←", "right": "→", "up": "↑", "down": "↓", "enter": "Enter", "esc": "Esc", "tab": "Tab",
          "space": "Space", "backspace": "Backspace", "delete": "Delete", "home": "Home", "end": "End"}


def plain(chord):
    """A chord as fuzzel shows it: Mod+Alt+← rather than Mod+Alt+Left."""
    def one(p):
        if p in PRETTY:
            return PRETTY[p]
        if len(p) == 1:
            return p.upper()
        return p.capitalize() if p.islower() else p
    return "+".join(one(p) for p in chord.split("+"))


MODS = {"mod": "Mod", "super": "Mod", "alt": "Alt", "ctrl": "Ctrl", "shift": "Shift", "prefix": "prefix"}


def chord_tokens(chord):
    """[[label, modifier-or-""], …] for the page to draw as keycaps."""
    parts = chord.split("+")
    out = [[MODS[p.lower()], MODS[p.lower()]] for p in parts[:-1] if p.lower() in MODS]
    last = parts[-1]
    one = plain(last) if last not in ("?",) else last
    return out + [[one, ""]]


INDENT = 2


def write_tsv(entries, out, prefix):
    """One line per shortcut, as three columns: the key, the title, and where it
    lives pushed to the right edge. That's all fuzzel shows — the extra chords
    are on the page — so a line reads at a glance.

    The columns are plain spaces. search.sh gives this picker a monospace font,
    so every character is one column wide on any screen; in a proportional font
    the same padding drifts by a few pixels a line, which is what it used to do.
    """
    columns = int(re.search(r"--width=(\d+)", (Path(__file__).parent / "search.sh").read_text()).group(1))
    # herdr's prefix is a key you press and let go, not a modifier to hold.
    show_key = lambda k: f"{plain(prefix)} ▸ {plain(k[7:])}" if k.startswith("prefix+") else plain(k)
    rows = []
    for e in entries:
        if not e["keys"] or e.get("replaced"):
            continue
        where = {"herdr": f"herdr · {e['cat']}", "ghostty": "ghostty"}.get(e["tool"], e["cat"])
        if not e["run"] and e["tool"] in ("niri", "niri-tasks"):
            where = f"keys only · {where}"
        rows.append((show_key(e["keys"][0]), e["title"], where, e["run"]))

    # As wide as most keys need; the odd long one pushes only its own title along.
    key_col = sorted(len(k) for k, *_ in rows)[int(len(rows) * 0.9)] + 2
    lines = []
    for key, title, where, run in rows:
        left = key.ljust(key_col) if len(key) < key_col else key + "  "
        # fuzzel's list holds two characters fewer than --width (measured: 93 of
        # 95; a longer line loses its end to "…"), and that dead space sits at the
        # right end only. Indenting every line by the same two characters — and
        # the prompt, in search.sh — evens the margins out again.
        line_len = columns - 2 - INDENT
        room = line_len - len(left) - len(where) - 2
        if len(title) > room:
            title = title[:room - 1].rstrip() + "…"
        lines.append(f"{' ' * INDENT}{left}{title}{' ' * (line_len - len(left) - len(title) - len(where))}{where}\t{run}")
    out.write_text("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--machine", default="", help="laptop or desktop: what the page shows first")
    ap.add_argument("--niri-tasks", type=Path, help="niri-tasks.kdl (default: the live one, else ~/Projects)")
    a = ap.parse_args()

    tasks = a.niri_tasks or next((p for p in (HOME / ".config/niri/niri-tasks.kdl",
                                              HOME / "Projects/niri-tasks/niri/niri-tasks.kdl") if p.exists()),
                                 HOME / ".config/niri/niri-tasks.kdl")
    niri = niri_entries([
        (REPO / "config/niri/config.kdl", "niri", "all"),
        (tasks, "niri-tasks", "all"),        # config.kdl includes it at the bottom
        (REPO / "config/niri/laptop.kdl", "niri", "laptop"),   # configure.sh appends these
        (REPO / "config/niri/desktop.kdl", "niri", "desktop"),
    ])
    herdr, prefix = herdr_entries(REPO / "config/herdr/config.toml")
    ghostty = ghostty_entries(REPO / "config/ghostty/config.ghostty")
    entries = niri + herdr + ghostty
    for e in entries:
        e.pop("action", None)
        e.pop("config", None)
        e["chords"] = [chord_tokens(k) for k in e["keys"]]

    a.out.mkdir(parents=True, exist_ok=True)
    data = {
        "generated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "machine": a.machine, "herdrVersion": HERDR_VERSION, "herdrPrefix": prefix,
        "entries": entries,
    }
    page = (Path(__file__).parent / "page.html").read_text()
    blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    (a.out / "shortcuts.html").write_text(page.replace("__SHORTCUTS_DATA__", blob))
    write_tsv(entries, a.out / "shortcuts.tsv", prefix)
    print(f"{len(entries)} shortcuts → {a.out}/shortcuts.html, shortcuts.tsv")


if __name__ == "__main__":
    sys.exit(main())
