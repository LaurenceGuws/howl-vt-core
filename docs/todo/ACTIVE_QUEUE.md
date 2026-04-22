# Howl Terminal Active Queue

Execution-only queue for `howl-terminal`.

## Goal

Build `howl-terminal` into a standalone, portable VT engine with deterministic
behavior, replayable tests, and no dependency on app/editor/platform code.

Freeze as-of: `HT-059D`.

## Active / Next

| ID | Status | Intent |
| --- | --- | --- |
| `HT-051A` | `done` | Queue reset: slim scope for 256-color work. |
| `HT-051B` | `done` | SGR 256-color semantic mapping. |
| `HT-051C` | `done` | Screen apply for 256-color style state. |
| `HT-051D` | `done` | Relay fixtures for 256-color integration. |
| `HT-051E` | `done` | Contract + queue sync for 256-color support. |
| `HT-052A` | `done` | Queue + contract scope: 24-bit truecolor. |
| `HT-052B` | `done` | Semantic mapping for truecolor SGR. |
| `HT-052C` | `done` | Screen apply for truecolor attrs. |
| `HT-052D` | `done` | Relay fixtures for truecolor flow. |
| `HT-052E` | `done` | Queue/contract sync close. |
| `HT-053A` | `done` | Queue + contract scope: bright ANSI. |
| `HT-053B` | `done` | Semantic mapping for bright ANSI. |
| `HT-053C` | `done` | Screen apply + reset invariants (verification: no code delta; bright colors apply through existing handlers). |
| `HT-053D` | `done` | Relay fixtures for bright ANSI flow. |
| `HT-053E` | `done` | Contract/queue sync close (closing: no code delta; HT-053A-D complete, scope frozen). |
| `HT-054A` | `done` | Queue + contract scope: underline and inverse. |
| `HT-054B` | `done` | Semantic mapping for underline/inverse SGR. |
| `HT-054C` | `done` | Screen apply + cell attrs for underline/inverse. |
| `HT-054D` | `done` | Relay fixtures for underline/inverse flow. |
| `HT-054E` | `done` | Contract/queue sync close. |
| `HT-055A` | `done` | Queue + contract scope: dim and strikethrough. |
| `HT-055B` | `done` | Semantic mapping for dim/strikethrough SGR. |
| `HT-055C` | `done` | Screen apply + cell attrs for dim/strikethrough. |
| `HT-055D` | `done` | Relay fixtures for dim/strikethrough flow. |
| `HT-055E` | `done` | Contract/queue sync close. |
| `HT-056A` | `done` | Scope seed: blink primitives (SGR 5/25) + reset continuity. |
| `HT-056B` | `done` | Semantic mapping for blink on/off in ordered SGR ops. |
| `HT-056C` | `done` | Screen apply + cell attrs for blink persistence/reset. |
| `HT-056D` | `done` | Relay fixtures for blink integration + malformed continuity. |
| `HT-056E` | `done` | Contract/queue close sync for blink batch. |
| `HT-057A` | `done` | Scope seed: underline color SGR 58/59 coverage. |
| `HT-057B` | `done` | Semantic mapping for underline color set/reset paths. |
| `HT-057C` | `done` | Screen state + cell attrs persistence for underline color. |
| `HT-057D` | `done` | Relay fixtures for underline color end-to-end continuity. |
| `HT-057E` | `done` | Contract/queue close sync for underline color batch. |
| `HT-059A` | `done` | Scope seed: library/test-only topology, demos in howl-hosts. |
| `HT-059B` | `done` | Remove local executable entrypoint and run target. |
| `HT-059C` | `done` | Build graph cleanup after executable removal. |
| `HT-059D` | `done` | Validation and queue close sync. |

## Guardrails

- Frozen legacy source is copybook, not authority.
- No compatibility/fallback/workaround paths.
- No app/editor/platform/session/publication imports in core parser/model lanes.
- Ticket metadata stays out of Zig source comments.
- Doc-only tickets must not touch source files.
- No `terminal_`, `core_`, or noisy prefix names in module file names or imports.
- All unit tests inline; integration tests in `src/test/relay.zig` only.

## Layout reference

```
src/parser/{parser,stream,utf8,csi}.zig   — parser primitives
src/event/{bridge,pipeline,semantic}.zig  — event layer
src/screen/state.zig                       — screen state
src/test/relay.zig                         — integration replay tests
src/root.zig                               — public API surface
app_architecture/terminal/
  EVENT_BRIDGE_CONTRACT.md
  SEMANTIC_SCREEN_CONTRACT.md
  MODEL_API_CONTRACT.md
  PARSER_API_CONTRACT.md
```
