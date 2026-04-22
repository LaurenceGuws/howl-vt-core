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

## Module layout (post HT-039)

```
src/parser/{parser,stream,utf8,csi}.zig   — parser primitives
src/event/{bridge,pipeline,semantic}.zig  — event layer
src/screen/state.zig                       — screen state
src/test/relay.zig                         — integration replay tests
src/root.zig                               — public API surface
```

## Test convention (post HT-040/041)

- Pure unit tests live inline in their module file.
- Integration tests (multi-module) go to `src/test/relay.zig`.
- `relay.zig` is included via `root.zig` so it runs under `zig build test`.
- No scattered `*_test.zig` files at `src/` root.

## Completed

| ID | Status | Intent | Primary files |
| --- | --- | --- | --- |
| `HT-021` | `done` | Freeze bridge seam contract. | `app_architecture/terminal/PARSER_CORE_EVENT_BRIDGE_CONTRACT.md` |
| `HT-022` | `done` | Harden bridge correctness tests. | (now inline in `src/event/bridge.zig` + `src/test/relay.zig`) |
| `HT-023` | `done` | Bridge queue API (len/isEmpty/clear/drainInto). | `src/event/bridge.zig` |
| `HT-024` | `done` | Parser core event pipeline module. | `src/event/pipeline.zig` |
| `HT-025` | `done` | Replay-style pipeline fixtures. | `src/test/relay.zig` |
| `HT-026` | `done` | Sync root exports and queue contract. | `src/root.zig` |
| `HT-027` | `done` | VT cursor movement consumer. | `src/event/semantic.zig` |
| `HT-028` | `done` | Screen model integration. | `src/screen/state.zig` |
| `HT-029` | `done` | Pipeline wired to screen apply. | `src/event/pipeline.zig` |
| `HT-030` | `done` | Cursor replay fixtures. | `src/test/relay.zig` |
| `HT-031` | `done` | Semantic/screen contract doc. | `app_architecture/terminal/PARSER_CORE_SEMANTIC_SCREEN_CONTRACT.md` |
| `HT-032` | `done` | Text and control semantic events. | `src/event/semantic.zig` |
| `HT-033` | `done` | Screen text buffer and apply. | `src/screen/state.zig` |
| `HT-034` | `done` | End-to-end replay fixtures (text+cursor). | `src/test/relay.zig` |
| `HT-039` | `done` | Normalize module names and paths. | `src/parser/`, `src/event/`, `src/screen/` |
| `HT-040` | `done` | Migrate unit tests inline; remove scattered test files. | all modules + `src/test/relay.zig` |
| `HT-041` | `done` | Simplify build test wiring to module + integration suites. | `build.zig` |
| `HT-042` | `done` | Sync architecture/docs to new naming and test conventions. | this file |

## Next

| ID | Status | Intent |
| --- | --- | --- |
| `HT-043` | `ready` | Next feature work (TBD). |

## Guardrails

- Frozen legacy source is copybook, not authority.
- No compatibility/fallback/workaround paths.
- No app/editor/platform/session/publication imports in core parser/model lanes.
- Ticket metadata stays out of Zig source comments.
- Doc-only tickets must not touch source files.
- No `terminal_`, `core_`, or noisy prefix names in module file names or imports.
- All unit tests inline; integration tests in `src/test/relay.zig` only.

## Report Evidence Rule

Every commit report must include:
- Commit hash
- Exact files changed from `git show --name-status <hash>`
- One-line claim -> file mapping

Use `docs/todo/REPORT_CHECKLIST.md` before sending reports.
