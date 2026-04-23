# Howl Terminal Active Queue

Execution-only queue for the current engineer loop.

## Ownership

- Architect writes and replaces this file every loop.
- Engineer executes only listed tickets.
- Engineer does not redesign scope during execution.

## Scope Anchor

- Milestone authority: `app_architecture/authorities/MILESTONE.md`
- M7 authority: `app_architecture/authorities/M7_FOUNDATION.md`
- Runtime contract: `app_architecture/contracts/RUNTIME_API.md`
- Model contract: `app_architecture/contracts/MODEL_API.md`
- Architect workflow: `docs/architect/WORKFLOW.md`

## Current Loop

**Status:** M6 complete and frozen. Execute M7 scope planning.

M1-M6 are frozen. Do not reopen earlier milestone semantics unless a current
milestone test exposes a direct regression rooted in earlier work.

M6 completion summary:
- SNAPSHOT_REPLAY.md contract authority published (payload scope, replay framing, determinism, non-goals).
- Snapshot API hardened: src/model/snapshot.zig + comprehensive docstrings.
- Replay evidence matrix validates determinism, parity, and reset/clear boundaries (10 tests).
- 432/432 tests pass; no mutable escape hatches; split-feed invariant holds.

## M7 Planning Phase (Scope Definition Only)

### M7-A: Performance Audit and Bounded Allocation Strategy

- Target files:
  - `app_architecture/authorities/M7_FOUNDATION.md` (new)
  - `app_architecture/contracts/RUNTIME_API.md` (memory bounds reference)
- Allowed change type: authority document creation and planning notes only.
- Required output:
  - define M7 scope: performance audit, bounded allocation enforcement, hot-path analysis.
  - establish allocation discipline policy (allocator ownership, lifetime guarantees).
  - document performance baseline targets (latency percentiles, throughput, memory caps).
  - define explicit non-goals (optimization beyond policy, streaming/incremental design, runtime tuning).
- Non-goals:
  - no code changes.
  - no implementation work.
  - no performance optimization (deferred to M7-B implementation phase).
- Stop conditions:
  - if M7 scope conflicts with M1-M6 frozen contracts, stop and report exact conflict.

### M7-B: Memory Discipline Baseline (Planning Queue Advance)

- Target files:
  - `docs/architect/MILESTONE_PROGRESS.md` (M7-A notes)
  - `docs/engineer/ACTIVE_QUEUE.md` (replace with M7-B implementation tickets)
  - `app_architecture/authorities/MILESTONE.md` (M7-A checklist mark)
- Allowed change type: status update and implementation queue definition only.
- Required output:
  - mark M7-A planning complete.
  - publish M7-B implementation queue with bounded allocation audit tickets.
- Non-goals:
  - no code changes.
  - no M7-B implementation yet.

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
- No scope expansion into M7-B during M7-A planning.
