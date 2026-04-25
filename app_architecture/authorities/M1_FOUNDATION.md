# M1 Foundation Authority

Milestone: `M1` (Parser-Screen Foundation)

Purpose: establish a clean, deterministic foundation to build full terminal
behavior without carrying stale state design.

## Kept from Prior Work

These completed outcomes remain in force:

- Parser/tokenization foundation and dispatch tests
- Event bridge and pipeline scaffolding
- Minimal semantic cursor/control mapping
- Minimal screen state model with erase/cursor/text behavior
- Library/test-only topology (no local app executable)
- Existing contract docs for parser/event/model seams

## M1 Focus

M1 scope is intentionally limited to parser/event/screen foundation behavior.
Style and color expansion is outside this milestone and not part of current execution scope.

## M1 package surface (host-neutral)

The `vt_core` module root orders the stable M1 seam first:

1. `parser` — byte and escape parsing into sink events
2. `pipeline` — parser plus bridge queue and `applyToScreen`
3. `semantic` — `SemanticEvent` mapping from bridge `Event`
4. `screen` — `ScreenState` and `apply`
5. `runtime` — `Engine` facade composing parser+pipeline+screen into single interface (convenience layer for hosts)

`model` remains exported for shared types used elsewhere in Howl; style and color fields there are not driven by the M1 `SemanticEvent` / `ScreenState` replay path. Behavioral authority for the non-style core is `app_architecture/contracts/SEMANTIC_SCREEN.md`.

The root module includes compile-time tests that guard the M1 host-neutral exports and the `runtime.Engine` facade method shapes. Runtime API authority lives in `app_architecture/contracts/RUNTIME_API.md`. A public surface change should fail local tests until this authority document and affected contracts are deliberately updated.

## M1 runtime facade

The `runtime.Engine` is a host-neutral convenience facade that composes `Pipeline` and `ScreenState` without modifying any parser/semantic/screen behavior. Hosts can use the facade to avoid direct pipeline/semantic imports and get a simpler async feed→apply→read interface.

`Engine` provides:
- `init(allocator, rows, cols)` — screen without cell buffer
- `initWithCells(allocator, rows, cols)` — screen with cells
- `feedByte(byte)` / `feedSlice(bytes)` — accumulate input
- `apply()` — drain queue and update screen
- `clear()` / `reset()` — queue and parser management
- `resetScreen()` — screen state reset without parser/queue reset
- `screen()` — screen state access (const reference)
- `queuedEventCount()` — queue introspection

The facade is a transparent wrapper; it does not extend VT semantics or change any M1 contracts. Behavior is identical to direct pipeline usage. Architectural benefit: hosts see only `Engine`, not parser/bridge/semantic layers.

Runtime parity confidence is enforced by replay integration tests in `src/test/relay.zig` that run identical scenario streams through direct `Pipeline+ScreenState` and through `runtime.Engine`, then assert matching cursor/cell/queue outcomes across cursor, control, erase, split-feed, and zero-dimension cases.

Parity coverage includes ignored-event determinism as a first-class invariant:
OSC title payloads, APC payloads, DCS payloads, ESC-final passthrough events, and non-mapped controls must not mutate screen state at this seam; after apply, queue depth must still deterministically drain to zero for both direct pipeline and runtime facade flows.

## M1 pipeline determinism (non-style)

The `Pipeline` orchestration layer is part of the M1 foundation: `clear` drops queued bridge work without screen application; `reset` clears both the queue and parser partial state; each `applyToScreen` drains the queue once and then clears it, so repeated apply without new input is a no-op on `ScreenState`. Full wording lives under “Pipeline seam” in `app_architecture/contracts/SEMANTIC_SCREEN.md`.

## M1 edge and zero-dimension determinism

M1 guarantees deterministic behavior at all boundary conditions:

**Cursor and control saturation:**
- Cursor movement (CUU/CUD/CUF/CUB) saturates at edges; repeated moves remain clamped
- Control sequences (CR/LF/BS) maintain invariants and saturate at boundaries
- Behavior at edges is idempotent: further moves do not change state

**Zero-dimension policy:**
- Text writes are no-ops when no cell plane exists (`rows=0` or `cols=0`)
- Erase operations are no-ops when no cell buffer exists (`cells == null`)
- Cursor arithmetic continues to work; saturates to origin on fully zero screens
- Pipeline clear/reset/apply remain safe and deterministic; no corruption possible

**Test coverage:**
- Boundary saturation tested in `src/test/relay.zig` “edge determinism” section
- Zero-dimension variants (rows=0×cols>0, rows>0×cols=0, rows=0×cols=0) tested in “zero-dim” section
- All cursor/control/erase operations verified safe and deterministic

## M1 Freeze State

M1 is frozen as the minimal parser-to-screen foundation. The accepted surface is:

- parser/event/screen pipeline behavior documented in `SEMANTIC_SCREEN.md`
- event bridge behavior documented in `EVENT_BRIDGE.md`
- parser API behavior documented in `PARSER_API.md`
- model exports documented in `MODEL_API.md`
- runtime facade behavior documented in `RUNTIME_API.md`
- replay tests in `src/test/relay.zig`
- root API guard tests in `src/root.zig`

Further terminal breadth belongs to M2 unless it is a bug fix against these contracts.

## Exit Criteria

- `zig build` and `zig build test` pass
- Contract docs and milestone docs are aligned
- Active queue references only in-scope M1 work
- No stale implementation ledgers required to understand current scope

## Non-Goals for M1

- Full style/color finalization
- Host integration and GUI runtime concerns
- Broad optimization campaigns outside foundation correctness
