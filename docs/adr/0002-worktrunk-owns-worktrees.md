# worktrunk owns worktrees; each repo's hooks set them up

Parallel coding agents each get a git worktree. worktrunk (`wt`) creates and
removes them, driven from herdr by the herdr-worktrunk plugin, and runs the
repo's own `.config/wt.toml` hooks to give each one its `.env`, ports and a
cloned database. The hooks follow one shape across repos
(`docs/worktree-setup.md`), and a Claude skill writes them. No tooling of our
own.

## Considered options

**herdr's native worktrees, plus a plugin of our own for setup.** herdr groups
worktrees under their project nicely, but its worktree support is git only: no
setup hooks, no per-repo config, it never deletes branches, and its one
extension point, `worktree.removed`, fires *after* the checkout is gone — too
late to read the worktree's `.env` for the database to drop. Filling that in
meant writing and owning a runner.

**A custom runner CLI** (`worktree-setup`, then `worktree-hook`), sourcing a
per-repo script with helpers for ports, env edits and database clones. Proposed
twice in planning and rejected: every piece of it already exists — worktrunk's
hooks and `hash_port`/`sanitize_db` filters, `createdb -T`, `dotenvx set` — and
real repos (spree, dimagi/open-chat-studio, greenriver/hmis-warehouse) do
exactly this in a few lines of `wt.toml`.

**Claude Code's `--worktree`.** Claude-only, the worktrees hide in
`.claude/worktrees`, and herdr handles them badly: the sidebar shows the wrong
branch (herdr #4227), new tabs follow the agent into them (#1634), and they are
not resumed with the session (#2379). Still the right tool *inside* a session,
for `isolation: worktree` subagents.

**A Postgres container per worktree** (worktrunk's own recipe; devenv). Full
isolation, but a 2 GB restore per worktree and a server each, where
`createdb -T` against the native Postgres already running is a file copy.

## Consequences

- worktrunk, dotenvx and the plugin are pinned in `lib/manifest.sh` — the
  binaries by checksum, the plugin by commit — because a hook runner and an
  unsandboxed plugin are code that runs on every worktree.
- herdr's own worktree menu items still exist and still skip the hooks. They
  cannot be removed; the convention says not to use them.
- The hook text is approved once per repo, and again whenever it changes.
  Declining skips all hooks, which the `_wt_` guard on `dropdb` makes safe.
