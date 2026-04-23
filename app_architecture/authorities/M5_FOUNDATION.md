# M5 Runtime Interface Foundation

`M5_FOUNDATION` — active authority for M5 execution.

This document bounds M5 with an explicit start point, end point, and ordered
execution gates so work does not drift.

## Start Point (Locked Baseline)

M5 starts from frozen M1-M4 behavior:

- M1-M3 parser/pipeline/screen/history/selection semantics are frozen.
- M4 input encoding contracts are frozen.
- `Engine` already exposes host-neutral methods for feed/apply/reset/screen,
  history/selection reads, and key/mouse encode entry points.

Known planning gap at M5 start:

- runtime-interface scope exists in milestone text, but lacks a single bounded
  authority defining M5 execution gates and stop conditions.

## End Point (M5 Done)

M5 is done only when all of the following are true:

- runtime interface scope is frozen in contracts with no ambiguous ownership.
- runtime method groups and lifecycle invariants are explicit and test-backed.
- runtime facade parity is proven for mixed host-loop usage patterns.
- all M5 work is complete without reopening frozen M1-M4 behavior.

## Execution Gates (Ordered)

### M5-A: Contract Closure

- define runtime lifecycle model (input feed, queueing, apply, state read).
- define allowed state mutations per runtime method family.
- define reset/clear/screen-reset interaction invariants in one place.
- update `RUNTIME_API.md` to be unambiguous for host embedding use.

Exit check:

- no conflicting language between milestone authority and runtime contract docs.

### M5-B: Interface Hardening

- align `src/runtime/engine.zig` surface to the M5 contract (no host/platform leakage).
- keep API host-neutral and deterministic.
- preserve const-read boundaries; no mutable escape hatches.

Exit check:

- runtime public API matches contract exactly; signatures and ownership are explicit.

### M5-C: Runtime Parity Matrix

- add parity tests covering mixed-operation host loops:
  - feed/apply/read cycles
  - clear/reset/resetScreen interaction paths
  - input encode calls interleaved with runtime state operations
- include split-feed and interruption cases where runtime ordering matters.

Exit check:

- parity/runtime tests prove runtime behavior is transparent to underlying pipeline/screen contracts.

### M5-D: Freeze and Handoff

- freeze M5 contracts and milestone state.
- replace active queue with M6 handoff scope.

Exit check:

- M5 marked done in milestone progress and queue is repointed to next milestone.

## Stop Conditions

Stop and escalate before continuing if any of these occur:

- M5 requirements would force semantic changes to frozen M1-M4 behavior.
- required runtime API change conflicts with frozen contract guarantees.
- parity tests indicate underlying parser/screen behavior mismatch unrelated to runtime interface scope.

## Non-Goals (M5)

- no snapshot/restore or replay contract expansion (M6 scope).
- no performance/memory campaign work (M7 scope).
- no host/platform integration code, renderer policy, or app lifecycle ownership.
- no compatibility shims, fallback paths, or duplicate APIs.

## Validation Baseline

Every M5 execution slice must pass:

- `zig build`
- `zig build test`
- `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`

## Docstring Rule (M5-Owned Stable Surfaces)

For stable M5 runtime API files and symbols:

- each owned file keeps a top-level `//!` ownership header.
- each stable public symbol keeps `///` docs aligned to contract behavior.
