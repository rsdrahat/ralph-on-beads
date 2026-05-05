# Choo Choo Ralph

<p align="center">
  <img src="choo-choo-ralph.png" alt="Choo Choo Ralph" width="100%">
</p>

![License](https://img.shields.io/badge/license-MIT-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple)
![Status](https://img.shields.io/badge/status-experimental-orange)

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#what-you-get">What You Get</a> •
  <a href="#why-beads">Why Beads</a> •
  <a href="#documentation">Documentation</a>
</p>

<p align="center"><em>Relentless like a train. Persistent like Ralph Wiggum. Ships code while you sleep.</em></p>

> **🧪 Experimental** — This workflow is actively tested on real projects. Smaller, verified tasks trade higher Claude Code usage for more reliable outcomes. Your mileage may vary—I'd love feedback on what works and what doesn't.

> **🔱 Fork notice** — This is `rsdrahat/ralph-on-beads`, a fork of [`mj-meyer/choo-choo-ralph`](https://github.com/mj-meyer/choo-choo-ralph). Differences from upstream:
> - **Worktree-per-iteration isolation** — every iteration of `ralph.sh` runs Claude inside a fresh git worktree on a `ralph/<iter-id>` branch, then fast-forwards back on success. Concurrent Ralphs can't stomp each other's edits. ([details](#worktree-isolation))
> - **Auto-promote atomic beads into molecules** — `--auto-promote=choo-choo-ralph` (or `=bug-fix`) makes Ralph pour any atomic `bd create` bead into a structured molecule before invoking Claude. One canonical workflow for both spec-poured and bare beads. ([details](#auto-promote))
> - **Roadmap** — additional gastown-inspired enhancements (subagent-typed steps, parallel siblings, batch-then-bisect refinery merge queue, FIX_NEEDED handoff) are queued as `P3` issues in this fork's `.beads/`.

---

## What is Choo Choo Ralph?

A [Claude Code](https://claude.com/claude-code) plugin that turns your plans into autonomous, verified work—designed for teams, not just side projects.

Most Ralph implementations use GitHub Issues (latency), scattered markdown files (messy), or monolithic JSON (doesn't scale). Choo Choo Ralph uses [Beads](https://github.com/steveyegge/beads)—a git-native task tracker where every task has an ID, workflows have real dependencies, and everything syncs through git the way your team already works.

**The thesis**: Simple loop + structured workflows + persistent memory = autonomous coding that actually works.

---

## The Workflow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   1. Plan   │ ──▶ │  2. Spec    │ ──▶ │  3. Pour    │ ──▶ │  4. Ralph   │ ──▶ │ 5. Harvest  │
│    (you)    │     │  (you + AI) │     │    (AI)     │     │    (AI)     │     │ (you + AI)  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

1. **Plan** — Write what you want to build (this part is yours)
2. **Spec** — AI transforms it into structured tasks; you review
3. **Pour** — Tasks become beads with workflows and dependencies
4. **Ralph** — The loop runs autonomously until done
5. **Harvest** — Extract learnings into skills, docs, or CLAUDE.md

---

## What You Get

- **Verified, not vibes** — Health checks before implementing, tests after, browser verification when needed
- **Team-friendly** — Git-native sync, no API latency, works with how your team already collaborates
- **Traceable** — Bead IDs link commits to tasks, learnings to work. Full history of what happened where.
- **Structured phases** — Bearings → Implement → Verify → Commit (not just "do the thing")
- **Bounded context** — Each task carries its own history via [Beads](https://github.com/steveyegge/beads), no context window bloat
- **Compounding knowledge** — Agents capture learnings as they work; harvest them into skills and docs that make future sessions smarter
- **Customizable workflows** — Formulas and scripts are yours to modify, not hardcoded decisions

---

## Quick Start

<details>
<summary>⚠️ <strong>Safety Warning</strong> — Read before running</summary>

Ralph runs Claude with `--dangerously-skip-permissions`, which allows it to execute commands without confirmation. This is powerful but risky.

**We strongly recommend:**
- Run in a **Docker container** or **VM**
- Use a machine that doesn't have your life's work on it
- Start with small, low-risk tasks until you trust the setup
- Review the formulas and scripts before running

By using this project, you accept full responsibility for any consequences.

</details>

**Prerequisites:** [Claude Code](https://claude.com/claude-code), [Beads](https://github.com/steveyegge/beads) (`bd` command), [jq](https://jqlang.github.io/jq/), git ≥ 2.5 (for worktree support)

```bash
# Install plugin (this fork)
/plugin marketplace add rsdrahat/ralph-on-beads
/plugin install choo-choo-ralph@choo-choo-ralph

# Set up project
/choo-choo-ralph:install

# Generate spec from your plan
/choo-choo-ralph:spec plans/my-feature.md

# Review the spec, then pour into beads
/choo-choo-ralph:pour

# Start the loop (each iteration runs in an isolated worktree by default)
./ralph.sh

# RECOMMENDED for bare `bd create` beads: auto-promote to the full molecule
# structure before invoking Claude, so every bead gets Bearings → Implement
# → Verify → Commit phases. Works for both ralph-assigned molecules and
# bare beads — molecules pass through unchanged; atomic beads get poured.
./ralph.sh --auto-promote=choo-choo-ralph
# Or with the lighter formula:
./ralph.sh --auto-promote=bug-fix

# Drive bare beads without promotion (atomic execution; less rigor)
./ralph.sh --assignee=any

# Drive a custom queue (e.g., your own assignee)
./ralph.sh --assignee=mybacklog --auto-promote=choo-choo-ralph

# Disable isolation and run claude in the main worktree (legacy behavior)
./ralph.sh --no-isolate

# Leave merge-back to a refinery (when issue ralph-on-beads-k03 lands)
RALPH_AUTO_MERGE=0 ./ralph.sh
```

For the complete workflow, see [docs/workflow.md](docs/workflow.md). For the new isolation model, see [Worktree isolation](#worktree-isolation) below.

---

## The Problem

Most autonomous coding setups fall into two traps:

1. **Too simple** — Run Claude in a loop, hope for the best, watch it spiral when something breaks
2. **Too complex** — Build elaborate orchestration that's harder to debug than the code it writes

And most Ralph implementations work fine for side projects but break down for teams. GitHub Issues introduce API latency. Scattered markdown files don't scale. Big JSON files or progress trackers get clunky when multiple people are involved.

Choo Choo Ralph is designed for real teams. The outer loop is dead simple. The workflow inside each task is structured and verified. Every task has an ID that traces through to commits and learnings. And everything syncs through git—no extra infrastructure.

---

## Why Beads?

Choo Choo Ralph requires [Beads](https://github.com/steveyegge/beads). Here's why it's worth adding to your stack:

**Solves the team problem** — Beads syncs via git, not APIs. No rate limits, no latency, no network errors when agents update tasks. Works with how your team already collaborates.

**Structured workflows, not checklists** — Molecules define multi-step workflows with real dependencies. Agents follow the structure instead of winging it.

**Traceability** — Every bead has an ID. Link commits to tasks, learnings to specific work. When something goes wrong (or right), you know where it came from.

**Bounded context** — Each bead carries its own history. Context stays contained instead of growing unbounded across sessions.

**Clean abstraction** — All the organizational work is behind `bd` commands. No cluttering your codebase with planning files.

> [!IMPORTANT]
> Beads is a **hard requirement**. The plugin's pour and formula system depends on Beads' molecule feature to create multi-step workflows.

---

## Worktree isolation

This fork wraps every iteration of `ralph.sh` (and `ralph-once.sh`) in a per-iteration git worktree so that concurrent Ralphs cannot stomp each other's edits — file-level isolation, in addition to the bead-claim-level isolation that upstream already provides.

**What happens per iteration:**

1. The script captures your current branch as `BASE_BRANCH`.
2. It creates a fresh worktree at `.ralph-worktrees/<iter-id>/` on a new branch `ralph/<iter-id>` based on `HEAD`.
3. It symlinks the repo's `.beads/` into the worktree so `bd` commands inside Claude write to one shared dolt db.
4. Claude runs with cwd inside the worktree. Commits land on `ralph/<iter-id>`.
5. After Claude exits, the script:
   - Detects uncommitted changes → leaves the worktree for inspection.
   - Detects no new commits → prunes worktree and branch.
   - Otherwise → tries `git merge --ff-only ralph/<iter-id>` into `BASE_BRANCH`. On success, removes worktree + branch. On failure (parallel Ralph already advanced `BASE_BRANCH`), leaves the branch + worktree for manual merge or for the future refinery (`ralph-on-beads-k03`).

**Flags & env:**

| Flag / env | Effect |
|---|---|
| `--no-isolate` | Skip worktrees entirely. Claude runs in the main worktree, like upstream. |
| `--assignee=<name>` / `RALPH_ASSIGNEE=<name>` | Filter the ready queue by this assignee (default: `ralph`). Use `any` to drop the filter — picks from all ready beads, including bare ones created via `bd create`. |
| `--auto-promote=<formula>` / `RALPH_AUTO_PROMOTE=<formula>` | Auto-pour atomic beads into a structured molecule before invoking Claude. See [Auto-promote](#auto-promote). |
| `RALPH_AUTO_MERGE=0` | Skip the fast-forward merge-back. Branches accumulate for refinery. |
| `RALPH_WORKTREE_ROOT=...` | Override the worktree directory (default: `<repo>/.ralph-worktrees/`). |

---

## Auto-promote

Ralph's molecule formula gives you a structured Bearings → Implement → Verify → Commit pipeline with verification gates and learning capture. Upstream that requires running `/choo-choo-ralph:spec` and `/choo-choo-ralph:pour` ahead of time. This fork lets you skip the spec/pour ceremony for one-off work: any **atomic** bead (created with `bd create`, no children) gets auto-poured into a fresh molecule before Claude is invoked.

```bash
# Workflow A: bare beads, full structure
bd create --title="Cache the user lookup" --description="In src/users/lookup.ts, add an LRU cache around fetchUserById with a 60s TTL. Add a unit test." --priority=2 --assignee=ralph
./ralph.sh --auto-promote=choo-choo-ralph
# Ralph picks the bead → sees it's atomic → pours a 5-issue molecule
# (root + bearings + implement + verify + commit) → closes the original
# with reason "auto-promoted to molecule …" → Claude runs the orchestrator
# loop on the new molecule.

# Workflow B: still works for already-poured molecules
/choo-choo-ralph:spec plans/big-feature.md
/choo-choo-ralph:pour
./ralph.sh --auto-promote=choo-choo-ralph
# Existing molecules pass through unchanged; only atomic beads get promoted.
```

**Choosing a formula:**
- `choo-choo-ralph` — full structure (bearings + implement + verify + commit). Best for substantive changes.
- `bug-fix` — lighter formula for targeted fixes. Use when you want some structure but not the full pipeline.
- Any other formula listed by `bd formula list` is fair game.

**Mechanics:** when bash detects an atomic bead, it shells out to `ralph-promote.sh <bead-id> <formula> <assignee>`, which runs `bd mol pour` with the bead's title and description as the `title` / `task` template variables. The original bead is closed with a reason linking to the new molecule's root id, so the audit trail stays intact. Existing molecule beads (any bead with children) skip promotion and pass straight through.

**Tradeoff:** every atomic bead becomes a 5-issue molecule and a multi-phase Claude run. Worth it for substantive work; overkill for "rename this variable" type fixes — for those, just run without `--auto-promote`.

**Git ≥ 2.5 required.** The install command adds `.ralph-worktrees/` to your `.gitignore`.

If a worktree is left behind after a failed merge, you can inspect it normally:

```bash
cd .ralph-worktrees/<iter-id>
git log
git diff <base-branch>
# When you're done:
cd -
git worktree remove .ralph-worktrees/<iter-id>
git branch -D ralph/<iter-id>
```

---

## Compounding Knowledge

Every task teaches your agents something. The question is: do you capture it?

```
Iteration 1: Write code → Discover patterns → Capture as comments
Iteration 2: Write code → Learn from previous → Capture new insights
Iteration 3: Harvest learnings → Create skills/docs → Future agents are smarter
Iteration 4: New agent benefits from skills → Works faster → Discovers more
...repeat...
```

**The flywheel:**
1. **Code** — Each task produces working, tested, committed code
2. **Memory** — Agents capture gaps and learnings as comments on beads
3. **Harvest** — You extract valuable patterns into skills, CLAUDE.md, docs
4. **Compound** — Future iterations benefit from accumulated knowledge
5. **Repeat** — The system gets smarter with every session

Run `/choo-choo-ralph:harvest` after a session to gather learnings and propose documentation artifacts.

---

## Customization

When you run `/choo-choo-ralph:install`, you get local copies of everything—shell scripts, formulas, and config. These are yours to modify.

This is intentional. We didn't want a CLI with hardcoded decisions. We wanted best practices as a starting point that you can adapt per-project. One project might need tweaked prompts; another works fine with defaults.

**What you can customize:**
- **Shell scripts** (`ralph.sh`, `ralph-once.sh`) — Loop behavior, task limits, output formatting
- **Formulas** (`.beads/formulas/`) — Workflow steps, prompts, verification requirements
- **Specs** (`.choo-choo-ralph/`) — Your planning and review process

For details, see [docs/customization.md](docs/customization.md).

---

## Why "Choo Choo Ralph"?

**Choo Choo** — Like a train with carts. Each cart is a containerized block of work—self-contained, carrying its own context and history. The train keeps moving forward, cart after cart, toward your destination.

**Ralph** — Named after the [Ralph Wiggum technique](https://ghuntley.com/ralph/): run an AI in a loop until it's done. Simple, relentless, surprisingly effective. Ralph makes mistakes, gets confused, but never stops trying.

---

## Documentation

- [Complete Workflow Guide](docs/workflow.md) — Step-by-step from planning to harvest
- [Spec Format Reference](docs/spec-format.md) — XML structure and review process
- [Commands Reference](docs/commands.md) — All options and arguments
- [Customization Guide](docs/customization.md) — Adapting Ralph to your project
- [Formula Reference](docs/formulas.md) — Creating and modifying workflow formulas
- [Troubleshooting](docs/troubleshooting.md) — Error handling and debugging

---

## Further Reading

**Ralph Technique**
- [ghuntley.com/ralph](https://ghuntley.com/ralph/) — The original Ralph philosophy
- [Matt Pocock's Ralph Guide](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum) — Practical tips

**Anthropic Research**
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Two-agent pattern, verification

**Tools**
- [Beads](https://github.com/steveyegge/beads) — Git-backed issue tracker with molecules
- [dev-browser](https://github.com/SawyerHood/dev-browser) — Browser automation for Claude Code
- [Claude Code](https://claude.com/claude-code) — Anthropic's CLI for agentic coding

## License

MIT
