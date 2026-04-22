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

`model` remains exported for shared types used elsewhere in Howl; style and color fields there are not driven by the M1 `SemanticEvent` / `ScreenState` replay path. Behavioral authority for the non-style core is `app_architecture/contracts/SEMANTIC_SCREEN.md`.

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
