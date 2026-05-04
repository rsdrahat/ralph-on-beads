#!/usr/bin/env bash
set -e

# Ralph on Beads - Autonomous coding loop with per-iteration worktrees
# Usage: ./ralph.sh [max_iterations] [--verbose|-v] [--no-isolate]
#
# Each iteration runs Claude inside a fresh git worktree on a per-iteration
# branch (ralph/<iter-id>). On clean exit with new commits, the branch is
# fast-forwarded into your current branch and the worktree is removed. On
# fast-forward failure (e.g. another Ralph already advanced the base branch),
# the worktree+branch are left in place for manual merge or refinery.
#
# Environment overrides:
#   RALPH_AUTO_MERGE=0    Skip merge-back; leave branches for refinery
#   RALPH_WORKTREE_ROOT   Override worktree dir (default: <repo>/.ralph-worktrees)

MAX_ITERATIONS=100
VERBOSE_FLAG=""
ISOLATE=1

for arg in "$@"; do
  case "$arg" in
  --verbose | -v) VERBOSE_FLAG="--verbose" ;;
  --no-isolate)   ISOLATE=0 ;;
  [0-9]*)         MAX_ITERATIONS="$arg" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_ROOT="${RALPH_WORKTREE_ROOT:-$REPO_ROOT/.ralph-worktrees}"
AUTO_MERGE="${RALPH_AUTO_MERGE:-1}"

iteration=0

echo "Starting Ralph loop (max $MAX_ITERATIONS iterations, isolate=$ISOLATE)"

PROMPT_BODY="
Run \`bd ready --assignee=ralph -n 100 --sort=priority\` to see available tasks.

Also run \`bd list --status=in_progress --assignee=ralph\` to see what tasks other Ralph agents are currently working on.

Decide which task to work on next. Selection criteria:
1. Priority - higher priority tasks are more important
2. Avoid conflicts - if other Ralph agents have tasks in_progress, you MUST pick a completely different epic. Do NOT work on any task that is a child, parent, or sibling of an in-progress task. Stay away from the entire epic tree that another Ralph is working on.
3. If all high-priority epics are being worked on by other Ralphs, pick a lower-priority epic that is completely unrelated

Pick ONE task, claim it with \`bd update <id> --status in_progress\`, then execute it according to its description.

One iteration = complete the task AND all its child tasks (if any).

Commit your work to the current branch as you go. The outer ralph.sh loop manages worktree creation and merge-back; you do not need to create or switch branches.

IMPORTANT: After the task and all children are done (or if blocked), EXIT immediately. Do NOT pick up another top-level task. The outer loop will handle the next iteration.
"

run_claude() {
  local cwd="$1"
  (cd "$cwd" && claude --dangerously-skip-permissions --output-format stream-json --verbose -p "$PROMPT_BODY" 2>&1) \
    | "$SCRIPT_DIR/ralph-format.sh" $VERBOSE_FLAG || true
}

while [ $iteration -lt $MAX_ITERATIONS ]; do
  echo ""
  echo "=== Iteration $((iteration + 1)) ==="
  echo "---"

  available=$(bd ready --assignee=ralph -n 100 --json 2>/dev/null | jq -r 'length')

  if [ "$available" -eq 0 ]; then
    echo "No ready work available. Done."
    exit 0
  fi

  echo "$available ready task(s) available"
  echo ""

  if [ "$ISOLATE" -eq 1 ]; then
    ITER_ID="$(date +%s)-$$-$RANDOM"
    BRANCH="ralph/$ITER_ID"
    WT_PATH="$WORKTREE_ROOT/$ITER_ID"
    BASE_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

    mkdir -p "$WORKTREE_ROOT"
    echo "→ worktree: $WT_PATH on $BRANCH (base: $BASE_BRANCH)"
    git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WT_PATH" HEAD >/dev/null

    # Share .beads with main repo so bd writes hit one dolt db
    ln -s "$REPO_ROOT/.beads" "$WT_PATH/.beads"

    run_claude "$WT_PATH"

    has_dirty=0
    git -C "$WT_PATH" diff --quiet || has_dirty=1
    git -C "$WT_PATH" diff --cached --quiet || has_dirty=1

    new_commits="$(git -C "$REPO_ROOT" log "$BASE_BRANCH..$BRANCH" --oneline 2>/dev/null || true)"

    # Unlink the .beads symlink so 'git worktree remove' sees a clean worktree
    # (the symlink itself is untracked and would otherwise block removal).
    cleanup_worktree() {
      [ -L "$WT_PATH/.beads" ] && rm -f "$WT_PATH/.beads"
      git -C "$REPO_ROOT" worktree remove --force "$WT_PATH" >/dev/null
    }

    if [ "$has_dirty" -eq 1 ]; then
      echo "⚠ uncommitted changes in $WT_PATH — leaving worktree for inspection"
    elif [ -z "$new_commits" ]; then
      echo "→ no commits on $BRANCH; pruning worktree"
      cleanup_worktree
      git -C "$REPO_ROOT" branch -D "$BRANCH" >/dev/null
    elif [ "$AUTO_MERGE" = "1" ]; then
      echo "→ fast-forwarding $BRANCH into $BASE_BRANCH"
      if git -C "$REPO_ROOT" merge --ff-only "$BRANCH" >/dev/null 2>&1; then
        cleanup_worktree
        git -C "$REPO_ROOT" branch -d "$BRANCH" >/dev/null
        echo "✓ merged and cleaned up"
      else
        echo "⚠ fast-forward failed (parallel commits on $BASE_BRANCH); leaving $BRANCH and worktree for manual merge or refinery"
      fi
    else
      echo "→ RALPH_AUTO_MERGE=0; leaving $BRANCH for refinery"
    fi
  else
    run_claude "$REPO_ROOT"
  fi

  ((iteration++)) || true
done

echo ""
echo "Reached max iterations ($MAX_ITERATIONS)"
