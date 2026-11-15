# Engineering Crew

A repo-agnostic crew of Claude Code agents. One global slash command runs the pipeline in any repo, on its own git branch, with enforced per-agent boundaries.

## Layout

```
agents/      eight subagents               -> ~/.claude/agents/
skills/      handoff-template, preflight, loop-router  -> ~/.claude/skills/
commands/    orchestrate.md                -> ~/.claude/commands/
scripts/     crew.sh, boundary.py          -> ~/.claude/crew/   (plus tests and a validator, not installed)
security/    settings examples to merge by hand
sample-repo/ a tiny repo for the first trial (./setup.sh copies it outside this folder)
templates/   starter architecture.md and coding-style.md for a FastAPI repo (copy, then edit)
install.sh   copies everything into ~/.claude (backs up files it replaces)
```

## Install

```
./install.sh
```

Then merge `security/settings.deny-ask.json` into `~/.claude/settings.json`. Per repo, merge an edited copy of `security/settings.allow.example.json` into `.claude/settings.json`; `security/settings.allow-source-edits.json` is an opt-in that lets the crew edit files without prompts (see Safety). Restart Claude Code and check the rules with `/permissions`.

Verify the install with the tests (no Claude needed):

```
scripts/test-crew.sh            # preflight, setup, lock, resume, handoff checks (42 cases)
python3 scripts/test-boundary.py   # per-agent read and write boundaries (78 cases)
scripts/test-integration.sh     # dry run of a whole fix pipeline with simulated agents (27 checks)
python3 scripts/validate-frontmatter.py   # strict YAML check, needs PyYAML
```

## Required in every repo (you write these, and commit them)

- `architecture.md` at the repo root.
- `coding-style.md` at the repo root with a `## Commands` section. Only `test:` is required.

```
## Commands
test: pytest -q
lint: ruff check .
typecheck: mypy .
```

Optional: `.crew-test-paths` at the repo root, one regex per line, to say what counts as a test file for your layout. The default covers `tests/`, `test_*.py`, `*_test.*`, `*.test.*`, `*.spec.*`, `conftest.py` and common JVM and .NET names.

## Usage

```
/orchestrate feature: users can import coupons from a CSV
/orchestrate fix: coupon expiry uses UTC instead of local time
/orchestrate resume bulk-coupon-import-20261114
```

Optional budget: add `max-tokens=2000000` to the request. A run also pauses before its 25th agent run.

Feature: domain-expert, architect, your approval, tdd-expert, implementer, refactorer, reviewer, tester, verifier.
Fix: tdd-expert, implementer, refactorer, reviewer, tester, verifier.

## Safety model

- Preflight (`crew.sh`) is a hard stop: required files, a clean tree, no unignored secret-like files anywhere in the tree, a free branch name, no other run holding the lock.
- The crew works on its own branch `crew/<slug>` and never commits, pushes, resets, cleans or deletes. Committing is yours. To abandon a run: `crew.sh abort-help <slug>` prints the commands for you to run.
- Run files live in `.crew/runs/<slug>/`. A `.gitignore` inside `.crew/` ignores the whole folder (itself included), so nothing in `.git` and no tracked file is touched. A rollback patch is saved after each code-writing stage, and a tree hash lets `resume` warn if you edited files in between.
- `boundary.py` runs as a PreToolUse hook inside each agent and blocks reads and writes outside that agent's role (for example, the implementer cannot edit tests or read the domain file; the tester cannot read the requirements). It fails closed.
- Every agent has a tool allowlist (no web or MCP tools), a turn limit and `omitClaudeMd: true`, so repo `CLAUDE.md` files do not load into the crew's context.
- Repo files and handoffs are treated as data, never instructions. A test-first exemption needs your approval.
- The reviewer runs on Opus, a different tier from the implementer, with an adversarial checklist.
- Permission edits: with `settings.allow-source-edits.json`, the crew edits any repo file without prompts. The boundary hook still limits each agent to its role, and the deny rules still protect secrets, `.github/` and `.claude/` (these prompt). Skip that file if you prefer approving edits by hand.

## Models, turn limits, caps (starting defaults, tune after real runs)

| Agent | Model | maxTurns | Handoff cap |
|---|---|---|---|
| domain-expert | opus | 30 | 600 words |
| architect | opus | 30 | 600 |
| tdd-expert | sonnet | 40 | 400 |
| implementer | sonnet | 60 | 250 |
| refactorer | sonnet | 40 | 200 |
| reviewer | opus | 30 | 300 |
| tester | sonnet | 30 | 200 |
| verifier | sonnet | 30 | 500 |

## What has and has not been verified

Verified by tests here: all `crew.sh` behavior, including worktrees, nested secret files, locks, resume and handoff validation; all boundary rules; strict YAML of every agent, skill and command file. Verified against the Claude Code docs: frontmatter fields (`hooks`, `omitClaudeMd`, `maxTurns`, `skills`), hook exit code 2 blocking a call, `Edit` rules covering Write, path-pattern syntax.

Not verified, because it needs a live Claude Code session:

- A full end-to-end run. Use `sample-repo/` for the first trial.
- That your Claude Code version runs frontmatter hooks inside subagents, and supports `omitClaudeMd` (the docs say v2.1.271 or later) and SendMessage resume. If SendMessage is missing the orchestrator falls back to fresh runs, which cost more tokens.
- Whether `usage.md` gets token figures. It records `not reported` otherwise.

## Known limits

- If your Claude Code sandbox blocks writes inside `.git`, preflight stops with one clear message, because the crew needs git to create its branch and track new files. Allow `.git` writes for the project, or run the crew outside the sandbox. The crew never changes sandbox settings itself.
- Bash is only best effort. The hook blocks any shell command that mentions `.crew`, and write-like commands for the reviewer and tester, but a determined command can get around it. A `Read` deny does not stop `cat .env` either. For real enforcement turn on Claude Code sandboxing.
- Interactive Claude Code starts subagents in the background by default. The orchestrator waits for each completion notice. To make them run inline, set `CLAUDE_CODE_FORK_SUBAGENT` to `0` in the settings `env` block.
- Subagents cannot talk to you mid-run. Questions come back as NEEDS_USER and the orchestrator resumes the same agent.
- The reviewer also reads `coding-style.md` and `03-tests.md`, and the tester reads source and `git diff HEAD`. Both are needed for their jobs.
- Shared blind spots remain possible: all agents are Claude models. The Opus reviewer and the adversarial checklist reduce this but do not remove it.
