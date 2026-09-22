# One-way deploy: the repo is authoritative

Managed files move repo → machine and only repo → machine. You edit config in
the repo and deploy it; nothing sweeps live files back. Capture exists for the
few things only a machine can know, as one script per thing, run deliberately —
never as a single command that pulls everything.

## Considered options

**Bidirectional sync**, which is what this repo actually had. `update.sh` swept
every managed file back from the machine, and configure.sh pushed them out, so
neither side was clearly authoritative. A file edited in both places resolved to
whichever script ran last, and the question "which version is right?" had no
answer you could reach without a diff. It was deleted in 232a2fa (2026-08-16),
209 lines.

Measuring before deleting is what settled it. Fourteen of the seventeen managed
files were byte-identical to the repo at the time, because nothing on the
machine edits them — so most of what the sweep pulled had never needed pulling.
All three that differed, differed by design.

## Consequences

**There is deliberately no capture for a file you'd edit in a text editor** —
`.bashrc`, the window-rules, waybar, ghostty. Change those in the repo. The
absence is the decision, not an omission to be filled in later; adding one back
reintroduces the ambiguity the deletion removed.

**Captured things are outside the path table entirely.** What capture deals in
— the live `config.kdl`, the wallpaper images and selection, the VS Code
extension list, the package list — appears in no row, so the table can be read
left-to-right as the single direction.

**The one row that isn't ours alone is `config/Code/settings.json`.** VS Code
writes it too, which is the ownership problem the retired `merge` kind existed
for, at a smaller scale. It is deliberately left as a plain `copy`: the repo
wins, drift shows up in `doctor.sh`, and you resolve it by hand. Adding a
capture script for it would be the third direction this decision exists to
avoid.

**A file the repo deploys but never pulls back is a trap, and the table makes it
visible.** `config/niri/dms/laptop.kdl` was deployed, was not gitignored, and
was never captured, so on a laptop every edit to the live file was silently
discarded by the next install. Declaring the direction once per file is what
makes that unrepresentable.

**Packages get a report, not a write.** `capture/packages.sh` is the one case
that cannot tell what belongs — 132 packages were manually installed against 27
declared when this was measured, and most of the gap is Ubuntu's own base
system. It prints a filtered list and you triage it by hand.

**Selections are seeded rather than deployed**, which is the one exception that
proves the rule: the repo guarantees a wallpaper and a window-rules profile
exist without overwriting the choice you made on the machine. Those are the only
files the repo writes that it does not subsequently own.
