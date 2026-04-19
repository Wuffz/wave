# Wave

A tiny session manager that sits in front of [Claude Code](https://claude.com/claude-code).

Wave is a zero-deps bash script. It gives you a simple menu to spin up new
git worktrees, resume work in existing ones, and drop straight into a Claude
session in the right directory — so you can work on several features in parallel
without fighting with `git worktree` commands.

**One invocation = one session.** Need several at once? Run `wave` in multiple
terminal windows or multiplexer panes.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Wuffz/wave/main/bin/install.sh | sh
```

The installer asks whether to drop `wave` into `~/.local/bin` (no root) or
`/usr/local/bin` (sudo).

Requirements: `bash`, `git`, and [Claude Code](https://claude.com/claude-code)
on your `PATH`.

## Use

Inside any git repo:

```bash
wave
```

That opens the menu:

```
wave  -  <project>
------------------------------------------------------------
  [n] new session
  [r] resume session
  [l] list worktrees
  [g] go live (swap main checkout)
  [c] clean a worktree
  [q] quit
```

### `[n] new session`

Pick a base branch from a numbered list, type a name for the new branch, and
wave:

1. Runs `git worktree add -b <branch> <path> <base>`
2. Runs the optional `.wave/setup.sh` hook
3. `exec`s `claude` in the new worktree

The worktree path is `../<project>-wave/<branch>` — sibling to your main repo.

### `[r] resume session`

Pick a worktree from the list. Wave `cd`s there and runs `claude --continue`,
which resumes the most recent Claude session in that directory. If there's no
session yet, Claude just starts a new one.

### `[l] list worktrees`

Shows every worktree, its branch, last-commit age, and a `*` if the working
tree is dirty.

### `[g] go live (swap main checkout)`

Your main repo is probably where `docker compose up` runs. Wave lets you
promote a worktree's branch into that checkout so your existing docker setup
picks it up without touching compose files.

Wave:

1. Refuses if the main repo has uncommitted changes
2. Briefly detaches the source worktree (git won't let the same branch be
   checked out twice)
3. `git checkout`s the chosen branch in the main repo
4. Runs the optional `.wave/go-live.sh` hook (e.g. `docker compose up -d`,
   migrations)

To swap back, just run `git checkout <other-branch>` in the main repo. The
source worktree stays detached at the commit it was on; `wave resume` still
works there.

> **Note:** with the "forward-only migrations, shared DB" model, make sure
> you're OK running the new branch's migrations against your local database
> before going live.

### `[c] clean a worktree`

Pick a worktree, confirm, and wave runs `.wave/cleanup.sh`, removes the
worktree, optionally deletes the branch, and prunes.

## Direct subcommands

Every menu item is also a subcommand, so you can skip the menu:

```bash
wave new
wave resume
wave list
wave go-live
wave clean
wave init          # create .wave/ config + hooks in the main repo
wave self-update   # reinstall from latest
wave version
wave help
```

## Hooks

When you first run wave in a repo, it creates a `.wave/` directory with empty
executable hooks. Fill them in as you like — if they aren't executable, wave
skips them.

| Hook | Args | When it runs |
|---|---|---|
| `.wave/setup.sh` | `<worktree-path> <branch>` | after `new`, before Claude starts |
| `.wave/cleanup.sh` | `<worktree-path> <branch>` | before `clean` removes the worktree |
| `.wave/go-live.sh` | `<branch> <main-repo-path>` | after `go-live` swaps the checkout |

Typical uses:

- `setup.sh`: `cp .env.example .env`, `composer install`, `npm ci`, symlink
  shared caches, etc.
- `cleanup.sh`: archive logs, drop a tenant-specific docker volume, etc.
- `go-live.sh`: `cd "$2" && docker compose up -d && docker compose exec app php artisan migrate`

## Config

`.wave/config` is a tiny shell-style key=value file:

```sh
# Default base branch when creating new worktrees.
# Blank = use the main repo's current branch.
DEFAULT_BASE_BRANCH=
```

## Why it exists

- `git worktree` is powerful but the commands are hard on the brain.
- Claude Code has `-w` and `--continue` built in — wave is a thin menu in front
  of those so you spend more time writing code and less time remembering flags.
- GUIs exist, but they're overkill when all you want is "drop me into a fresh
  session on a new branch."

## License

See `LICENSE.MD`.
