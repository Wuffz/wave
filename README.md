# 🌊 Wave

A simple, elegant Git worktree manager inspired by Laravel Sail and Vessel.

Wave makes it effortless to work on multiple branches simultaneously without the hassle of constant branch switching or stashing changes.

## What are Git Worktrees?

Git worktrees let you check out multiple branches at the same time in separate directories. Instead of switching branches in a single directory, each worktree is a complete working copy with its own branch checked out.

**The Power of Worktrees:**
- Work on multiple features simultaneously, each with its own running dev environment
- Review PRs without disrupting your current work
- Run tests on one branch while developing on another
- Compare different implementations side-by-side
- No more `git stash` juggling or waiting for rebuilds

Wave wraps Git's worktree commands with a simple, intuitive interface and adds powerful automation through setup/cleanup hooks.

## Why Wave?

Working on multiple features or bug fixes at once? Tired of:
- Switching branches back and forth
- Stashing and unstashing changes
- Losing your mental context
- Waiting for builds to restart

Wave creates isolated worktrees for each branch, letting you keep multiple branches running side-by-side.

## Installation

Install Wave with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/Wuffz/wave/main/bin/install.sh | sh
```

The installer will ask you to choose:
- **User install** (`~/.local/bin`) - No root required, recommended
- **Global install** (`/usr/local/bin`) - Requires root, available to all users

Or manually:

```bash
# User install (recommended)
mkdir -p ~/.local/bin
curl -o ~/.local/bin/wave https://raw.githubusercontent.com/Wuffz/wave/main/bin/wave.sh
chmod +x ~/.local/bin/wave

# Make sure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

## Quick Start

```bash
# Initialize Wave in your Git repository
wave init

# Create a worktree for an existing branch
wave create feature/existing-branch

# Create a new branch from current HEAD
wave create feature/new-feature

# Create a new branch from a specific base (local or remote)
wave create feature/new-login develop
wave create hotfix/bug-123 origin/main

# List all active worktrees
wave ls

# Run a command in a specific worktree
wave exec feature/new-login npm run dev

# Remove a worktree when done
wave remove feature/new-login
```

## Commands

| Command | Description |
|---------|-------------|
| `wave init` | Initialize Wave in your repository |
| `wave create <branch> [base]` | Create or checkout a worktree |
| `wave remove <branch>` | Remove a worktree |
| `wave ls` | List all active worktrees |
| `wave status` | Show detailed worktree status (default) |
| `wave` | Alias for `wave status` |
| `wave exec <branch> <cmd>` | Execute a command in a worktree |
| `wave prune` | Clean up stale worktree references |
| `wave self-update` | Update Wave to the latest version |

**Aliases:** `wave up` (create), `wave down` (remove) - for backward compatibility

### Understanding `wave create`

The `wave create` command is smart about branches:

**Existing local branch:**
```bash
wave create feature/existing
# Checks out the existing local branch in a new worktree
```

**Existing remote branch:**
```bash
wave create feature/from-teammate
# Checks out origin/feature/from-teammate if it exists remotely
```

**New branch from current HEAD:**
```bash
wave create feature/new-thing
# Creates a new branch from wherever you currently are
```

**New branch from specific base:**
```bash
wave create feature/new-thing develop
# Creates a new branch from local 'develop' or 'origin/develop'

wave create hotfix/urgent main
# Creates from 'main' or 'origin/main'
```

Wave always prefers `origin/` (remote) over local branches when creating from a base, ensuring you're working from the latest code.

## How It Works

Wave organizes your worktrees in a clean structure alongside your main repository:

```
/home/you/projects/
  ├── your-project/           # Your main repository
  └── your-project-wave/      # Wave worktrees directory (sibling to main repo)
      ├── feature-a/          # Worktree for feature-a branch
      ├── feature-b/          # Worktree for feature-b branch
      └── bugfix-123/         # Worktree for bugfix-123 branch
```

**Where to find your worktrees:**

If your main repo is at `/home/you/projects/myapp/`, Wave creates worktrees at `/home/you/projects/myapp-wave/`.

Each worktree is a complete working directory with its own branch checked out. You can open them in your editor, run dev servers, make commits - they're fully independent copies of your repository.

## Custom Hooks

Wave supports multiple hooks for automation. All hooks are created in `.wave/` when you run `wave init`.

### Worktree Lifecycle Hooks

**Setup Hook (`.wave/setup.sh`)**

Runs automatically **after** creating a new worktree:

```bash
#!/bin/sh
# Args: $1=worktree_path $2=branch_name
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

cd "$WORKTREE_PATH"
npm install
cp .env.example .env
echo "✅ Setup complete for $BRANCH_NAME"
```

**Cleanup Hook (`.wave/cleanup.sh`)**

Runs automatically **before** removing a worktree:

```bash
#!/bin/sh
# Args: $1=worktree_path $2=branch_name
WORKTREE_PATH="$1"
BRANCH_NAME="$2"

# Clean up any resources
echo "🧹 Cleaning up $BRANCH_NAME"
```

### Command Hooks

**Up Hook (`.wave/up.sh`)**

Runs **before** `wave up` or `wave create`:

```bash
#!/bin/sh
# Runs before creating any worktree
echo "🌊 Preparing to create worktree..."
# e.g., check disk space, fetch latest from origin
git fetch --all
```

**Down Hook (`.wave/down.sh`)**

Runs **before** `wave down` or `wave remove`:

```bash
#!/bin/sh
# Runs before removing any worktree
echo "🌊 Preparing to remove worktree..."
# e.g., backup data, notify team
```

**Status Hook (`.wave/status.sh`)**

Runs **before** `wave status` (also runs when you type just `wave`):

```bash
#!/bin/sh
# Runs before showing status
echo "🌊 Checking worktree health..."
# e.g., check for uncommitted changes, running processes
```

## Common Workflows

### Working on Multiple Features
```bash
# You're on develop, start two new features
wave create feature/user-auth develop
wave create feature/new-dashboard develop

# Each runs independently
wave exec feature/user-auth npm run dev -- --port 3001
wave exec feature/new-dashboard npm run dev -- --port 3002
```

### Reviewing a Teammate's PR
```bash
# Teammate pushed feature/cool-thing to origin
wave create feature/cool-thing

# Review it without affecting your current work
wave exec feature/cool-thing npm run test
```

### Hotfix from Production
```bash
# Production is on main, you're working on develop
wave create hotfix/critical-bug main

# Fix, test, and push - your develop work is untouched
wave remove hotfix/critical-bug
```

### Working Without PR Access
```bash
# You work on feature branches from develop
wave create feature/payment-flow develop
wave create feature/notifications develop

# Each is based on origin/develop (latest remote)
# No need to have develop checked out locally
```

## Requirements

- Git 2.5+ (for worktree support)
- POSIX-compliant shell (bash, zsh, sh)

## Updating Wave

Keep Wave up to date:

```bash
wave self-update
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - feel free to use Wave in your projects!

## Inspiration

Wave is inspired by the simplicity and elegance of:
- [Laravel Sail](https://laravel.com/docs/sail)
- [Vessel](https://vessel.shippingdocker.com/)

---

Made with 🌊 by developers who love clean workflows

