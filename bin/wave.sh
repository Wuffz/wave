#!/usr/bin/env bash
# Wave — a tiny session manager in front of Claude Code.
#
# Every invocation drops you into at most one Claude session (or exits).
# Use your terminal multiplexer of choice to run wave in parallel windows.

set -eu

WAVE_VERSION="2.0.0"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/Wuffz/wave/main/bin/install.sh"

# ---------- repo / config ----------

require_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "wave: not inside a Git repository." >&2
    exit 1
  }
}

load_repo_info() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  COMMON_DIR="$(git rev-parse --git-common-dir)"
  case "$COMMON_DIR" in
    /*) ;;
    *) COMMON_DIR="$REPO_ROOT/$COMMON_DIR" ;;
  esac
  MAIN_REPO="$(cd "$COMMON_DIR/.." && pwd)"
  PROJECT_NAME="$(basename "$MAIN_REPO")"
  WAVE_DIR="$MAIN_REPO/.wave"
  WAVE_WORKTREES="$(dirname "$MAIN_REPO")/${PROJECT_NAME}-wave"
}

load_config() {
  DEFAULT_BASE_BRANCH=""
  if [ -f "$WAVE_DIR/config" ]; then
    DEFAULT_BASE_BRANCH="$(grep -E '^DEFAULT_BASE_BRANCH=' "$WAVE_DIR/config" 2>/dev/null | cut -d'=' -f2- || true)"
  fi
}

ensure_init() {
  [ -d "$WAVE_DIR" ] || wave_init_silent
}

wave_init_silent() {
  mkdir -p "$WAVE_DIR" "$WAVE_WORKTREES"
  if [ ! -f "$WAVE_DIR/config" ]; then
    cat > "$WAVE_DIR/config" <<'EOF'
# Wave configuration
# Default base branch when creating new worktrees (blank = current branch)
DEFAULT_BASE_BRANCH=
EOF
  fi
  for h in setup cleanup go-live; do
    if [ ! -f "$WAVE_DIR/$h.sh" ]; then
      cat > "$WAVE_DIR/$h.sh" <<EOF
#!/usr/bin/env bash
# Wave hook: $h — see README.md for args
EOF
      chmod +x "$WAVE_DIR/$h.sh"
    fi
  done
}

# ---------- small ui helpers ----------

hr() { printf -- '%.0s-' $(seq 1 "${COLUMNS:-60}"); echo; }

header() {
  hr
  printf "  wave  -  %s\n" "$1"
  hr
}

# Picks an item from an array by number. Sets REPLY_INDEX (0-based) or returns 1.
pick_from() {
  local prompt="$1"; shift
  local items=("$@")
  local n=${#items[@]}
  [ "$n" -eq 0 ] && return 1
  local i=1
  for item in "${items[@]}"; do
    printf "  %2d) %s\n" "$i" "$item"
    i=$((i+1))
  done
  echo
  while :; do
    printf "%s" "$prompt"
    local input=""
    read -r input || return 1
    [ -z "$input" ] && return 1
    case "$input" in
      q|Q) return 1 ;;
      ''|*[!0-9]*) echo "  enter a number 1..$n (or q)"; continue ;;
    esac
    if [ "$input" -ge 1 ] && [ "$input" -le "$n" ]; then
      REPLY_INDEX=$((input-1))
      return 0
    fi
    echo "  out of range; pick 1..$n (or q)"
  done
}

confirm() {
  local prompt="$1"
  printf "%s [y/N] " "$prompt"
  local ans=""
  read -r ans || return 1
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- listings ----------

list_worktrees_paths() {
  git -C "$MAIN_REPO" worktree list --porcelain | awk -v main="$MAIN_REPO" '
    /^worktree /{ p=$2; next }
    /^$/{ if (p && p != main) print p; p="" }
    END{ if (p && p != main) print p }
  '
}

list_worktrees_labels() {
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    local b t
    b="$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    t="$(git -C "$p" log -1 --format=%cr 2>/dev/null || echo '?')"
    printf "%s\t%s\t%s\n" "$b" "$p" "$t"
  done < <(list_worktrees_paths)
}

list_remote_branches() {
  git -C "$MAIN_REPO" fetch --prune --quiet origin 2>/dev/null || true
  git -C "$MAIN_REPO" for-each-ref --format='%(refname:short)' refs/remotes/origin \
    | sed 's#^origin/##' \
    | grep -v '^HEAD$' \
    | sort -u
}

list_local_branches() {
  git -C "$MAIN_REPO" for-each-ref --format='%(refname:short)' refs/heads \
    | sort -u
}

# ---------- flows ----------

flow_new() {
  header "new session"

  echo "Pick a base branch:"
  local -a bases=()
  local current
  current="$(git -C "$MAIN_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'main')"
  bases+=("$current (current)")

  local b
  while IFS= read -r b; do
    [ "$b" = "$current" ] && continue
    bases+=("$b")
  done < <({ list_local_branches; list_remote_branches; } | sort -u)

  if ! pick_from "Base> " "${bases[@]}"; then
    echo "cancelled."
    return 0
  fi
  local base="${bases[$REPLY_INDEX]}"
  base="${base% (current)}"

  echo
  printf "New branch name: "
  local new_branch=""
  read -r new_branch || return 0
  [ -z "$new_branch" ] && { echo "cancelled."; return 0; }

  case "$new_branch" in
    *' '*|*..*|*'~'*|*'^'*|*':'*|*'\'*|*'?'*|*'*'*|*'['*)
      echo "wave: invalid branch name." >&2
      return 1
      ;;
  esac

  local target="$WAVE_WORKTREES/$new_branch"
  if [ -e "$target" ]; then
    echo "wave: worktree path already exists: $target" >&2
    return 1
  fi

  local base_ref=""
  if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/remotes/origin/$base"; then
    base_ref="origin/$base"
  elif git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$base"; then
    base_ref="$base"
  else
    echo "wave: base branch '$base' not found locally or on origin." >&2
    return 1
  fi

  echo
  echo "Creating worktree '$new_branch' from '$base_ref' at:"
  echo "  $target"
  git -C "$MAIN_REPO" worktree add -b "$new_branch" "$target" "$base_ref"

  if [ -x "$WAVE_DIR/setup.sh" ]; then
    "$WAVE_DIR/setup.sh" "$target" "$new_branch" || echo "wave: setup hook exited non-zero (continuing)"
  fi

  launch_claude_in "$target" ""
}

flow_resume() {
  header "resume session"

  local -a lines=()
  while IFS= read -r line; do lines+=("$line"); done < <(list_worktrees_labels)

  if [ "${#lines[@]}" -eq 0 ]; then
    echo "No worktrees yet. Use 'new' to create one."
    return 0
  fi

  local -a labels=()
  local -a paths=()
  local row
  for row in "${lines[@]}"; do
    local b p t
    b="$(printf '%s' "$row" | cut -f1)"
    p="$(printf '%s' "$row" | cut -f2)"
    t="$(printf '%s' "$row" | cut -f3)"
    labels+=("$(printf '%-30s  %s' "$b" "$t")")
    paths+=("$p")
  done

  if ! pick_from "Worktree> " "${labels[@]}"; then
    echo "cancelled."
    return 0
  fi

  launch_claude_in "${paths[$REPLY_INDEX]}" "--continue"
}

flow_list() {
  header "worktrees"
  local any=0
  local row
  while IFS= read -r row; do
    any=1
    local b p t
    b="$(printf '%s' "$row" | cut -f1)"
    p="$(printf '%s' "$row" | cut -f2)"
    t="$(printf '%s' "$row" | cut -f3)"
    local dirty=""
    if [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then
      dirty=" *"
    fi
    printf "  %s%s\n    %s   (%s)\n" "$b" "$dirty" "$p" "$t"
  done < <(list_worktrees_labels)
  [ "$any" -eq 0 ] && echo "  (none)"
  echo
  printf "  main repo: %s  (branch: %s)\n" \
    "$MAIN_REPO" \
    "$(git -C "$MAIN_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
}

flow_go_live() {
  header "go live - swap main checkout"

  if [ -n "$(git -C "$MAIN_REPO" status --porcelain 2>/dev/null)" ]; then
    echo "wave: main repo has uncommitted changes - aborting." >&2
    echo "  $MAIN_REPO" >&2
    return 1
  fi

  local -a lines=()
  while IFS= read -r line; do lines+=("$line"); done < <(list_worktrees_labels)
  if [ "${#lines[@]}" -eq 0 ]; then
    echo "No worktrees to promote."
    return 0
  fi

  local -a labels=()
  local -a branches=()
  local -a paths=()
  local row
  for row in "${lines[@]}"; do
    local b p t
    b="$(printf '%s' "$row" | cut -f1)"
    p="$(printf '%s' "$row" | cut -f2)"
    t="$(printf '%s' "$row" | cut -f3)"
    labels+=("$(printf '%-30s  %s' "$b" "$t")")
    branches+=("$b")
    paths+=("$p")
  done

  if ! pick_from "Promote> " "${labels[@]}"; then
    echo "cancelled."
    return 0
  fi

  local branch="${branches[$REPLY_INDEX]}"
  local source_path="${paths[$REPLY_INDEX]}"

  echo
  echo "About to check out '$branch' in:"
  echo "  $MAIN_REPO"
  echo "Source worktree '$source_path' will be briefly detached."
  confirm "Proceed?" || { echo "cancelled."; return 0; }

  local prev_head
  prev_head="$(git -C "$source_path" rev-parse HEAD)"
  git -C "$source_path" checkout --detach --quiet "$prev_head"

  if ! git -C "$MAIN_REPO" checkout "$branch"; then
    echo "wave: checkout failed; re-attaching worktree." >&2
    git -C "$source_path" checkout --quiet "$branch" || true
    return 1
  fi

  echo
  echo "OK - main repo now on '$branch'."
  echo "  (Worktree $source_path is detached at $prev_head until you swap back.)"

  if [ -x "$WAVE_DIR/go-live.sh" ]; then
    echo
    echo "Running go-live hook..."
    "$WAVE_DIR/go-live.sh" "$branch" "$MAIN_REPO" || echo "wave: go-live hook exited non-zero"
  fi
}

flow_clean() {
  header "clean worktrees"

  local -a lines=()
  while IFS= read -r line; do lines+=("$line"); done < <(list_worktrees_labels)
  if [ "${#lines[@]}" -eq 0 ]; then
    echo "Nothing to clean."
    return 0
  fi

  local -a labels=()
  local -a paths=()
  local -a branches=()
  local row
  for row in "${lines[@]}"; do
    local b p t
    b="$(printf '%s' "$row" | cut -f1)"
    p="$(printf '%s' "$row" | cut -f2)"
    t="$(printf '%s' "$row" | cut -f3)"
    local flag=""
    [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ] && flag=" [dirty]"
    labels+=("$(printf '%-30s  %s%s' "$b" "$t" "$flag")")
    paths+=("$p")
    branches+=("$b")
  done

  if ! pick_from "Remove> " "${labels[@]}"; then
    echo "cancelled."
    return 0
  fi

  local path="${paths[$REPLY_INDEX]}"
  local branch="${branches[$REPLY_INDEX]}"

  echo
  echo "Will remove worktree:"
  echo "  $path  ($branch)"
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    echo "  ! worktree has uncommitted changes."
  fi
  confirm "Remove?" || { echo "cancelled."; return 0; }

  if [ -x "$WAVE_DIR/cleanup.sh" ]; then
    "$WAVE_DIR/cleanup.sh" "$path" "$branch" || echo "wave: cleanup hook exited non-zero (continuing)"
  fi

  git -C "$MAIN_REPO" worktree remove --force "$path"

  if confirm "Also delete branch '$branch'?"; then
    git -C "$MAIN_REPO" branch -D "$branch" || true
  fi

  git -C "$MAIN_REPO" worktree prune
  echo "removed."
}

# ---------- launcher ----------

launch_claude_in() {
  local dir="$1"
  local claude_flag="${2:-}"
  if ! command -v claude >/dev/null 2>&1; then
    echo "wave: 'claude' not found in PATH. Install Claude Code first." >&2
    echo "  worktree is ready at: $dir" >&2
    return 1
  fi
  cd "$dir"
  echo
  echo "-> launching claude in $dir"
  if [ -n "$claude_flag" ]; then
    exec claude "$claude_flag"
  else
    exec claude
  fi
}

# ---------- menu ----------

main_menu() {
  header "$PROJECT_NAME"
  echo "  [n] new session"
  echo "  [r] resume session"
  echo "  [l] list worktrees"
  echo "  [g] go live (swap main checkout)"
  echo "  [c] clean a worktree"
  echo "  [q] quit"
  echo
  printf "> "
  local choice=""
  read -r choice || { echo; return 0; }
  case "$choice" in
    n|N|new) flow_new ;;
    r|R|resume) flow_resume ;;
    l|L|list|ls) flow_list ;;
    g|G|go-live|golive) flow_go_live ;;
    c|C|clean) flow_clean ;;
    q|Q|quit|'') echo "bye." ;;
    *) echo "unknown choice: $choice"; return 1 ;;
  esac
}

# ---------- self-update ----------

wave_self_update() {
  local wave_path
  wave_path="$(command -v wave 2>/dev/null || true)"
  if [ -z "$wave_path" ]; then
    echo "wave: could not locate installation - reinstall:" >&2
    echo "  curl -fsSL $INSTALL_SCRIPT_URL | sh" >&2
    exit 1
  fi
  local install_type="1"
  case "$wave_path" in
    "$HOME"/.local/bin/wave) install_type="1" ;;
    /usr/local/bin/wave) install_type="2" ;;
  esac
  echo "Updating wave at $wave_path ..."
  if command -v curl >/dev/null 2>&1; then
    echo "$install_type" | curl -fsSL "$INSTALL_SCRIPT_URL" | sh
  elif command -v wget >/dev/null 2>&1; then
    echo "$install_type" | wget -qO- "$INSTALL_SCRIPT_URL" | sh
  else
    echo "wave: need curl or wget" >&2
    exit 1
  fi
}

# ---------- dispatch ----------

usage() {
  cat <<EOF
wave $WAVE_VERSION - session manager for Claude Code

usage:
  wave                  open main menu
  wave new              create a new worktree + session
  wave resume           pick a worktree and continue its session
  wave list             list worktrees
  wave go-live          promote a worktree's branch to the main checkout
  wave clean            remove a worktree
  wave init             create .wave/ config + hooks
  wave self-update      reinstall from latest
  wave version          print version
  wave help             this message

hooks (run if executable):
  .wave/setup.sh    <worktree-path> <branch>        after 'new'
  .wave/cleanup.sh  <worktree-path> <branch>        before 'clean'
  .wave/go-live.sh  <branch> <main-repo-path>       after 'go-live'
EOF
}

main() {
  case "${1:-}" in
    version|--version|-v) echo "wave $WAVE_VERSION"; exit 0 ;;
    help|--help|-h) usage; exit 0 ;;
    self-update) wave_self_update; exit 0 ;;
  esac

  require_git_repo
  load_repo_info
  ensure_init
  load_config

  case "${1:-}" in
    '') main_menu ;;
    new|n) flow_new ;;
    resume|r|continue) flow_resume ;;
    list|ls|l) flow_list ;;
    go-live|golive|g|live) flow_go_live ;;
    clean|c|rm|remove) flow_clean ;;
    init) wave_init_silent; echo "wave: initialized $WAVE_DIR" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
