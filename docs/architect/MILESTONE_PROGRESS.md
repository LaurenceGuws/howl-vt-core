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
| `M6` Snapshot and Replay Contracts | `done` | `app_architecture/authorities/M6_FOUNDATION.md` | Snapshot/replay contract authority published (SNAPSHOT_REPLAY.md). Snapshot surface hardened with comprehensive docstrings. Replay evidence matrix validates determinism, reset/clear boundaries, mode changes, and direct vs runtime parity. M6 complete and frozen. |
| `M7` Performance and Memory Discipline | `done` | `app_architecture/authorities/M7_FOUNDATION.md` | M7 frozen. Doctrine, audit, protocol, fixtures, and baseline evidence (`M7-BL-001`..`M7-BL-005`) are complete. F1/F2/F2B/F3 specs and reviews accepted. Freeze review: `docs/review/m7/M7_FREEZE_REVIEW.md`. |
| `M8` Host Integration Readiness | `done` | `app_architecture/authorities/M8_FOUNDATION.md` | M8 frozen. Contract closure (A), seam audit (B), validation gates (C), and execution evidence slices (E1/E2) are accepted. Freeze review: `docs/review/m8/M8_FREEZE_REVIEW.md`. |
| `M9` Multi-Host Confidence | `done` | `app_architecture/authorities/M9_FOUNDATION.md` | M9 frozen. Conformance contract, protocol, fixtures, and execution evidence are accepted. Freeze review: `docs/review/m9/M9_FREEZE_REVIEW.md`. |
| `M10` Best-in-Class Embedded Engine | `done` | `app_architecture/authorities/M10_FOUNDATION.md` | M10 frozen. Doctrine, evidence protocol, fixtures, execution evidence, and continuous freeze cadence are accepted. Freeze review: `docs/review/m10/M10_FREEZE_REVIEW.md`. |
