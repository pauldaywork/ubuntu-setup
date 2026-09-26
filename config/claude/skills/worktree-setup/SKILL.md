---
name: worktree-setup
description: >
  Give a repo its worktree setup — the `.worktreeinclude` and `.config/wt.toml`
  hooks that copy `.env`, give each worktree its own ports and a cloned
  database, and drop it again on removal — by surveying the repo, interviewing
  the user, writing both files to the shared convention, and proving them on a
  throwaway worktree. Triggers on: "/worktree-setup", "set up worktrees for this
  repo", "write the wt.toml", "make this repo work with parallel agents", or
  fixing a repo whose worktree setup fails.
---

# worktree-setup: a repo's `.config/wt.toml`, by interview

The convention is `~/Projects/ubuntu-setup/docs/worktree-setup.md`. **Read all
of it first** — the shape of `wt.toml`, every rule, and why each exists. This
skill is the procedure; that document is the source of truth for what the
result looks like, and every file you write must match it.

Every repo is different underneath and identical on top: the same named steps
in the same order, differing only in what the project needs. Your job is to
find out what it needs — from the repo first, from the user second — and
nothing more.

**Secrets stay unread.** Read `.env` files for their *key names*, never their
values, and when you need something from a URL (the database name, the host),
extract only that part. Nothing from a `.env` goes into `wt.toml`.

## 1. Survey

Work out everything the repo can tell you before asking anything. Run these from
the main checkout:

```bash
git ls-files --others --ignored --exclude-standard --directory   # what git does not carry
for f in .env .env.*; do [ -f "$f" ] && echo "$f: $(grep -oE '^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*=' "$f" | sed 's/^\s*//; s/export\s*//; s/=$//' | tr '\n' ' ')"; done
cat .worktreeinclude .config/wt.toml 2>/dev/null                  # an existing setup to extend
```

Then read, as they apply: the lockfile (which install command); `package.json`
scripts, `vite`/`next` config, `Procfile`, compose files (every server, and
whether it takes its port from an env var or a flag); ORM and migration config
(drizzle, knex, prisma, alembic — the migrate command, and which env key holds
the URL); SQLite files; Redis or queue clients.

For each database URL, pull out only the database name and host:

```bash
dotenvx get DATABASE_URL -f .env -o | sed -E 's#^[a-z]+://([^@]*@)?##; s#\?.*##'   # host:port/dbname
```

and for a local Postgres, its size, live connections, and whether its template
exists:

```bash
psql -d postgres -Atc "select datname, pg_size_pretty(pg_database_size(datname)), numbackends from pg_stat_database join pg_database using (datname) where datname in ('<db>', '<db>_template')"
```

**Done when** you hold a survey table with a row for every gitignored file,
every env key, every server, every database and every other service — each with
what you found and what you would propose for it.

## 2. Interview

Put the survey to the user as proposals to confirm, not open questions: they
know the project, you know the convention. Use `AskUserQuestion`, up to four
topics per call, your proposal first and marked recommended. Topics, in order:

1. **Files to copy** — which gitignored files a working checkout needs. This
   becomes `.worktreeinclude`. Build output and dependency folders are not on
   it; the `deps` step recreates them.
2. **Env keys per worktree** — which keys must differ between worktrees (ports,
   database URLs, anything naming a local resource) and which carry over as-is.
3. **Servers** — each one, and how it takes its port. Ask specifically whether
   anything is pinned to a port or URL: OAuth callbacks, webhooks, CORS
   origins. Those break on a new port; the convention's portless row covers
   them.
4. **Databases** — each one's mode: **full clone** (the default), **schema
   only** (clone the template empty, let `migrate` build it), or **shared**
   (no step — the user must say why sharing is safe). Show its size, and warn
   when it has live connections, since those rule it out as a clone source.
   If `<db>_template` is missing, propose creating it.
5. **Other services** — Redis, compose, queues, storage, each against the
   convention's table.
6. **Dependencies and migrations** — the install command, the migrate command,
   and any seed.

**Done when** every row of the survey table has a decision the user has
confirmed.

## 3. Write

Write `.worktreeinclude` and `.config/wt.toml` in the convention's shape: its
step names, its order, its `pre-remove` guard verbatim. Start the file with
the version line and a comment recording the decisions — which servers on which
keys, which databases in which mode — so the next reader, and the next run of
this skill, knows why each step is there.

Check against the rules as you go; these are the ones a hand-written file gets
wrong:

- Each dependent step in its own `[[pre-start]]` block.
- `dotenvx set … --plain` for every per-worktree key — replace, never append.
- `<prefix>_wt_` at most 15 characters, so the clone's name survives Postgres's
  63-byte cut.
- `{{ … }}` unquoted, and the commands plain `sh`.

For a missing template, confirm with the user, check the source has no
connections, then:

```bash
createdb -T <db> <db>_template
```

**Done when** both files are written and every rule in the convention holds
for them — go through the rules list line by line.

## 4. Prove

A setup that has not run is a guess. Create a throwaway worktree, check it,
remove it, check again:

```bash
sha256sum .env > /tmp/main-env.sum
wt switch --create wt-selftest --yes --no-cd </dev/null
```

`--yes` approves the hooks for this one run without recording anything; the
user approves them for real the first time they use the herdr keys.

Then confirm, and show the user each result:

- the command exited 0, and every step ran;
- the worktree's `.env` has a new port for each server, and `DATABASE_URL`
  names the `_wt_` clone (`dotenvx get DATABASE_URL -f .env -o` in the worktree,
  printing only the part after the last `/`);
- the clone exists, holding data if it is a full clone
  (`psql -d postgres -Atc "select 1 from pg_database where datname = '<clone>'"`);
- `sha256sum -c /tmp/main-env.sum` passes — the main checkout's `.env` is
  untouched.

Then remove it and confirm the teardown:

```bash
wt remove wt-selftest --yes --foreground </dev/null
```

- the clone is gone, the worktree folder is gone, and the branch is gone (it
  has no commits, so worktrunk counts it as merged).

When a step fails, fix `wt.toml` and prove it again from the top, removing the
half-made worktree first (`wt remove wt-selftest --yes --foreground`). The
convention's *When a step fails* section covers re-running in place.

**Done when** every check above has passed on one clean run, create through
remove.

## 5. Hand over

Report what the repo now does per worktree — files, ports, databases, deps —
and the proof results. The files only take effect once committed **on the
default branch**, since worktrunk reads hooks from the checkout it runs in;
commit only if the user asks, and say which branch they are on if it is not the
default.
