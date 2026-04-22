# Howl Terminal Active Queue

Execution-only queue for `howl-terminal`.

## Goal

Build `howl-terminal` into a standalone, portable VT engine with deterministic
behavior, replayable tests, and no dependency on app/editor/platform code.

## Active / Next

| ID | Status | Intent |
| --- | --- | --- |
| `HT-047` | `done` | Completed prior batch. |
| `HT-048A` | `done` | Queue/doc hygiene: retire stale manifest, sync active queue. |
| `HT-048B` | `done` | Semantic mapping for CSI J/K erase operations. |
| `HT-048C` | `done` | Screen erase apply behavior for line and display modes. |
| `HT-048D` | `done` | Relay integration fixtures for erase flow. |
| `HT-048E` | `done` | Contract sync: document erase events and update queue status. |
| `HT-049A` | `done` | Define minimal SGR semantic scope and defer advanced features. |
| `HT-049B` | `done` | Semantic mapping for CSI m (SGR) operations. |
| `HT-049C` | `done` | Apply style state in screen cell writes. |
| `HT-049D` | `done` | Relay integration fixtures for style flow. |
| `HT-049E` | `done` | Contract sync and queue status update for style. |

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
