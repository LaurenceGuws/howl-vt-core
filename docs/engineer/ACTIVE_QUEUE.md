# Howl Terminal Active Queue

Execution-only queue for the current engineer loop.

## Ownership

- Architect writes and replaces this file every loop.
- Engineer executes only listed tickets.
- Engineer does not redesign scope during execution.

## Scope Anchor

- Milestone authority: `app_architecture/authorities/MILESTONE.md`
- M5 authority: `app_architecture/authorities/M5_FOUNDATION.md`
- Runtime contract: `app_architecture/contracts/RUNTIME_API.md`
- Architect workflow: `docs/architect/WORKFLOW.md`

## Current Loop

**Status:** M4 frozen. M5 active.

M1-M4 are frozen. Do not reopen parser/screen/history/selection/input behavior
unless an M5 parity test exposes a direct runtime-related regression.

## M5 Execution Order (Do Not Reorder)

1. **M5-A: Contract Closure**
   - Align runtime lifecycle + mutation-boundary language across authorities/contracts.
   - Exit check: no ambiguity in reset/clear/resetScreen/apply behavior.

2. **M5-B: Interface Hardening**
   - Align `src/runtime/engine.zig` public API to contract text.
   - Exit check: host-neutral, deterministic surface; no mutable escapes.

3. **M5-C: Runtime Parity Matrix**
   - Add mixed host-loop parity/runtime tests.
   - Exit check: direct pipeline/screen and runtime facade behavior match.

4. **M5-D: Freeze Handoff**
   - Update authority/progress docs and repoint queue to M6 planning.
   - Exit check: M5 marked done with closeout evidence.

## Guardrails

- No compatibility/fallback/workaround/shim paths.
- No host/platform/renderer lifecycle imports in runtime/model/event/screen lanes.
- No scope expansion into M6+ during M5 execution.
