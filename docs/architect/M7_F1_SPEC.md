# M7 F1 Optimization Spec

Spec ID: `M7-F1-SPEC-001`

Target finding: `F1` from `M7_AUDIT.md`

Goal: reduce allocation pressure caused by bridge text ownership while
preserving frozen `M1-M6` behavior and two-phase `feed* -> apply` semantics.

## Baseline Anchor

All acceptance comparisons for this spec use baseline `M7-BL-001`:

- `docs/architect/M7_BASELINE.md`

Required harness command:

- `zig build m7-baseline`

## Problem Statement

Current bridge behavior duplicates every ASCII slice into owned memory before
queueing. This drives high alloc count and alloc bytes on text-heavy and
scroll-heavy runtime workloads.

This spec permits internal ownership redesign to reduce allocator traffic, but
does not permit behavioral shortcuts.

## Allowed Change Surface

Primary allowed files:

- `src/event/bridge.zig`
- `src/event/pipeline.zig`
- `src/parser/parser.zig` (only if required for ownership-safe handoff)
- `src/test/relay.zig`
- `tools/m7_baseline.zig`
- `docs/architect/M7_BASELINE.md`

Secondary allowed files (only if required for contract documentation alignment):

- `app_architecture/contracts/RUNTIME_API.md`
- `app_architecture/contracts/SNAPSHOT_REPLAY.md`

## Explicit Non-Goals

- no VT semantic expansion
- no runtime API signature changes
- no host/platform integration changes
- no queue-bounding policy changes (that is `F2`)
- no scroll algorithm redesign (that is `F3`)
- no snapshot contract mutation (that is `D3`, measured separately)

## Contract Invariants (Must Hold)

1. `feed*` does not mutate visible screen state; `apply` remains the mutating step.
2. Event ordering and semantic outcome are deterministic and unchanged.
3. Split-feed chunking invariance remains true.
4. `clear`, `reset`, and `resetScreen` semantics remain frozen.
5. History and selection behavior remain frozen.
6. Snapshot parity and capture semantics remain frozen.

Any proposal that violates these invariants is rejected, even if faster.

## Required Evidence

For each candidate change, produce:

1. full `zig build m7-baseline` output
2. updated comparison table vs `M7-BL-001`
3. parity/correctness test results (`zig build test`)
4. explicit statement of which allocations were removed or reduced

## Acceptance Gates

All gates are required unless architect explicitly waives one in writing.

1. Allocation reduction gate:
   `ascii_heavy` median alloc count must decrease by at least `25%`.
2. Allocation bytes gate:
   `ascii_heavy` median alloc bytes must decrease by at least `20%`.
3. Stability gate:
   `mixed_interactive` median latency must not regress by more than `5%`.
4. Throughput gate:
   `ascii_heavy` throughput must not regress by more than `3%`.
5. Correctness gate:
   `zig build test` remains fully green.

## Stop Conditions

Stop and escalate if any occur:

- reduction requires mutating screen state during `feed*`
- reduction requires changing event semantic meaning/order
- reduction depends on hidden fallback paths or compatibility branches
- baseline variance exceeds protocol threshold and blocks trustworthy comparison

## Deliverable Shape

When this spec is executed, expected artifacts are:

1. one implementation commit for F1 code + tests
2. one evidence commit updating `M7_BASELINE.md` with post-change run
3. one short architect review note confirming gate pass/fail
