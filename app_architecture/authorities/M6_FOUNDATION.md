# M6 Snapshot and Replay Foundation

`M6_FOUNDATION` — active authority for M6 execution.

This document defines bounded M6 scope so snapshot/replay work lands without
reopening frozen M1-M5 behavior.

## Start Point (Locked Baseline)

M6 starts from frozen M1-M5:

- M1-M3 parser/pipeline/screen/history/selection semantics are frozen.
- M4 input/control encode contracts are frozen.
- M5 runtime lifecycle invariants and mixed host-loop parity are frozen.

Current gap:

- no stable snapshot contract for host/diagnostic consumers.
- no explicit replay contract that binds runtime snapshots to deterministic
  validation flows.

## End Point (M6 Done)

M6 is done only when all are true:

- snapshot contract is explicit, host-neutral, and frozen.
- replay contract is explicit, deterministic, and frozen.
- runtime/model snapshot read surface is implemented and test-backed.
- replay tests prove snapshot/replay invariants without changing M1-M5 behavior.

## Scope (In)

- contract authority for snapshot payload contents and invariants.
- contract authority for replay stream framing and deterministic outcomes.
- host-neutral runtime/model read surfaces needed to capture snapshots.
- tests proving snapshot capture determinism and replay parity invariants.

## Non-Goals (M6)

- no persistence format standardization (JSON/binary file format is out of scope).
- no cross-version snapshot compatibility guarantees.
- no snapshot restore/mutate surface unless explicitly authorized by contract.
- no performance campaign work (M7).
- no host/platform transport, storage, or UI integration.

## Execution Gates (Ordered)

### M6-A: Contract Closure

- create snapshot/replay contract authority document.
- define snapshot fields and coordinate semantics (viewport/history/selection).
- define replay stream boundary rules (feed/apply boundaries, split-feed handling).
- define what is explicitly excluded from snapshot/replay guarantees.

Exit check:

- no ambiguity across `RUNTIME_API.md`, `MODEL_API.md`, and M6 authority.

### M6-B: Snapshot Surface

- add minimal runtime/model snapshot read surface matching M6-A contract.
- keep surface host-neutral and const/read-only by default.
- add docstrings aligned to contract.

Exit check:

- snapshot API is explicit and deterministic; no mutable escape hatches.

### M6-C: Replay Contract Evidence

- add replay/parity tests that exercise snapshot + replay invariants:
  - identical byte stream + apply boundaries => identical snapshots
  - split-feed chunking invariance
  - reset/clear boundary behavior as defined in M6-A contract
- validate runtime facade and direct pipeline/screen parity for covered cases.

Exit check:

- replay evidence demonstrates contract claims end-to-end.

### M6-D: Freeze and Handoff

- freeze M6 contracts and milestone state.
- publish M7 handoff queue.

Exit check:

- M6 marked done in milestone progress; active queue repointed to M7 planning.

## Stop Conditions

Stop and escalate if any occur:

- M6 requirements force semantic changes to frozen M1-M5 behavior.
- snapshot contract would require mutable access violating runtime/model boundaries.
- replay evidence reveals divergence rooted outside M6 scope (parser/screen core mismatch).

## Validation Baseline

Every M6 execution slice must pass:

- `zig build`
- `zig build test`
- `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`

## Docstring Rule (M6-Owned Stable Surfaces)

For files/symbols stabilized by M6:

- each owned file keeps top-level `//!` ownership header.
- each stable public symbol has `///` contract-aligned behavior docs.
