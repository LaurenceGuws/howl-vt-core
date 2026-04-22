# Architect Workflow

Purpose: drive project direction, break big goals into digestible milestones, and publish the largest execution cuts that remain reviewable.

## Role

Architect owns:
- project direction and milestone sequencing
- architecture and contract decisions
- decomposition of milestones into reviewable execution cuts
- queue authoring and acceptance/rejection

Engineer owns:
- implementation of architect-issued execution cuts
- evidence reporting only

Engineer must not own:
- planning, scoping, or reprioritization
- authority docs or architecture direction
- workflow changes
- symbol/interface design decisions not explicitly specified in ticket

## Architect Iteration Loop

1. Read current authorities, contracts, code, and tests.
2. Choose the next largest chunk of milestone work that stays reviewable.
3. Write queue tickets in `docs/engineer/ACTIVE_QUEUE.md`.
4. Each ticket must include:
   - target files
   - allowed change type
   - explicit non-goals
   - validation commands
   - stop conditions
5. Keep tickets large enough to sustain long execution, but bounded enough for strict review.
6. Review engineer report against diffs/tests/contracts.
7. Accept or reject with explicit corrective queue rewrite.
8. On acceptance, replace queue with the next large reviewable cut.

## Queue Discipline

- Queue is temporary and rewritten each loop.
- Queue is execution-only, never a historical ledger.
- Queue items are execution cuts, not thinking prompts.
- If a task needs analysis/design, it stays with architect and is not delegated.

## Acceptance Gate

Accept only when all are true:
- Scope strictly matches ticket boundaries.
- `zig build` and `zig build test` pass.
- Required grep checks pass.
- Claims match `git show --name-status`.
- No unauthorized doc/authority/workflow edits.

## Tracking Discipline

- `app_architecture/authorities/*`: architecture direction.
- `app_architecture/contracts/*`: behavioral/API contracts.
- `docs/architect/MILESTONE_PROGRESS.md`: milestone state only.
- `docs/engineer/ACTIVE_QUEUE.md`: current execution loop only.
- Commits + tests: implementation evidence.
