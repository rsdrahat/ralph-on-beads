#!/usr/bin/env bash
set -e

# Ralph Overseer — long-running Claude session that dispatches parallel
# ralph-worker subagents to execute beads from a team's queue.
#
# This is the bash *bootstrap*. The orchestration loop lives inside the
# Claude session, driven by ralph-overseer-prompt.md.
#
# STATUS: SCAFFOLD. Not yet wired into /choo-choo-ralph:install or
# end-to-end tested. See ralph-on-beads-trz.
#
# Usage:
#   AGENT_TEAM=team-credit-feedback ./ralph-overseer.sh
#
# Required env:
#   AGENT_TEAM            bd assignee to filter on (e.g. team-credit-feedback)
#
# Optional env:
#   RALPH_MAX_PARALLEL    max concurrent workers (default 3)
#   RALPH_AUTO_PROMOTE    formula name to auto-pour atomic beads
#                         (e.g. choo-choo-ralph). Empty = disabled.
#   RALPH_BASE_BRANCH     ff-merge target (default: current HEAD branch)
#   RALPH_WORKTREE_ROOT   override worktree directory (default: /tmp)

if [ -z "${AGENT_TEAM:-}" ]; then
  echo "ralph-overseer: AGENT_TEAM is required (e.g. AGENT_TEAM=team-credit-feedback)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
RALPH_MAX_PARALLEL="${RALPH_MAX_PARALLEL:-3}"
RALPH_BASE_BRANCH="${RALPH_BASE_BRANCH:-$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)}"
RALPH_WORKTREE_ROOT="${RALPH_WORKTREE_ROOT:-/tmp}"
RALPH_AUTO_PROMOTE="${RALPH_AUTO_PROMOTE:-}"

export AGENT_TEAM REPO_ROOT RALPH_MAX_PARALLEL RALPH_AUTO_PROMOTE RALPH_BASE_BRANCH RALPH_WORKTREE_ROOT

PROMPT_FILE="$SCRIPT_DIR/ralph-overseer-prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
  echo "ralph-overseer: missing prompt file: $PROMPT_FILE" >&2
  exit 1
fi

cat <<EOF
Starting Ralph overseer
  team           : $AGENT_TEAM
  repo           : $REPO_ROOT
  base branch    : $RALPH_BASE_BRANCH
  max parallel   : $RALPH_MAX_PARALLEL
  auto-promote   : ${RALPH_AUTO_PROMOTE:-off}
  worktree root  : $RALPH_WORKTREE_ROOT

EOF

exec claude --dangerously-skip-permissions -p "$(cat "$PROMPT_FILE")"
