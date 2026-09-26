# Worktree setup: one convention for every repo

Coding agents run in parallel, one per git worktree, so they never edit the
same checkout. A worktree is more than a checkout, though: it needs the
project's gitignored files (`.env`), its own port for each dev server, and its
own copy of the database, so two agents never migrate or seed the same one.
And all of it has to go again when the worktree does.

Nothing here is custom tooling. [worktrunk](https://worktrunk.dev) (`wt`) owns
the worktree lifecycle and runs each repo's hooks; the hooks are a few lines of
config calling Postgres's own template cloning and
[dotenvx](https://dotenvx.com). What this document fixes is the *shape* of those
hooks, so every repo reads the same way and differs only where the project does.
The `worktree-setup` Claude skill interviews you about a repo and writes its
config to this convention.

## How you use it

In a project's herdr session (`Mod+Alt+P`), the herdr-worktrunk plugin's keys:

| Key | Does |
|---|---|
| `prefix+shift+g` | Pick or create a worktree, branching from the default branch |
| `prefix+shift+c` | The same, branching from the current branch |
| `prefix+shift+o` | Pick from local **and** remote branches |
| `prefix+shift+m` | Merge into the default branch (squash, rebase, fast-forward), then remove |
| `prefix+shift+e` | Remove: drops the worktree's database; an unmerged branch is kept |

A new worktree opens as a herdr workspace grouped under the project's, with the
setup output held on screen. Start the agent there.

**Don't use herdr's own worktree items** in its sidebar menu ("New worktree",
"Delete worktree checkout…"). They make and delete plain git worktrees and run
none of the hooks: no `.env`, no port, no database — and on delete, a database
left behind. The keys above replace herdr's `prefix+shift+g`; the menu items
cannot be removed.

Worktrees live in `~/.worktrees/<repo>/<branch>` (set in
`config/worktrunk/config.toml`), not in `~/Projects`, which niritasks lists as
projects.

## What a repo carries

Both committed, **on the default branch**. worktrunk reads hooks from the
worktree you run `wt` from, which for the plugin's keys is the project's main
checkout.

```
.worktreeinclude     # gitignored files to copy from the main checkout
.config/wt.toml      # the hooks, in the shape below
```

`.worktreeinclude` uses gitignore syntax, and a file is copied only if it is
matched there **and** gitignored. It is the one file every worktree tool reads
the same way — Claude Code, Codex, Conductor and worktrunk — so it is the list of
record for "files a checkout needs that git does not have".

## The shape of `.config/wt.toml`

The same named steps, in the same order, in every repo. Leave out a step a
project does not need; do not rename or reorder the rest.

```toml
# worktree-setup v1 — see ubuntu-setup/docs/worktree-setup.md
# servers: web (PORT)   databases: votes <- votes_template (full clone)

[[pre-start]]
copy = "wt step copy-ignored --require-include"

[[pre-start]]
db-name = "wt config state vars set db=votes_wt_{{ branch | sanitize_db }}"

[[pre-start]]
db = "createdb -S file_copy -T votes_template {{ vars.db }}"
env-port = "dotenvx set PORT {{ ('web-' ~ branch) | hash_port }} -f .env --plain"

[[pre-start]]
env-db = "url=$(dotenvx get DATABASE_URL -f .env -o) && dotenvx set DATABASE_URL \"${url%/*}/{{ vars.db }}\" -f .env --plain"

[[pre-start]]
deps = "npm ci"

[[pre-start]]
migrate = "npx drizzle-kit migrate"

[pre-remove]
db = "{% if vars is defined and vars.db is defined %}case {{ vars.db }} in *_wt_*) dropdb --if-exists --force {{ vars.db }} ;; *) echo 'refusing to drop {{ vars.db }}: not a worktree database' >&2; exit 1 ;; esac{% else %}echo 'no worktree database recorded, nothing to drop'{% endif %}"

[list]
url = "http://localhost:{{ ('web-' ~ branch) | hash_port }}"
```

Step by step:

| Step | What | Why this way |
|---|---|---|
| `copy` | `.worktreeinclude` files from the main checkout | `--require-include` copies nothing when the file is absent, rather than every gitignored file (`node_modules` included) |
| `db-name` | Records the clone's name against the branch | See *The database name is recorded once* below |
| `db` | Clones the database from its template | `createdb -T` is Postgres's own clone; `-S file_copy` copies files rather than WAL-logging every page |
| `env-port` | A port per server | `hash_port` gives a stable port (10000–19999) from the branch; the `'web-'` salt keeps two servers in one worktree apart |
| `env-db` | Points `DATABASE_URL` at the clone | Swaps only the database name, keeping the user, password and host from the copied `.env` |
| `deps` | Installs dependencies | |
| `migrate` | Migrations, then any seed | After the clone, so it brings a copied database up to the branch's schema |
| `pre-remove db` | Drops the clone | Before the worktree goes, and only a name that is recorded **and** marked `_wt_` |

## Rules

**Each `[[pre-start]]` block is one step, run in order; keys inside a block run
at the same time.** Anything that needs the result of another step goes in a
later block. `db` and `env-port` share a block because neither needs the other.

**Replace values in `.env`; never append.** The copied `.env` already has
`PORT` and `DATABASE_URL`, pointing at main's. Appending leaves two lines for
one key, and which wins is up to whatever reads the file — npm's dotenv takes
the last, other loaders need not — while the common "add it unless it is
already there" recipe keeps main's outright. Either way a worktree can end up
on main's database without a word. `dotenvx set --plain` replaces the line in
place, keeps its quoting and everything else in the file, and adds the key if
it is missing. `--plain` matters: without it dotenvx encrypts the value.

**A URL with `?parameters` keeps them.** `env-db` above swaps everything after
the last `/`, which would drop `?sslmode=…`. For such a URL use:

```toml
env-db = "url=$(dotenvx get DATABASE_URL -f .env -o) && base=${url%%\\?*} && case $url in *\\?*) q=?${url#*\\?} ;; *) q= ;; esac && dotenvx set DATABASE_URL \"${base%/*}/{{ vars.db }}$q\" -f .env --plain"
```

**Clone from a template, never from the database you work in.** `createdb -T`
refuses a source with open connections, and the one your dev server uses always
has them. Keep `<db>_template` next to it, which nothing connects to:

```bash
dropdb --if-exists votes_template && createdb -T votes votes_template   # while votes is idle
```

Refresh it when main's data or schema has moved on far enough to matter; new
worktrees clone whatever it holds, and `migrate` covers the schema in between.

**The database name is recorded once.** `sanitize_db` ends in a short hash
from Rust's standard hasher, which is not guaranteed stable across builds — a
newer `wt` could compute a different name at removal than it did at creation,
and drop nothing while the real clone leaks. So `db-name` stores the name with
`wt config state vars`, and everything after reads `{{ vars.db }}`.

**Keep the prefix short: `<prefix>_wt_` at most 15 characters.** Postgres cuts
identifiers at 63 bytes, silently, and `sanitize_db` can be 48. A longer prefix
gets its clone created under a truncated name that removal never finds. The
prefix only has to be recognisable, not the source database's name: `hdb_wt_`
for `hansard_db_test`.

**The `_wt_` marker is the safety catch, so keep it.** Removal drops only a
recorded name containing `_wt_`. If setup was skipped — the approval prompt
declined, or `--no-hooks` — the copied `.env` still points at **main's**
database, and a removal that worked the name out from `.env` would drop it.

**Don't quote `{{ }}`.** worktrunk shell-escapes every value it substitutes, so
`'{{ branch }}'` double-quotes and breaks. The one exception above is
`\"${url%/*}/{{ vars.db }}\"`, which is safe only because `sanitize_db` output
is plain `[a-z0-9_]` and needs no escaping.

**Write `sh`, not `bash`.** Hooks run under `sh -c`, which is dash on Ubuntu:
no `[[ ]]`, arrays or `pipefail`. Longer logic goes in a script (below).

**Hooks get a JSON blob on stdin.** Pass every value on the command line; a
command that reads stdin (`psql` with no `-c`, a password prompt) eats the
JSON instead.

**No secrets in `wt.toml`.** It is committed. Credentials reach a worktree only
by `.worktreeinclude` copying the `.env` they already live in.

**No long-running servers in `pre-start`.** It blocks until done. If a repo
wants its dev server started, that is `post-start` with
`wt step tether -- <cmd>`, which stops it when the worktree goes.

**More than about 15 lines: move it to scripts.** Keep the step names and call
`scripts/worktree/setup.sh` / `teardown.sh` from them, as spree does. Same
steps, same order, same rules.

### Other services, same pattern

| Service | Per-worktree |
|---|---|
| A second server | Its own salted port: `('api-' ~ branch) \| hash_port` into its own key |
| docker compose | `-p {{ repo }}_{{ branch \| sanitize_db }}` on every compose command, `down -v` in `pre-remove` |
| Redis | A database index, `{{ ('redis-' ~ branch) \| hash_port }}` mod 16, or a key prefix |
| SQLite | List the file in `.worktreeinclude`; the copy is the clone |
| A URL pinned somewhere (OAuth callback, webhook, CORS origin) | A fixed port breaks it. Use [portless](https://github.com/vercel-labs/portless) for a stable `https://<branch>.<app>.localhost`, or register the callback per worktree |

## First run in a repo

worktrunk asks before running a repo's hooks for the first time, and again
whenever their text changes — the prompt is in the plugin's pane. Approving is
remembered in `~/.config/worktrunk/approvals.toml`. **Declining skips every
hook for that operation and carries on without them**: a worktree with main's
`.env`, or a removal that drops nothing.

## When a step fails

A failed `pre-start` step stops the rest, but the worktree and branch stay.
Fix the cause, then from inside the worktree:

```bash
wt hook pre-start
```

Every step is safe to re-run: `copy` skips files already there, `dotenvx set`
replaces, and `db` fails harmlessly if the clone exists (drop it first, or
remove and recreate the worktree, to re-clone).
