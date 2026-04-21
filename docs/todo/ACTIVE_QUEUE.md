# Howl Terminal Active Queue

Execution-only queue for `howl-terminal`.
Keep this file short: active ticket(s), next ticket(s), and current guardrails.

## Goal

Build `howl-terminal` into a standalone, portable VT engine with deterministic
behavior, replayable tests, and no dependency on app/editor/platform code.

## Milestones

| ID | Target | Exit |
| --- | --- | --- |
| `HT-M2` | Minimal semantic VT core builds standalone | Parser/model/protocol/core slice compiles with no host/UI/FFI/JNI imports |
| `HT-M3` | Core behavior tests ported | Unit/reflow/protocol fixtures pass under Howl naming |
| `HT-M4` | Replay harness proof | Deterministic replay fixture runner with smoke/cursor/reflow fixtures |
| `HT-M5` | Public package API | `src/root.zig` exposes a narrow stable API |
| `HT-M6` | Host API boundary | PTY/FFI/host adapter shape is Howl-owned (no legacy ABI compatibility) |

## Active

| ID | Status | Intent | Primary files | Exit |
| --- | --- | --- | --- | --- |
| `HT-021` | `done` | Freeze bridge seam contract. | `app_architecture/terminal/PARSER_CORE_EVENT_BRIDGE_CONTRACT.md` | Contract document is normative authority for CoreEvent and bridge. |
| `HT-022` | `done` | Harden bridge correctness tests. | `src/terminal_parser_core_event_bridge_test.zig` | OSC/APC/DCS/invalid/ownership policies locked by explicit assertions. |
| `HT-023` | `done` | Bridge queue API (len/isEmpty/clear/drainInto). | `src/terminal/parser_core_event_bridge.zig`, `src/terminal_parser_core_event_bridge_test.zig` | Bridge usable as reusable seam with explicit queue operations. |
| `HT-024` | `done` | Parser core event pipeline module. | `src/terminal/parser_core_event_pipeline.zig`, `src/terminal_parser_core_event_pipeline_test.zig`, `build.zig` | Pipeline owns parser+bridge; feedByte/feedSlice/events/reset; exported from root. |
| `HT-025` | `done` | Replay-style pipeline fixtures. | `src/terminal_parser_core_event_pipeline_test.zig` | Stray-ESC, invalid UTF-8, split CSI, interleaved feed FIFO locked by deterministic fixtures. |

## Next

| ID | Status | Intent | Primary files | Exit |
| --- | --- | --- | --- | --- |
| `HT-027` | `ready` | VT cursor movement consumer in pipeline. | `src/terminal/**` | Pipeline emits cursor-move events for CUU/CUD/CUF/CUB/CUP CSI sequences. |
| `HT-028` | `ready` | Screen model integration seam. | `src/terminal/**` | Pipeline connects to minimal screen model (rows/cols/cursor); no host coupling. |

## Guardrails

- Frozen legacy source is copybook, not authority.
- No compatibility/fallback/workaround paths.
- No app/editor/platform/session/publication imports in core parser/model lanes.
- Ticket metadata stays out of Zig source comments.

## Report Evidence Rule

Every commit report must include:
- Commit hash
- Exact files changed from `git show --name-status <hash>`
- One-line claim -> file mapping

Use `docs/todo/REPORT_CHECKLIST.md` before sending reports.
