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

Current milestone target is `M1`, with `M0` baseline retained.

## Authority Rules

- Milestone docs define intent and acceptance, not ticket logs.
- Queue docs define current work only.
- Commit history and tests remain implementation evidence.
- Engineer loop control rules are defined in `docs/architect/WORKFLOW.md`.
