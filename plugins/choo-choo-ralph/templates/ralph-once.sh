#!/usr/bin/env bash
set -e

# Ralph on Beads - Single interactive iteration in an isolated worktree
# Usage: ./ralph-once.sh [--no-isolate]
#
# Creates a per-iteration git worktree on a fresh branch (ralph/<iter-id>),
# runs Claude interactively inside it, then attempts an --ff-only merge back
# to the base branch on clean exit.
#
# Environment overrides:
#   RALPH_AUTO_MERGE=0    Skip merge-back; leave the branch for refinery
#   RALPH_WORKTREE_ROOT   Override worktree dir (default: <repo>/.ralph-worktrees)

ISOLATE=1
[[ "$1" == "--no-isolate" ]] && ISOLATE=0

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_ROOT="${RALPH_WORKTREE_ROOT:-$REPO_ROOT/.ralph-worktrees}"
AUTO_MERGE="${RALPH_AUTO_MERGE:-1}"

echo "=== Ralph Single Iteration (isolate=$ISOLATE) ==="

available=$(bd ready --assignee=ralph -n 100 --json 2>/dev/null | jq -r 'length')

if [ "$available" -eq 0 ]; then
  echo "No open work available."
  exit 0
fi

echo "$available open task(s) available"
echo ""

PROMPT="
Run \`bd ready --assignee=ralph -n 100 --sort=priority\` to see available tasks.

Decide which task to work on next. This should be the one YOU decide has the highest priority - not necessarily the first in the list.

Pick ONE task, claim it with \`bd update <id> --status in_progress\`, then execute it according to its description.

One iteration = complete the task AND all its child tasks (if any).

Commit your work to the current branch as you go. The outer ralph-once.sh script manages worktree creation and merge-back; you do not need to create or switch branches.

After the task and all children are done (or if blocked), EXIT. This is a single iteration.
"

if [ "$ISOLATE" -eq 1 ]; then
  ITER_ID="$(date +%s)-$$-$RANDOM"
  BRANCH="ralph/$ITER_ID"
  WT_PATH="$WORKTREE_ROOT/$ITER_ID"
  BASE_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

  mkdir -p "$WORKTREE_ROOT"
  echo "→ worktree: $WT_PATH on $BRANCH (base: $BASE_BRANCH)"
  git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WT_PATH" HEAD >/dev/null
  ln -s "$REPO_ROOT/.beads" "$WT_PATH/.beads"

  (cd "$WT_PATH" && claude "$PROMPT") || true

  has_dirty=0
  git -C "$WT_PATH" diff --quiet || has_dirty=1
  git -C "$WT_PATH" diff --cached --quiet || has_dirty=1

  new_commits="$(git -C "$REPO_ROOT" log "$BASE_BRANCH..$BRANCH" --oneline 2>/dev/null || true)"

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
      echo "⚠ fast-forward failed; leaving $BRANCH and worktree for manual merge"
    fi
  else
    echo "→ RALPH_AUTO_MERGE=0; leaving $BRANCH"
  fi
else
  claude "$PROMPT"
fi
