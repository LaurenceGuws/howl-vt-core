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

Current milestone target is `M4`, with `M1` foundation, `M2` terminal state
breadth, and `M3` history/selection retained as frozen baselines.

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

- `[ ]` Input contract: supported key/modifier/mouse/control event model is explicit and separate from host/platform event types.
- `[ ]` Encoding contract: deterministic input-to-byte encoding rules are documented and test-backed for supported modes.
- `[ ]` Runtime input surface: engine exposes host-neutral input encode/feed entry points without parser/pipeline leakage.
- `[ ]` Mode interactions: input behavior with active modes is explicit and deterministic.
- `[ ]` Replay evidence: direct and runtime parity tests cover control output for representative key/control sequences.

### M4 Closeout Sequence

1. Freeze input/control contracts and runtime API additions.
2. Run full M4 input parity/replay validation.
3. Mark `M4` done and publish next milestone handoff.

## Authority Rules

- Milestone docs define intent and acceptance, not ticket logs.
- Queue docs define current work only.
- Commit history and tests remain implementation evidence.
- Engineer loop control rules are defined in `docs/architect/WORKFLOW.md`.
