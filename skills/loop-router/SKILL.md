---
name: loop-router
description: Routing rules, shared loop counter and human pause for the engineering crew orchestrator. Use whenever an agent returns a status other than DONE, or a test fails.
---

# Loop router

The orchestrator keeps ONE loop counter for the whole run in `.crew/runs/<slug>/loops.md` (a line per loop: number, route, who raised it, one-line reason).

## Routes

| # | Trigger | Goes to | Then resume from |
|---|---|---|---|
| 1 | Implementer says a test contradicts the design or itself | TDD expert | TDD expert, then implementer onward |
| 2 | Reviewer verdict: code problem | Implementer | Implementer, then refactorer, reviewer, tester |
| 3 | Reviewer verdict: design problem | Architect | Architect, then TDD expert onward |
| 4 | Architect or TDD expert finds a requirement gap | Domain expert | Domain expert (which asks the user if needed), then forward |
| 5 | Tester reports any failing test | Implementer | Implementer, refactorer, reviewer, tester |
| 6 | Verifier finds a mismatch with the requirements | The user, never an agent | The user decides |

Only a fully green tester run may reach the verifier.

## Counting

- Routes 1 to 5 each add one to the counter.
- Route 6 is a pause for the user and is NOT counted.
- Route 1 may happen once per run. A second bad-test claim pauses for the user.
- Small fix mode has no domain expert or architect. Routes 3 and 4 become a pause for the user.

## The pause

If the counter is already 3 and another loop is needed, stop and ask the user for approval. Show:

1. The conflict, quoting the agent's Route reason.
2. Who raised it and which round.
3. What each earlier loop tried (from loops.md).
4. Options: approve one more loop, change the requirement, fix it by hand, or abort.

Wait for the answer. Do not continue on your own.

## Route 6 detail

When the verifier flags a mismatch, show the user the requirement on one side and what the tester observed on the other. The verifier writes nothing to `docs/` or `architecture.md` until the mismatch is resolved.

## Re-run rule

A re-run agent reads its existing handoff file and updates only what changed. It must stay inside its word cap and bump its Round line.

## Re-approval (feature mode)

When route 3 or 4 re-runs the architect or domain expert after the user approved the design, `Approved` in `state.md` goes back to `no`. Show the user what changed and get approval again before the chain resumes. This is a pause for the user and is not counted as a loop.

## State

After every loop, update the Loops line in `state.md` and add the entry to `loops.md`, so a resumed run keeps the same count.

## Budget

The orchestrator stops and asks the user before the 25th agent run of a single run (counter `Agent-runs` in `state.md`), and when the request set `max-tokens=<N>` and the tokens reported in `usage.md` exceed it. This bounds cost even if every individual loop looks reasonable.
