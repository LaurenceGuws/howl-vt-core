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
| `HT-015` | `done` | Deterministic parser transcript assertions (no count-only checks). | `src/terminal_parser_dispatch_test.zig` | Parser dispatch assertions are exact type/order/payload transcripts. |
| `HT-016` | `done` | Incremental-feed boundary fixtures (UTF-8/CSI/OSC/APC/DCS). | `src/terminal_parser_dispatch_test.zig` | Multi-call boundary behavior is covered by explicit fixtures. |
| `HT-017A` | `done` | Report-integrity rules/checklist. | `docs/todo/ACTIVE_QUEUE.md`, `docs/todo/REPORT_CHECKLIST.md` | Commit claims are required to map to `git show --name-status`. |

## Next

| ID | Status | Intent | Primary files | Exit |
| --- | --- | --- | --- | --- |
| `HT-018` | `ready` | Freeze parser API contract in architecture authority. | `app_architecture/terminal/PARSER_API_CONTRACT.md` | Stable parser/model entrypoints documented with breaking-change rule. |
| `HT-019` | `ready` | Add first parser integration seam (no host coupling). | `src/terminal/**` | Adapter consumes `parser.Parser` + `Sink` and emits minimal core event surface. |

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
