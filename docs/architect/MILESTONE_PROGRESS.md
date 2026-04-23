# Milestone Progress Board

This board tracks milestone state only. It does not track implementation steps.

| Milestone | Status | Scope Anchor | Notes |
| --- | --- | --- | --- |
| `M0` Repo Scaffold | `done` | `app_architecture/authorities/SCOPE.md` | Build/test/docs baseline established. |
| `M1` Parser-Screen Foundation | `done` | `app_architecture/authorities/M1_FOUNDATION.md` | Parser/event/screen/runtime foundation frozen with contracts and replay coverage. |
| `M2` Terminal State Breadth | `done` | `app_architecture/authorities/MILESTONE.md` | Wrap/tabs/modes/reset-state/cursor-alias semantics are complete and parity-tested. M2 frozen with contracts. |
| `M3` History and Selection | `done` | `app_architecture/authorities/MILESTONE.md` | Contracts frozen and implementation complete (history FIFO storage, runtime history read surface, signed selection coordinates, deterministic eviction invalidation, parity/runtime coverage). |
| `M4` Input and Control Surface | `done` | `app_architecture/authorities/M4_FOUNDATION.md` | Input/control contracts frozen (INPUT_CONTROL.md, MODEL_API.md, RUNTIME_API.md). Keyboard encoding implemented and tested for: printable ASCII, special keys (ENTER/ESCAPE/TAB/BACKSPACE), cursor keys (UP/DOWN/LEFT/RIGHT), extended keys (HOME/END/INS/DEL/PAGEUP/PAGEDOWN), function keys (F1-F12). All with full modifier support (Shift/Alt/Ctrl). Determinism and reset/screen-state independence verified. |
| `M5` Runtime Interface | `done` | `app_architecture/authorities/M5_FOUNDATION.md` | M5 complete and frozen: lifecycle contract matrix, conformance tests, runtime docstring hardening, and mixed host-loop parity matrix are validated. |
| `M6` Snapshot and Replay Contracts | `active` | `app_architecture/authorities/M6_FOUNDATION.md` | M6 authority published. Next: M6-A contract closure, M6-B snapshot surface, M6-C replay evidence, M6-D freeze handoff. |
| `M7` Performance and Memory Discipline | `planned` | `app_architecture/authorities/MILESTONE.md` | Deferred. |
| `M8` Host Integration Readiness | `planned` | `app_architecture/authorities/MILESTONE.md` | Deferred. |
| `M9` Multi-Host Confidence | `planned` | `app_architecture/authorities/MILESTONE.md` | Deferred. |
| `M10` Best-in-Class Embedded Engine | `planned` | `app_architecture/authorities/MILESTONE.md` | Long-term target. |
