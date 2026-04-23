# Howl Terminal Milestone Authority

This document defines high-level milestones from scaffold to long-term target.
It is intentionally non-implementation-detailed.

## Milestone Ladder

| ID | Name | Outcome |
| --- | --- | --- |
| `M0` | Repo Scaffold | Package compiles, tests run, docs/workflow baseline exists. |
| `M1` | Parser-Screen Foundation | Parser/event/screen pipeline is deterministic and minimal. |
| `M2` | Terminal State Breadth | Core screen semantics: wrap, scroll, tabs, modes, reset/state consistency. |
| `M3` | History and Selection | Scrollback/history and selection/hyperlink semantics are portable and tested. |
| `M4` | Input and Control Surface | Key/input encoding and control interaction surfaces are stable. |
| `M5` | Runtime Interface | Engine runtime interface is host-neutral and explicit. |
| `M6` | Snapshot and Replay Contracts | Stable snapshot/replay contracts for host and diagnostics. |
| `M7` | Performance and Memory Discipline | Hot paths are audited, bounded, and benchmarked. |
| `M8` | Host Integration Readiness | `howl-terminal` API is ready for first host integration without API churn. |
| `M9` | Multi-Host Confidence | Cross-host reproducibility and conformance evidence is established. |
| `M10` | Best-in-Class Embedded Engine | Portable terminal engine with rigorous correctness and operational quality. |

## Current Direction

Current milestone target is `M7`, with `M1-M6` retained as frozen baselines.

## M2 Checklist

M2 is complete only when each checklist item is explicitly satisfied and
validated by replay/parity/runtime evidence.

- `[x]` Wrap semantics: line wrap and bottom-row scroll behavior are deterministic.
- `[x]` Tab semantics: HT/CHT/CBT behavior, clamping, split-feed handling, and interruption determinism are locked.
- `[x]` Mode semantics: DEC private mode state (`?25`, `?7`) is deterministic and reset-consistent.
- `[x]` Reset/state consistency: `clear`, `reset`, `resetScreen`, and DECSTR behavior are contract-aligned and parity-covered.
- `[x]` Cursor alias semantics: CSI `a` (CUF alias), `e` (CUD alias), and `` ` `` (CHA alias) are mapped, deterministic, and parity-tested.

### M2 Closeout Sequence

1. Run a final M2 breadth-gap audit against current contracts and replay surface.
2. Implement or explicitly defer each in-scope gap with tests and authority updates.
3. Perform one M2 freeze pass (contracts, milestone progress, active queue) and mark `M2` done.

## M3 Checklist

M3 is complete only when history and selection behavior are portable,
host-neutral, and covered by replay/parity/runtime evidence.

- `[x]` Scope boundary: scrollback/history and selection are model/runtime behavior; host UI gestures, clipboard, renderer policy, and platform integration stay out of scope.
- `[x]` Coordinate model: viewport coordinates, history coordinates, and selection endpoints are explicit and deterministic across scroll.
- `[x]` History storage: bottom scrolling captures visible rows into bounded history without changing frozen M2 visible-screen semantics.
- `[x]` Reset/clear policy: `clear`, `reset`, `resetScreen`, DECSTR, zero-dimension screens, and history truncation have documented, tested behavior.
- `[x]` Selection lifecycle: selection start/update/finish/clear works across viewport and history coordinates with deterministic invalidation rules.
- `[x]` Runtime API: hosts can read history/selection through minimal const, host-neutral accessors; no mutable screen/history escape hatch is introduced.
- `[x]` Replay evidence: direct pipeline, runtime facade, and chunked-feed parity tests cover history-producing streams and selection state transitions.

### M3 Closeout Sequence

1. Freeze M3 history/selection contracts and update the model/runtime API contracts.
2. Run the full M3 replay/parity/runtime validation matrix.
3. Mark `M3` done in milestone progress and replace the active queue with the next milestone handoff.

## M4 Checklist

M4 is complete only when input/control behavior is contract-defined, host-neutral,
and replay-tested through runtime surfaces.

- `[x]` M4-A1: Input contract: supported key/modifier/mouse/control event model is explicit and separate from host/platform event types.
- `[x]` M4-A2: Encoding contract: deterministic input-to-byte encoding rules are documented and test-backed for supported modes.
- `[x]` M4-A3: Runtime input surface: engine exposes host-neutral input encode/feed entry points without parser/pipeline leakage.
- `[x]` M4-B1: Mode interactions: input behavior with active modes is explicit (keyboard encoding mode-agnostic, mouse encoding mode-aware; INPUT_CONTROL.md documents both).
- `[x]` M4-B2: Extended key coverage: deterministic encoding for INS, DEL, HOME, END, PAGEUP, PAGEDOWN with full modifier support.
- `[x]` M4-B3: Function-key baseline: F1-F12 constants and deterministic encoding with modifier support.
- `[x]` Replay evidence: direct and runtime parity tests cover control output for representative key/control sequences (keyboard input comprehensive coverage, modifier combinations, reset stability, extended/function keys).

### M4 Closeout Sequence

1. Freeze input/control contracts and runtime API additions.
2. Run full M4 input parity/replay validation.
3. Publish/update `app_architecture/authorities/M4_FOUNDATION.md`.
4. Mark `M4` done and publish next milestone handoff.

## M5 Checklist

M5 is complete only when runtime interface behavior is explicit, host-neutral,
and parity-tested for real host-loop usage patterns.

- `[x]` M5-A: Runtime contract closure: lifecycle, mutation boundaries, and reset/clear interactions are unambiguous in authority docs.
- `[x]` M5-B: Runtime interface hardening: `Engine` API aligns to contract without host/platform leakage or mutable escapes.
  - M5-B1 (docstrings): all stable methods documented with behavior and mutation/read boundaries
  - M5-B2 (parity tests): 5 mixed host-loop tests proving runtime facade transparency
- `[x]` M5-C: Runtime parity matrix: mixed host-loop operation sequences are covered by replay/parity/runtime tests (M5-B2 completed).
- `[x]` M5-D: Freeze evidence: M5 authority/progress/queue are finalized and M6 handoff is published.

### M5 Closeout Sequence

1. Publish/update `app_architecture/authorities/M5_FOUNDATION.md` with bounded start/end and stop conditions.
2. Execute M5-A through M5-D in order with contract-first validation.
3. Mark `M5` done and repoint active queue to M6 planning scope.

## M6 Checklist

M6 is complete only when snapshot/replay behavior is explicit, host-neutral, and
proven deterministic through runtime/direct parity evidence.

- `[x]` M6-A: Snapshot/replay contract closure: payload boundaries, replay framing, and invariants are unambiguous.
- `[x]` M6-B: Snapshot surface: runtime/model const read APIs align to contract without mutable escapes.
- `[x]` M6-C: Replay evidence matrix: snapshot/replay invariants are test-backed across direct and runtime flows.
- `[x]` M6-D: Freeze evidence: M6 authority/progress/queue are finalized and M7 handoff is published.

### M6 Closeout Sequence

1. Publish/update `app_architecture/authorities/M6_FOUNDATION.md` with bounded start/end, gates, and stop conditions.
2. Execute M6-A through M6-D in order with contract-first validation.
3. Mark `M6` done and repoint active queue to M7 planning scope.

## M7 Checklist

M7 is complete only when performance and memory discipline are defined by
explicit doctrine, audited against the real codebase, and backed by reproducible
evidence rather than intuition.

- `[ ]` M7-A: Performance doctrine closure: metric priority order, tradeoff rules, and "bounded" vocabulary are explicit.
- `[ ]` M7-B: Measurement protocol: trusted local benchmark/profiling method is documented and reproducible.
- `[ ]` M7-C: Hot-path audit: parser/event/screen/runtime/snapshot hot paths and allocation sites are classified and ranked.
- `[ ]` M7-D: Implementation gates: future optimization tickets are bounded by exact targets, evidence expectations, and stop conditions.
- `[ ]` M7-E: Freeze evidence: doctrine, audit findings, accepted optimizations, and resulting bounds are frozen for M8.

### M7 Closeout Sequence

1. Complete architect-only doctrine and audit work before publishing any engineer execution queue.
2. Land only optimization slices that tie to declared measurement surfaces and preserve frozen `M1-M6` semantics.
3. Mark `M7` done only when the memory/performance story is explicit enough to support host-readiness work without guesswork.

## Authority Rules

- Milestone docs define intent and acceptance, not ticket logs.
- Queue docs define current work only.
- Commit history and tests remain implementation evidence.
- Engineer loop control rules are defined in `docs/architect/WORKFLOW.md`.
