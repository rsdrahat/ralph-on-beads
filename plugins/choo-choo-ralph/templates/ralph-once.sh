#!/usr/bin/env bash
set -e

# Ralph on Beads - Single interactive iteration in an isolated worktree
# Usage: ./ralph-once.sh [--no-isolate] [--assignee=<name>|any] [--auto-promote=<formula>]
#
# Creates a per-iteration git worktree on a fresh branch (ralph/<iter-id>),
# runs Claude interactively inside it, then attempts an --ff-only merge back
# to the base branch on clean exit.
#
# Assignee filtering:
#   Default is `ralph`. Pass `--assignee=any` (or set RALPH_ASSIGNEE=any) to
#   drop the filter and pick from all ready beads.
#
# Auto-promote:
#   --auto-promote=<formula> makes this script pick the next ready bead, and
#   if it's atomic, pour a fresh molecule of the named formula seeded from
#   its title + description before launching Claude. See ralph.sh for details.
#
# Environment overrides:
#   RALPH_ASSIGNEE        Assignee to filter on; "any" / "" disables filter
#   RALPH_AUTO_PROMOTE    Formula name (same as --auto-promote=…)
#   RALPH_AUTO_MERGE=0    Skip merge-back; leave the branch for refinery
#   RALPH_WORKTREE_ROOT   Override worktree dir (default: <repo>/.ralph-worktrees)

ISOLATE=1
RALPH_ASSIGNEE="${RALPH_ASSIGNEE:-ralph}"
AUTO_PROMOTE="${RALPH_AUTO_PROMOTE:-}"

for arg in "$@"; do
  case "$arg" in
  --no-isolate)     ISOLATE=0 ;;
  --assignee=*)     RALPH_ASSIGNEE="${arg#--assignee=}" ;;
  --auto-promote=*) AUTO_PROMOTE="${arg#--auto-promote=}" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_ROOT="${RALPH_WORKTREE_ROOT:-$REPO_ROOT/.ralph-worktrees}"
AUTO_MERGE="${RALPH_AUTO_MERGE:-1}"

if [ "$RALPH_ASSIGNEE" = "any" ] || [ -z "$RALPH_ASSIGNEE" ]; then
  BD_FILTER=""
  READY_CMD="bd ready -n 100 --sort=priority"
  ASSIGNEE_LABEL="any"
else
  BD_FILTER="--assignee=$RALPH_ASSIGNEE"
  READY_CMD="bd ready --assignee=$RALPH_ASSIGNEE -n 100 --sort=priority"
  ASSIGNEE_LABEL="$RALPH_ASSIGNEE"
fi

echo "=== Ralph Single Iteration (isolate=$ISOLATE, assignee=$ASSIGNEE_LABEL, auto_promote=${AUTO_PROMOTE:-off}) ==="

available=$(bd ready $BD_FILTER -n 100 --json 2>/dev/null | jq -r 'length')

if [ "$available" -eq 0 ]; then
  echo "No open work available."
  exit 0
fi

echo "$available open task(s) available"

# When --auto-promote is set, pick + (maybe) promote in bash before launching
# Claude. Tell Claude exactly which bead to work on.
PICKED_ID=""
if [ -n "$AUTO_PROMOTE" ]; then
  PICKED_ID="$(bd ready $BD_FILTER -n 1 --sort=priority --json 2>/dev/null | jq -r '.[0].id // empty')"
  if [ -z "$PICKED_ID" ]; then
    echo "No pickable bead. Done."
    exit 0
  fi
  child_count="$(bd list --parent "$PICKED_ID" --json 2>/dev/null | jq -r 'length // 0')"
  if [ "${child_count:-0}" = "0" ]; then
    echo "→ $PICKED_ID is atomic; promoting via formula '$AUTO_PROMOTE'"
    if new_id="$("$SCRIPT_DIR/ralph-promote.sh" "$PICKED_ID" "$AUTO_PROMOTE" "$RALPH_ASSIGNEE")"; then
      echo "→ promoted to molecule $new_id"
      PICKED_ID="$new_id"
    else
      echo "⚠ promote failed; aborting"
      exit 1
    fi
  fi
fi

if [ -n "$PICKED_ID" ]; then
  PROMPT="
You have been assigned bead \`$PICKED_ID\` for this iteration.

1. Run \`bd show $PICKED_ID\` to read the task. The description is the source of truth.
2. Claim it: \`bd update $PICKED_ID --status in_progress\`.
3. If the description is an orchestrator (i.e. it tells you to find ready steps via \`bd ready --parent\`), run that orchestrator loop on this bead's children. Otherwise, the bead is atomic — execute its description directly.
4. When done, close the bead: \`bd close $PICKED_ID\`.

Commit your work to the current branch as you go. The outer ralph-once.sh script manages worktree creation and merge-back; you do not need to create or switch branches.

EXIT after $PICKED_ID is closed (or if blocked).
"
else
  PROMPT="
Run \`$READY_CMD\` to see available tasks.

Decide which task to work on next. This should be the one YOU decide has the highest priority - not necessarily the first in the list.

Pick ONE task, claim it with \`bd update <id> --status in_progress\`, then execute it according to its description.

One iteration = complete the task AND all its child tasks (if any). If the bead has no children (i.e. it's a bare \`bd create\` bead, not a molecule-poured one), just execute its description directly.

Commit your work to the current branch as you go. The outer ralph-once.sh script manages worktree creation and merge-back; you do not need to create or switch branches.

After the task and all children are done (or if blocked), EXIT. This is a single iteration.
"
fi

echo ""

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
