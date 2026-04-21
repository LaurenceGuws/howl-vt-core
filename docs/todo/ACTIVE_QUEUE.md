# Howl Terminal Active Queue

This is the active planning surface for `howl-terminal`. Keep it short,
executable, and code-facing.

## Goal

Build `howl-terminal` into a standalone, portable VT engine that can eventually
stand beside serious terminal cores such as Ghostty's VT layer: small public
surface, deterministic behavior, replayable tests, and no dependency on the old
monolithic IDE.

Frozen legacy source is copybook, not authority. Copy only what passes current
Howl boundaries and naming rules.

## Naming Rules

- Product/repo/binary: `howl-terminal`
- Zig package/import where needed: `howl_terminal`
- Human name: `Howl Terminal`
- Forbidden in this repo: legacy brand strings, legacy ABI names, and
  compatibility aliases

## Milestones

| ID | Target | Exit |
| --- | --- | --- |
| `HT-M1` | Clean package skeleton and project authority | `zig build` / `zig build test` pass; docs name the goal and first queue |
| `HT-M2` | Minimal semantic VT core builds standalone | Parser/model/screen/protocol/core slice compiles under `howl_terminal`; no host/UI/FFI/JNI imports |
| `HT-M3` | Core behavior tests ported | Small unit/reflow/protocol tests pass from copied fixtures with Howl names |
| `HT-M4` | Replay harness proof | Deterministic replay fixture runner exists with at least smoke/cursor/reflow fixtures |
| `HT-M5` | Public package API | `src/root.zig` exposes a narrow Howl Terminal API without leaking internal layout |
| `HT-M6` | Host API boundary | PTY/FFI/host adapter shape is designed from Howl needs, not copied legacy ABI compatibility |

## Current Work

| ID | Status | Intent | Primary files | Exit |
| --- | --- | --- | --- | --- |
| `HT-001` | `done` | Replace `zig init` scaffold with Howl Terminal project authority and active queue. | `README.md`, `docs/todo/ACTIVE_QUEUE.md`, `build.zig.zon` | Project names are correct; `zig build` and `zig build test` pass. |
| `HT-002` | `done` | Prepare first core-copy manifest from frozen source without moving code yet. | `docs/todo/HT_002_CORE_COPY_MANIFEST.md` | Manifest names the smallest source/test set for `HT-M2`; excludes FFI, UI, Android, editor, and host packaging. |
| `HT-003` | `done` | Copy parser/model heartbeat and add first proof test. | `src/terminal/parser/{stream,utf8,csi}.zig`, `src/terminal/model/{types,selection,metrics}.zig` | Parser/model compiles under Howl naming; 11 tests pass. |
| `HT-004` | `done` | Add first proof test—CSI parser tokenization. | `src/terminal_csi_parse_test.zig`, `build.zig` | 7 CSI parser tests + 4 embedded tests pass; wired into `zig build test`. |
| `HT-005` | `done` | Fix HT-004 test assertions to match parser contract (count field semantics). | `src/terminal_csi_parse_test.zig` | All 11 tests pass with correct count expectations. |
| `HT-006` | `done` | Update capability wording to reflect parser primitives scope. | `src/root.zig` | Removed VT100-only phrasing; accurate description of ANSI/DEC/CSI support. |
| `HT-007` | `done` | Wire parser proof tests into build test execution. | `build.zig`, `src/root.zig` | Parser tests run deterministically via `zig build test`. |
| `HT-008` | `done` | Add standalone parser state machine with callback dispatch. | `src/terminal/parser/parser.zig`, `src/terminal/parser.zig` | Parser: 386 lines, no app/session/FFI coupling, callback Sink interface. |
| `HT-009` | `done` | Add parser dispatch proof tests and wire into build. | `src/terminal_parser_dispatch_test.zig`, `build.zig` | 9 dispatch tests pass: mixed stream, terminators, UTF-8/ASCII, CSI params. |
| `HT-010` | `done` | Harden parser: errdefer cleanup, explicit stray-ESC contract. | `src/terminal/parser/parser.zig` | Memory-safe init; contract documented: ESC marker dropped in OSC/APC/DCS. |
| `HT-011` | `done` | Strengthen test assertions; sync queue to reflect completed work. | `src/terminal_parser_dispatch_test.zig`, `docs/todo/ACTIVE_QUEUE.md` | Exact event sequence + payload assertions; queue reflects HT-001..011 done. |

## First Core-Copy Default

Current default is parser/model heartbeat only (`HT-003`).

- include: parser primitives + model primitives needed for one proof test
- defer: FFI, host/PTy integration, Android, renderer/presentation, editor/workspace,
  selection/scrolling/reflow, and any session/publication code

If a copied file imports app/editor/platform/session code, stop and shrink.

## Validation

For each implementation commit:

- `zig build`
- `zig build test`
- `rg -n "<legacy-brand-pattern>" .`

Expected grep result: no matches.
