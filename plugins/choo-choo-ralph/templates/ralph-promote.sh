#!/usr/bin/env bash
# ralph-promote.sh — Promote an atomic bead into a structured molecule.
#
# Reads the bead's title + description, pours a molecule of the given
# formula seeded with those values, and closes the original with a reason
# linking to the new molecule's root id. Prints the new root id on stdout.
#
# Usage: ./ralph-promote.sh <bead-id> <formula> [<assignee>]
# Exits non-zero on failure (writes diagnostic to stderr).

set -e

BEAD_ID="${1:?usage: $0 <bead-id> <formula> [<assignee>]}"
FORMULA="${2:?usage: $0 <bead-id> <formula> [<assignee>]}"
ASSIGNEE="${3:-ralph}"

show_json="$(bd show "$BEAD_ID" --json 2>/dev/null || true)"
if [ -z "$show_json" ] || [ "$show_json" = "[]" ]; then
  echo "ralph-promote: bead $BEAD_ID not found" >&2
  exit 2
fi

title="$(echo "$show_json" | jq -r '.[0].title // empty')"
desc="$(echo "$show_json"  | jq -r '.[0].description // empty')"

if [ -z "$title" ]; then
  echo "ralph-promote: bead $BEAD_ID has no title; refusing to promote" >&2
  exit 3
fi

# Refuse if it's already a molecule (would otherwise create duplicates).
child_count="$(bd list --parent "$BEAD_ID" --json 2>/dev/null | jq -r 'length // 0')"
if [ "${child_count:-0}" != "0" ]; then
  echo "ralph-promote: bead $BEAD_ID already has $child_count children; not atomic" >&2
  exit 4
fi

# Pour. The output line "Root issue: <id>" is what we need.
pour_output="$(bd mol pour "$FORMULA" --var "title=$title" --var "task=$desc" --assignee="$ASSIGNEE" 2>&1)"
new_id="$(echo "$pour_output" | awk '/Root issue:/ {print $NF}')"

if [ -z "$new_id" ]; then
  echo "ralph-promote: pour failed; output was:" >&2
  echo "$pour_output" >&2
  exit 5
fi

bd close "$BEAD_ID" --reason="auto-promoted to molecule $new_id via $FORMULA" >/dev/null

echo "$new_id"
