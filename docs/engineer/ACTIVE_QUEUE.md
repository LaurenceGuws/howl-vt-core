# Howl Terminal Active Queue

Execution-only queue for the current engineer loop.

## Ownership

- Architect writes and replaces this file every loop.
- Engineer executes only listed tickets.
- Engineer does not redesign scope during execution.

## Scope Anchor

- Milestone authority: `app_architecture/authorities/MILESTONE.md`
- M6 authority: `app_architecture/authorities/M6_FOUNDATION.md`
- Runtime contract: `app_architecture/contracts/RUNTIME_API.md`
- Model contract: `app_architecture/contracts/MODEL_API.md`
- Architect workflow: `docs/architect/WORKFLOW.md`

## Current Loop

**Status:** M5 frozen. Execute M6-A.

M1-M5 are frozen. Do not reopen parser/screen/history/selection/input/runtime
semantics unless an M6 test exposes a direct regression.

## M6-A Execution Order (Do Not Reorder)

### M6-A1: Snapshot/Replay Contract Authority

- Target files:
  - `app_architecture/contracts/SNAPSHOT_REPLAY.md` (new)
  - `app_architecture/contracts/RUNTIME_API.md`
  - `app_architecture/contracts/MODEL_API.md`
- Allowed change type: contract clarification only (no code changes).
- Required output:
  - define snapshot payload scope and deterministic invariants.
  - define replay stream framing (feed/apply boundaries, split-feed behavior).
  - define explicit non-goals and breakage rules.
- Non-goals:
  - no runtime/model API signature changes in this ticket.
  - no test/code updates.
- Stop conditions:
  - if contract closure requires changing frozen M1-M5 semantics, stop and report exact conflict.

### M6-A2: Snapshot Surface Baseline (Code + Tests)

- Target files:
  - `src/model.zig`
  - `src/model/types.zig` and/or `src/model/snapshot.zig` (new if needed)
  - `src/runtime/engine.zig`
  - `src/test/relay.zig`
- Allowed change type: additive snapshot read surface and tests only.
- Required output:
  - implement minimal const/read-only snapshot API aligned to M6-A1 contract.
  - include deterministic snapshot parity tests for direct vs runtime flows.
  - include at least one split-feed replay equivalence snapshot test.
- Non-goals:
  - no snapshot restore/mutation API.
  - no persistence/file format code.
  - no host/platform integration code.
- Stop conditions:
  - if snapshot API requires mutable escape hatch or semantic mutation of frozen behavior, stop and report.

### M6-A3: M6-A Closeout + Queue Advance

- Target files:
  - `docs/architect/MILESTONE_PROGRESS.md`
  - `docs/engineer/ACTIVE_QUEUE.md`
  - `app_architecture/authorities/MILESTONE.md` (M6-A checklist mark only)
- Allowed change type: status and queue handoff update only.
- Required output:
  - mark M6-A complete in progress notes.
  - mark `M6-A` checklist item as done.
  - replace queue with M6-B starter tickets.
- Non-goals:
  - no code/contract changes.

## Engineer Report Format

- `#DONE` ticket IDs
- `#OUTSTANDING` ticket IDs
- commit hash + subject
- validation results
- files changed

## Mandatory Validation Per Ticket

- `zig build`
- `zig build test`
- `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`

## Guardrails

- No compatibility/fallback/workaround/shim paths.
- No host/platform/renderer lifecycle imports in runtime/model/event/screen lanes.
- No scope expansion into M6-B/M6-C/M6-D during M6-A execution.
