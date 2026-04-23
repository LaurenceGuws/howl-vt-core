# M7 F2 Queue Growth Spec

Spec ID: `M7-F2-SPEC-001`

Target finding: `F2` from `M7_AUDIT.md`

Goal: make queue-growth behavior explicit, measurable, and reviewable under
`feed* -> apply` semantics without reopening frozen `M1-M6` behavior.

## Baseline Anchor

Primary baseline for this spec:

- `docs/review/m7/M7_BASELINE.md` (`M7-BL-003`)

Required harness command:

- `zig build m7-baseline`

## Problem Statement

Queue growth before `apply` is currently permitted by contract, but the project
lacked a concrete envelope and acceptance criteria for queue-depth pressure.

`F2` does not force bounded queue semantics immediately. It forces explicit
measurement and policy gates so future queue changes are deliberate.

## Allowed Change Surface

Primary files:

- `src/event/pipeline.zig`
- `src/event/bridge.zig`
- `src/runtime/engine.zig` (read-only metrics/reporting additions only)
- `tools/m7_baseline.zig`
- `src/test/relay.zig`
- `docs/review/m7/M7_BASELINE.md`

Policy/authority alignment files:

- `app_architecture/authorities/M7_FOUNDATION.md`
- `docs/review/m7/M7_MEASUREMENT_PROTOCOL.md`
- `docs/review/m7/M7_AUDIT.md`

## Explicit Non-Goals

- no semantic changes to `feed* -> apply` ownership model
- no renderer/host integration work
- no VT behavior expansion
- no scroll algorithm redesign (`F3`)
- no snapshot contract redesign (`D3`)

## Contract Invariants (Must Hold)

1. `feed*` remains non-mutating for visible screen state.
2. Queue event ordering and semantic outcomes remain deterministic.
3. Split-feed invariance remains true.
4. `clear`, `reset`, `resetScreen` behavior remains frozen.
5. History, selection, and snapshot semantics remain frozen.

## Required F2 Metrics

`F2` evidence must include:

- `median_max_queue_depth`
- `median_peak_live_bytes`
- existing latency/throughput/allocation metrics from `m7-baseline`

Required workloads:

- `queue_growth_ascii_chunked_64`
- `queue_growth_scroll_chunked_16`

## Acceptance Gates

Current `F2` policy phase accepts one of two outcomes:

### Outcome A: Policy-only closure (no queue algorithm changes)

Required:

1. queue-depth and peak-live metrics are published and stable enough for review
2. doctrine text explicitly documents queue-growth envelope assumptions
3. no regressions in existing `M7` latency/throughput baselines beyond protocol tolerance

### Outcome B: Queue-management implementation change

Required:

1. all Outcome A requirements
2. measurable reduction in at least one of:
   - `median_max_queue_depth` on required queue workloads
   - `median_peak_live_bytes` on required queue workloads
3. no major regressions:
   - `ascii_heavy` throughput regression must be <=3%
   - `mixed_interactive` median latency regression must be <=5%
4. full correctness gate pass (`zig build test`)

## Stop Conditions

Stop and escalate if any occur:

- queue mitigation requires mutating screen state during `feed*`
- queue mitigation changes event ordering semantics
- queue mitigation introduces hidden compatibility/fallback branches
- measurement variance prevents trustworthy queue-depth comparison

## Deliverable Shape

For each F2 slice:

1. one scoped commit for policy/implementation
2. one evidence update in `M7_BASELINE.md`
3. one architect review note stating pass/fail per outcome gates
