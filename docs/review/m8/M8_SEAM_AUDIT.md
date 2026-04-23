# M8 Integration Seam Audit

Architect-owned seam audit for first-host readiness.

Scope baseline: frozen `M1-M7` contracts.

## Seam Classification

Status vocabulary:

- `ready`: seam contract is explicit and test-backed enough for host integration.
- `needs-hardening`: seam is usable but requires bounded clarification/evidence.
- `blocked`: seam has unresolved contract conflict that must be closed first.

| Seam | Primary Surface | Current Status | Rationale | Required Follow-Up |
| --- | --- | --- | --- | --- |
| Lifecycle | `Engine.init*`, `deinit`, `clear`, `reset`, `resetScreen` | `ready` | Lifecycle boundaries and mutation/read matrix are explicit in `RUNTIME_API.md` and M5 parity/conformance tests. | None for M8-A/B closure. |
| Input ingest | `feedByte`, `feedSlice`, `apply` | `ready` | Feed/apply two-phase contract, split-feed determinism, and queue semantics are frozen and replay-tested. | None for M8-A/B closure. |
| State read | `screen`, `queuedEventCount` | `ready` | Const read-only surfaces are explicit; no mutable escape hatch exists. | None for M8-A/B closure. |
| History/selection | `historyRowAt`, `historyCount`, `historyCapacity`, `selection*` | `ready` | Coordinate model, eviction invalidation, and runtime parity behavior are contract-backed and tested. | None for M8-A/B closure. |
| Control output | `encodeKey`, `encodeMouse` | `needs-hardening` | Keyboard encode contract is explicit and covered; mouse encode remains placeholder (empty output) and must be carried as explicit non-goal in readiness gates. | M8-C must include explicit host-readiness rule for placeholder mouse behavior (non-blocking, non-overclaimed). |
| Snapshot | `Engine.snapshot`, `model.EngineSnapshot` | `ready` | Snapshot is const/read-only and explicitly scoped as non-restore/non-transport; determinism evidence exists in M6. | None for M8-A/B closure. |

## Audit Findings

### F1: Host boundary is contract-strong for all runtime method families

`RUNTIME_API.md` defines lifecycle, mutation/read boundaries, and invariants with
sufficient precision for first-host integration.

Disposition: no contract gap found.

### F2: Mouse encode placeholder must stay explicit in readiness framing

`encodeMouse` is intentionally placeholder and deterministic. Host readiness must
not imply mouse-report completeness at M8.

Disposition: carry as explicit non-goal in M8-C readiness matrix.

### F3: No core platform-policy leakage detected in frozen API surfaces

Reviewed seams remain host-neutral and contract-owned by runtime/model layers.

Disposition: no blocking issue found.

## M8-B Exit Status

- Blocking conflicts: none.
- Seam audit verdict: pass with one bounded hardening item (`encodeMouse` framing).
- M8-B can close once M8-C gate matrix explicitly captures placeholder mouse behavior.
