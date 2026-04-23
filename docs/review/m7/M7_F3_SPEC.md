# M7 F3 Scroll Path Spec

Spec ID: `M7-F3-SPEC-001`

Target finding: `F3` from `M7_AUDIT.md`

Goal: reduce scroll-path cost under history-producing workloads while preserving
frozen semantics and using `M7-BL-004` as upstream queue-stabilized baseline.

## Baseline Anchor

Comparison baseline for this spec:

- `docs/review/m7/M7_BASELINE.md` (`M7-BL-004`)

Required harness command:

- `zig build m7-baseline`

Primary target workloads:

- `scroll_heavy_history0`
- `scroll_heavy_history1000`
- `queue_growth_scroll_chunked_16`

## Problem Statement

Current bottom-row scroll behavior performs full visible-buffer movement each
scroll step. This is deterministic and simple, but costly at sustained scroll
volume.

`F3` allows internal data-layout/algorithm work to reduce this cost, provided
observable behavior remains unchanged.

## Allowed Change Surface

Primary files:

- `src/screen/state.zig`
- `src/runtime/engine.zig` (only if required for safe access adaptation)
- `src/model/snapshot.zig` (only if needed to preserve snapshot parity under
  internal scroll representation changes)
- `src/test/relay.zig`
- `tools/m7_baseline.zig`
- `docs/review/m7/M7_BASELINE.md`

Secondary contract files (only if wording clarification is needed):

- `app_architecture/contracts/SEMANTIC_SCREEN.md`
- `app_architecture/contracts/SNAPSHOT_REPLAY.md`

## Explicit Non-Goals

- no VT semantic expansion
- no change to `feed* -> apply` contract
- no queue-policy redesign (`F2` scope)
- no host/platform integration work
- no compatibility/fallback branch introduction

## Contract Invariants (Must Hold)

1. Visible screen content after each `apply` is identical for equivalent input.
2. Cursor position and wrap/mode behavior are unchanged.
3. History capture order and recency indexing are unchanged.
4. Selection invalidation behavior remains unchanged.
5. Snapshot observable content and ordering remain unchanged.
6. Split-feed invariance remains unchanged.

## Required Evidence

Every F3 implementation slice must provide:

1. `zig build m7-baseline` full output
2. comparison table vs `M7-BL-004`
3. `zig build test` pass
4. parity statement covering visible cells, cursor, history, and snapshot

## Acceptance Gates

All gates required unless explicitly waived by architect review note.

1. `scroll_heavy_history0` median latency improvement >= `10%`.
2. `scroll_heavy_history1000` median latency improvement >= `10%`.
3. `queue_growth_scroll_chunked_16` median latency improvement >= `8%`.
4. No major regressions:
   - `ascii_heavy` throughput regression <= `3%`
   - `mixed_interactive` median latency regression <= `5%`
5. Correctness gate: full `zig build test` pass.

## Stop Conditions

Stop and escalate if any occur:

- optimization requires changing visible output semantics
- optimization breaks history recency/index semantics
- snapshot parity cannot be preserved without contract break
- measured improvement is noise-level only and cannot clear gate thresholds

## Deliverable Shape

Expected sequence for F3:

1. one or more implementation commits, each keeping tree buildable
2. one evidence update commit in `M7_BASELINE.md`
3. one architect review commit with gate pass/fail
