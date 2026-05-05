---
description: Install Choo Choo Ralph into the current project
---

# Install Choo Choo Ralph

Set up the Ralph autonomous coding workflow in this project.

## Pre-requisites Check

1. **Check beads CLI**: Run `bd --version`
   - If not installed: "Please install beads first. See: https://github.com/steveyegge/beads"

2. **Check Claude CLI**: Run `claude --version`
   - If not installed: Warn user they'll need it to run Ralph

3. **Check jq**: Run `jq --version`
   - If not installed: "Please install jq for JSON parsing. See: https://jqlang.github.io/jq/"

4. **Initialize beads**: If `.beads/` doesn't exist, run `bd init`

## Check for Existing Files

Before installing, check which files already exist:
- `./ralph.sh`
- `./ralph-once.sh`
- `./ralph-format.sh`
- `./ralph-promote.sh`
- `.beads/formulas/choo-choo-ralph.formula.toml`
- `.beads/formulas/bug-fix.formula.toml`

**If ANY files exist**: Use AskUserQuestion to ask user for each existing file whether to:
- Skip (keep existing)
- Overwrite (replace with new version)

**If NO files exist**: Proceed directly to installation.

## Installation Steps

Use Bash `cp` commands for fast file copying (NOT Read/Write tools).

1. **Copy shell scripts** to project root (if not skipped):
   ```bash
   cp "${CLAUDE_PLUGIN_ROOT}/templates/ralph.sh" ./ralph.sh
   cp "${CLAUDE_PLUGIN_ROOT}/templates/ralph-once.sh" ./ralph-once.sh
   cp "${CLAUDE_PLUGIN_ROOT}/templates/ralph-format.sh" ./ralph-format.sh
   cp "${CLAUDE_PLUGIN_ROOT}/templates/ralph-promote.sh" ./ralph-promote.sh
   chmod +x ralph.sh ralph-once.sh ralph-format.sh ralph-promote.sh
   ```

2. **Set up formulas directory**:
   ```bash
   mkdir -p .beads/formulas
   cp "${CLAUDE_PLUGIN_ROOT}/templates/choo-choo-ralph.formula.toml" .beads/formulas/
   cp "${CLAUDE_PLUGIN_ROOT}/templates/bug-fix.formula.toml" .beads/formulas/
   ```

3. **Create spec directory**:
   ```bash
   mkdir -p .choo-choo-ralph
   ```

4. **Add worktree dir to .gitignore**:
   Append `.ralph-worktrees/` to `.gitignore` if not already present. Ralph
   creates per-iteration git worktrees there for isolation when running in
   parallel; they should never be committed.
   ```bash
   grep -qxF '.ralph-worktrees/' .gitignore 2>/dev/null || echo '.ralph-worktrees/' >> .gitignore
   ```

5. **Verify installation**:
   - Confirm all files exist
   - Run `bd formula list` to verify both formulas are registered (choo-choo-ralph and bug-fix)

## Recommended Plugins

1. **Check dev-browser plugin**: Check your available skills for `dev-browser`
   - If not available, recommend installing it for browser-based smoke tests and UI verification
   - GitHub: https://github.com/SawyerHood/dev-browser
   - This plugin is used by the bearings step (smoke test) and verify step (UI verification)

## Output

Report what was installed (and what was skipped if applicable):

- Scripts: ralph.sh, ralph-once.sh, ralph-format.sh, ralph-promote.sh
- Formulas: .beads/formulas/choo-choo-ralph.formula.toml, .beads/formulas/bug-fix.formula.toml
- Spec directory: .choo-choo-ralph/
- Worktree dir: `.ralph-worktrees/` (gitignored; auto-managed per iteration)

Note: Each iteration of `ralph.sh` runs in an isolated git worktree on a
`ralph/<iter-id>` branch, then fast-forward-merges back on success. Pass
`--no-isolate` or set `RALPH_AUTO_MERGE=0` to change this behavior.

To drive bare `bd create` beads through the full Bearings → Implement →
Verify → Commit structure, run with
`./ralph.sh --auto-promote=choo-choo-ralph` (or `=bug-fix`). Atomic beads
are auto-poured into a fresh molecule before Claude is invoked.

Explain next steps:

1. Use `/choo-choo-ralph:spec` to generate a spec from your plan
2. Review and approve features in the spec
3. Use `/choo-choo-ralph:pour` to create beads
4. Run `./ralph.sh` to start the autonomous loop
