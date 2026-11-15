---
name: preflight
description: "What the crew preflight checks and why. The checks themselves run in ~/.claude/crew/crew.sh, so use this to explain or extend them."
---

# Preflight

The orchestrator never improvises these checks. It runs `~/.claude/crew/crew.sh preflight <slug>`, which collects every problem and prints one message, or `PREFLIGHT OK`. This page documents what it covers. Change the script, and its tests in `scripts/test-crew.sh`, when you change a rule.

## Required repo inputs (you write these)

| File at the repo root | Needed by | Rule |
|---|---|---|
| `architecture.md` | domain-expert, architect, verifier | Exists and is non-empty |
| `coding-style.md` | tdd-expert, implementer, refactorer, reviewer | Exists, is non-empty, and has a `## Commands` section with a `test:` line |

```
## Commands
test: pytest -q
lint: ruff check .
typecheck: mypy .
security: bandit -r src
```

Only `test:` is required. Agents run only the commands listed here and never invent others.

## Git checks

1. Inside a git repository with at least one commit.
2. Working tree clean. The message tells you to commit `architecture.md` and `coding-style.md` first if they are among the dirty paths.
3. No unignored secret-like files anywhere in the tree (`.env*`, `*.pem`, `*.key`; `.example`, `.sample` and `.template` files are fine). Otherwise they would leak into diffs and checkpoint patches.
4. The branch `crew/<slug>` does not exist yet.
5. No other run holds `.crew/lock`.
6. Git can create files inside its own directory. Some sandboxes forbid it, and the crew needs it for the branch and for tracking new files.

For `--resume` the clean-tree and branch-exists checks are replaced by: the current branch must be `crew/<slug>`, and a WARN is printed if the working tree changed since the last agent finished.

## Local ignore

`.crew/` gets its own `.gitignore` containing `*`, which ignores the whole folder including that file. Nothing inside `.git` is written and your tracked `.gitignore` is never edited, so the run's diff stays clean and it works in worktrees and sandboxes.

## Setup

`crew.sh setup` records the current branch and commit, creates `crew/<slug>`, the run folder `.crew/runs/<slug>/` with `00-task.md`, `state.md`, `loops.md` and `usage.md`, and the lock.
