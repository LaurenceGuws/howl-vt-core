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

The `howl_terminal` module root orders the stable M1 seam first:

1. `parser` — byte and escape parsing into sink events
2. `pipeline` — parser plus bridge queue and `applyToScreen`
3. `semantic` — `SemanticEvent` mapping from bridge `Event`
4. `screen` — `ScreenState` and `apply`
5. `runtime` — `Engine` facade composing parser+pipeline+screen into single interface (convenience layer for hosts)

`model` remains exported for shared types used elsewhere in Howl; style and color fields there are not driven by the M1 `SemanticEvent` / `ScreenState` replay path. Behavioral authority for the non-style core is `app_architecture/contracts/SEMANTIC_SCREEN.md`.

## M1 runtime facade

The `runtime.Engine` is a host-neutral convenience facade that composes `Pipeline` and `ScreenState` without modifying any parser/semantic/screen behavior. Hosts can use the facade to avoid direct pipeline/semantic imports and get a simpler async feed→apply→read interface.

`Engine` provides:
- `init(allocator, rows, cols)` — screen without cell buffer
- `initWithCells(allocator, rows, cols)` — screen with cells
- `feedByte(byte)` / `feedSlice(bytes)` — accumulate input
- `apply()` — drain queue and update screen
- `clear()` / `reset()` — queue and parser management
- `screenRef()` / `screenMut()` — screen state access
- `queuedEventCount()` — queue introspection

The facade is a transparent wrapper; it does not extend VT semantics or change any M1 contracts. Behavior is identical to direct pipeline usage. Architectural benefit: hosts see only `Engine`, not parser/bridge/semantic layers.

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

## Remaining M1 Outcomes

- Reassess screen model boundaries against scope authority
- Reconfirm semantic-to-screen API shape for non-style core behavior
- Tighten replay fixtures around cursor/erase/control determinism
- Define first stable public API subset for host-neutral consumption
- Freeze M1 contract set once behaviors are verified and bounded

## Exit Criteria

- `zig build` and `zig build test` pass
- Contract docs and milestone docs are aligned
- Active queue references only in-scope M1 work
- No stale implementation ledgers required to understand current scope

## Non-Goals for M1

- Full style/color finalization
- Host integration and GUI runtime concerns
- Broad optimization campaigns outside foundation correctness
