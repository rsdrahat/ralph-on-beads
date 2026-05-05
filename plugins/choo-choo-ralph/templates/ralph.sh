#!/usr/bin/env bash
set -e

# Ralph on Beads - Autonomous coding loop with per-iteration worktrees
# Usage: ./ralph.sh [max_iterations] \
#                   [--verbose|-v] [--no-isolate] \
#                   [--assignee=<name>|any] \
#                   [--auto-promote=<formula>]
#
# Each iteration runs Claude inside a fresh git worktree on a per-iteration
# branch (ralph/<iter-id>). On clean exit with new commits, the branch is
# fast-forwarded into your current branch and the worktree is removed. On
# fast-forward failure (e.g. another Ralph already advanced the base branch),
# the worktree+branch are left in place for manual merge or refinery.
#
# Assignee filtering:
#   Default is `ralph` (the assignee that /choo-choo-ralph:pour stamps onto
#   molecule-poured beads). Pass `--assignee=any` (or set RALPH_ASSIGNEE=any)
#   to drop the filter entirely.
#
# Auto-promote (recommended for bare beads):
#   --auto-promote=choo-choo-ralph (or any formula registered via
#   `bd formula list`) makes the loop pick the next ready bead, and if it's
#   atomic (no children), pour a fresh molecule of the named formula seeded
#   from its title + description before invoking Claude. The original is
#   closed with a "promoted to molecule …" reason. Existing molecules pass
#   through unchanged. This gives every bead the same Bearings → Implement
#   → Verify → Commit structure without you having to spec/pour by hand.
#
# Environment overrides:
#   RALPH_ASSIGNEE        Assignee to filter on; "any" / "" disables filter
#   RALPH_AUTO_PROMOTE    Formula name (same as --auto-promote=…)
#   RALPH_AUTO_MERGE=0    Skip merge-back; leave branches for refinery
#   RALPH_WORKTREE_ROOT   Override worktree dir (default: <repo>/.ralph-worktrees)

MAX_ITERATIONS=100
VERBOSE_FLAG=""
ISOLATE=1
RALPH_ASSIGNEE="${RALPH_ASSIGNEE:-ralph}"
AUTO_PROMOTE="${RALPH_AUTO_PROMOTE:-}"

for arg in "$@"; do
  case "$arg" in
  --verbose | -v)    VERBOSE_FLAG="--verbose" ;;
  --no-isolate)      ISOLATE=0 ;;
  --assignee=*)      RALPH_ASSIGNEE="${arg#--assignee=}" ;;
  --auto-promote=*)  AUTO_PROMOTE="${arg#--auto-promote=}" ;;
  [0-9]*)            MAX_ITERATIONS="$arg" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_ROOT="${RALPH_WORKTREE_ROOT:-$REPO_ROOT/.ralph-worktrees}"
AUTO_MERGE="${RALPH_AUTO_MERGE:-1}"

# Build the assignee filter. "any" or empty disables it.
if [ "$RALPH_ASSIGNEE" = "any" ] || [ -z "$RALPH_ASSIGNEE" ]; then
  BD_FILTER=""
  READY_CMD="bd ready -n 100 --sort=priority"
  IN_PROGRESS_CMD="bd list --status=in_progress"
  ASSIGNEE_LABEL="any"
else
  BD_FILTER="--assignee=$RALPH_ASSIGNEE"
  READY_CMD="bd ready --assignee=$RALPH_ASSIGNEE -n 100 --sort=priority"
  IN_PROGRESS_CMD="bd list --status=in_progress --assignee=$RALPH_ASSIGNEE"
  ASSIGNEE_LABEL="$RALPH_ASSIGNEE"
fi

iteration=0

echo "Starting Ralph loop (max $MAX_ITERATIONS iterations, isolate=$ISOLATE, assignee=$ASSIGNEE_LABEL, auto_promote=${AUTO_PROMOTE:-off})"

# Default prompt: Claude picks from the queue itself. Used when --auto-promote
# is OFF, since the bash side hasn't pre-selected a bead.
PROMPT_PICK="
Run \`$READY_CMD\` to see available tasks.

Also run \`$IN_PROGRESS_CMD\` to see what other agents are currently working on.

Decide which task to work on next. Selection criteria:
1. Priority - higher priority tasks are more important
2. Avoid conflicts - if other agents have tasks in_progress, you MUST pick a completely different epic. Do NOT work on any task that is a child, parent, or sibling of an in-progress task. Stay away from the entire epic tree that another agent is working on.
3. If all high-priority epics are being worked on, pick a lower-priority epic that is completely unrelated

Pick ONE task, claim it with \`bd update <id> --status in_progress\`, then execute it according to its description.

One iteration = complete the task AND all its child tasks (if any). If the bead has no children (i.e. it's a bare \`bd create\` bead, not a molecule-poured one), just execute its description directly.

Commit your work to the current branch as you go. The outer ralph.sh loop manages worktree creation and merge-back; you do not need to create or switch branches.

IMPORTANT: After the task and all children are done (or if blocked), EXIT immediately. Do NOT pick up another top-level task. The outer loop will handle the next iteration.
"

# Builder for the auto-promote-mode prompt: bash already picked + (maybe)
# promoted, so Claude is told exactly which bead to work on.
build_assigned_prompt() {
  local id="$1"
  cat <<EOF

You have been assigned bead \`$id\` for this iteration.

1. Run \`bd show $id\` to read the task. The description is the source of truth.
2. Claim it: \`bd update $id --status in_progress\`.
3. If the description is an orchestrator (i.e. it tells you to "find ready steps" via \`bd ready --parent\`), run that orchestrator loop on this bead's children.
   Otherwise, the bead is atomic — execute its description directly.
4. When the work is complete, close the bead: \`bd close $id\`.

Commit your work to the current branch as you go. The outer ralph.sh loop manages worktree creation and merge-back; you do not need to create or switch branches.

EXIT after $id is closed (or if blocked). Do NOT pick up another top-level task.
EOF
}

run_claude() {
  local cwd="$1"
  local prompt="$2"
  (cd "$cwd" && claude --dangerously-skip-permissions --output-format stream-json --verbose -p "$prompt" 2>&1) \
    | "$SCRIPT_DIR/ralph-format.sh" $VERBOSE_FLAG || true
}

while [ $iteration -lt $MAX_ITERATIONS ]; do
  echo ""
  echo "=== Iteration $((iteration + 1)) ==="
  echo "---"

  available=$(bd ready $BD_FILTER -n 100 --json 2>/dev/null | jq -r 'length')

  if [ "$available" -eq 0 ]; then
    echo "No ready work available. Done."
    exit 0
  fi

  echo "$available ready task(s) available"

  # Decide the prompt for this iteration. With --auto-promote, bash picks
  # and (if atomic) promotes before invoking Claude.
  this_prompt="$PROMPT_PICK"
  if [ -n "$AUTO_PROMOTE" ]; then
    picked_id="$(bd ready $BD_FILTER -n 1 --sort=priority --json 2>/dev/null | jq -r '.[0].id // empty')"
    if [ -z "$picked_id" ]; then
      echo "→ no pickable bead this iteration; skipping"
      ((iteration++)) || true
      continue
    fi

    child_count="$(bd list --parent "$picked_id" --json 2>/dev/null | jq -r 'length // 0')"
    if [ "${child_count:-0}" = "0" ]; then
      echo "→ $picked_id is atomic; promoting via formula '$AUTO_PROMOTE'"
      if new_id="$("$SCRIPT_DIR/ralph-promote.sh" "$picked_id" "$AUTO_PROMOTE" "$RALPH_ASSIGNEE")"; then
        echo "→ promoted to molecule $new_id"
        picked_id="$new_id"
      else
        echo "⚠ promote failed for $picked_id; skipping iteration"
        ((iteration++)) || true
        continue
      fi
    else
      echo "→ $picked_id is already a molecule ($child_count children); passing through"
    fi

    this_prompt="$(build_assigned_prompt "$picked_id")"
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

    # Share .beads with main repo so bd writes hit one dolt db
    ln -s "$REPO_ROOT/.beads" "$WT_PATH/.beads"

    run_claude "$WT_PATH" "$this_prompt"

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
    run_claude "$REPO_ROOT" "$this_prompt"
  fi

  ((iteration++)) || true
done

echo ""
echo "Reached max iterations ($MAX_ITERATIONS)"
