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

Current milestone target is `M2`, with `M1` baseline retained.

## M2 Checklist

M2 is complete only when each checklist item is explicitly satisfied and
validated by replay/parity/runtime evidence.

- `[x]` Wrap semantics: line wrap and bottom-row scroll behavior are deterministic.
- `[x]` Tab semantics: HT/CHT/CBT behavior, clamping, split-feed handling, and interruption determinism are locked.
- `[x]` Mode semantics: DEC private mode state (`?25`, `?7`) is deterministic and reset-consistent.
- `[x]` Reset/state consistency: `clear`, `reset`, `resetScreen`, and DECSTR behavior are contract-aligned and parity-covered.
- `[ ]` Remaining core screen-state breadth audit and closure pass for M2 (identify any unmapped in-scope cursor/control semantics and either implement or explicitly defer with authority rationale).

### M2 Closeout Sequence

1. Run a final M2 breadth-gap audit against current contracts and replay surface.
2. Implement or explicitly defer each in-scope gap with tests and authority updates.
3. Perform one M2 freeze pass (contracts, milestone progress, active queue) and mark `M2` done.

## Authority Rules

- Milestone docs define intent and acceptance, not ticket logs.
- Queue docs define current work only.
- Commit history and tests remain implementation evidence.
- Engineer loop control rules are defined in `docs/architect/WORKFLOW.md`.
