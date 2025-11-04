#!/bin/sh

require_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Not inside a Git repository."
    exit 1
  }
}

get_repo_info() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PROJECT_NAME="$(basename "$REPO_ROOT")"
  WAVE_DIR="$REPO_ROOT/.wave"
  WAVE_WORKTREES="$(dirname "$REPO_ROOT")/${PROJECT_NAME}-wave"
}

wave_init() {
  get_repo_info
  mkdir -p "$WAVE_DIR" "$WAVE_WORKTREES"

  # Create hook files
  touch "$WAVE_DIR/setup.sh" "$WAVE_DIR/cleanup.sh" "$WAVE_DIR/up.sh" "$WAVE_DIR/down.sh" "$WAVE_DIR/status.sh"
  chmod +x "$WAVE_DIR/setup.sh" "$WAVE_DIR/cleanup.sh" "$WAVE_DIR/up.sh" "$WAVE_DIR/down.sh" "$WAVE_DIR/status.sh"

  # Add default content to hooks
  echo "#!/bin/sh\n# setup logic for new worktree\n# Args: \$1=worktree_path \$2=branch_name" > "$WAVE_DIR/setup.sh"
  echo "#!/bin/sh\n# cleanup logic for removed worktree\n# Args: \$1=worktree_path \$2=branch_name" > "$WAVE_DIR/cleanup.sh"
  echo "#!/bin/sh\n# runs before wave up/create" > "$WAVE_DIR/up.sh"
  echo "#!/bin/sh\n# runs before wave down/remove" > "$WAVE_DIR/down.sh"
  echo "#!/bin/sh\n# runs before wave status" > "$WAVE_DIR/status.sh"

  echo "Initialized .wave and ${PROJECT_NAME}-wave directories"
  echo "Created hooks: setup.sh, cleanup.sh, up.sh, down.sh, status.sh"
}

wave_create() {
  BRANCH="$1"
  BASE_BRANCH="$2"
  [ -z "$BRANCH" ] && echo "Usage: wave create <branch> [base-branch]" && exit 1
  require_git_repo
  get_repo_info

  TARGET="$WAVE_WORKTREES/$BRANCH"

  # Check if branch exists locally
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Using existing local branch '$BRANCH'"
    git -C "$REPO_ROOT" worktree add "$TARGET" "$BRANCH"
  # Check if branch exists on remote
  elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    echo "Checking out remote branch 'origin/$BRANCH'"
    git -C "$REPO_ROOT" worktree add "$TARGET" "$BRANCH"
  # Create new branch
  else
    if [ -n "$BASE_BRANCH" ]; then
      # Try remote first, then local
      if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
        echo "Creating '$BRANCH' from 'origin/$BASE_BRANCH'"
        BASE_REF="origin/$BASE_BRANCH"
      elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
        echo "Creating '$BRANCH' from local '$BASE_BRANCH'"
        BASE_REF="$BASE_BRANCH"
      else
        echo "Error: Base branch '$BASE_BRANCH' not found locally or on origin"
        exit 1
      fi
    else
      # Default to current HEAD
      echo "Creating '$BRANCH' from current HEAD"
      BASE_REF="HEAD"
    fi
    git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$TARGET" "$BASE_REF"
  fi

  [ -x "$WAVE_DIR/setup.sh" ] && "$WAVE_DIR/setup.sh" "$TARGET" "$BRANCH"
  echo "Worktree '$BRANCH' created at $TARGET"
}

wave_remove() {
  BRANCH="$1"
  [ -z "$BRANCH" ] && echo "Usage: wave remove <branch>" && exit 1
  require_git_repo
  get_repo_info

  TARGET="$WAVE_WORKTREES/$BRANCH"
  [ -d "$TARGET" ] || { echo "No worktree found for branch '$BRANCH'"; exit 1; }

  [ -x "$WAVE_DIR/cleanup.sh" ] && "$WAVE_DIR/cleanup.sh" "$TARGET" "$BRANCH"
  git -C "$REPO_ROOT" worktree remove "$TARGET"
  echo "Worktree '$BRANCH' removed"
}

# Aliases for backward compatibility with hooks
wave_up() {
  require_git_repo
  get_repo_info
  [ -x "$WAVE_DIR/up.sh" ] && "$WAVE_DIR/up.sh"
  wave_create "$@"
}

wave_down() {
  require_git_repo
  get_repo_info
  [ -x "$WAVE_DIR/down.sh" ] && "$WAVE_DIR/down.sh"
  wave_remove "$@"
}

wave_ls() {
  require_git_repo
  get_repo_info
  echo "Active worktrees:"
  git -C "$REPO_ROOT" worktree list
}

wave_status() {
  require_git_repo
  get_repo_info

  # Run status hook if it exists
  [ -x "$WAVE_DIR/status.sh" ] && "$WAVE_DIR/status.sh"

  echo "Worktree status:"
  for path in "$WAVE_WORKTREES"/*; do
    [ -d "$path" ] || continue
    BRANCH="$(basename "$path")"
    COMMIT="$(git -C "$path" rev-parse HEAD 2>/dev/null)"
    echo "  $BRANCH -> $COMMIT @ $path"
  done
}

wave_exec() {
  BRANCH="$1"; shift
  [ -z "$BRANCH" ] && echo "Usage: wave exec <branch> <command>" && exit 1
  require_git_repo
  get_repo_info

  TARGET="$WAVE_WORKTREES/$BRANCH"
  [ -d "$TARGET" ] || { echo "No worktree found for branch '$BRANCH'"; exit 1; }

  (cd "$TARGET" && "$@")
}

wave_prune() {
  require_git_repo
  get_repo_info
  echo "Pruning stale worktrees..."
  git -C "$REPO_ROOT" worktree prune
  echo "Done"
}

wave_self_update() {
  INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/Wuffz/wave/main/bin/install.sh"
  WAVE_PATH="$(command -v wave 2>/dev/null)"

  [ -z "$WAVE_PATH" ] && {
    echo "Error: Could not locate wave installation"
    echo "Please reinstall using: curl -fsSL $INSTALL_SCRIPT_URL | sh"
    exit 1
  }

  echo "Updating wave..."
  echo "Current location: $WAVE_PATH"

  # Determine if this is a user or global install
  case "$WAVE_PATH" in
    "$HOME"/.local/bin/wave)
      echo "Detected user installation"
      INSTALL_TYPE="1"
      ;;
    /usr/local/bin/wave)
      echo "Detected global installation"
      INSTALL_TYPE="2"
      ;;
    *)
      echo "Custom installation location detected"
      echo "Defaulting to user install"
      INSTALL_TYPE="1"
      ;;
  esac

  echo ""

  # Download and run install script with the appropriate choice (non-interactive)
  if command -v curl >/dev/null 2>&1; then
    echo "$INSTALL_TYPE" | curl -fsSL "$INSTALL_SCRIPT_URL" | sh
  elif command -v wget >/dev/null 2>&1; then
    echo "$INSTALL_TYPE" | wget -qO- "$INSTALL_SCRIPT_URL" | sh
  else
    echo "Error: Neither curl nor wget is available"
    exit 1
  fi

  echo ""
  echo "Wave updated successfully!"
}

case "$1" in
  init) wave_init ;;
  create) wave_create "$2" "$3" ;;
  remove) wave_remove "$2" ;;
  up) wave_up "$2" "$3" ;;
  down) wave_down "$2" ;;
  ls) wave_ls ;;
  status) wave_status ;;
  exec) shift; wave_exec "$@" ;;
  prune) wave_prune ;;
  self-update) wave_self_update ;;
  "")
    # Default to status when no command provided
    wave_status
    ;;
  *)
    echo "Usage: wave {init|create <branch> [base]|remove <branch>|ls|status|exec <branch> <cmd>|prune|self-update}"
    echo "       Aliases: up (create), down (remove)"
    echo "       Run 'wave' without arguments to show status"
    exit 1
    ;;
esac