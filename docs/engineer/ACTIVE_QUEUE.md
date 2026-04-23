# Howl Terminal Active Queue

Execution-only queue for the current engineer loop.

## Ownership

- Architect writes and replaces this file every loop.
- Engineer executes only listed tickets.
- Engineer does not plan, redesign, or expand scope.

## Scope Anchor

- Scope authority: `app_architecture/authorities/SCOPE.md`
- Milestone authority: `app_architecture/authorities/MILESTONE.md`
- Architect workflow: `docs/architect/WORKFLOW.md`

## Current Loop

**Status:** M4-A accepted and frozen. Execute M4-B.

M1/M2/M3/M4-A are frozen. Do not reopen parser/screen/history/selection or
M4-A input behavior unless an M4-B test exposes a direct regression.

## M4-B Tickets

### M4-B1: Mode-Interaction Contract Closure

- `ID`: M4-B1
- `Target files`: `app_architecture/contracts/INPUT_CONTROL.md`, `app_architecture/contracts/RUNTIME_API.md`
- `Allowed change type`: documentation-first authority update (code only if required for consistency)
- `Intent`: close the remaining mode-interaction ambiguity by defining exactly what mode state influences encoding in M4
- `Required behavior`:
  - one unambiguous rule for context sensitivity (mode-aware vs fully mode-agnostic) for current encode surface
  - explicit reset/resetScreen effects on input mode state
  - explicit non-goals for unsupported mode-dependent behavior in M4
- `Non-goals`: no host/platform event schemas; no renderer or clipboard policy
- `Validation`: `zig build`; `zig build test`; `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`
- `Stop conditions`: stop if closure requires breaking M4-A API signatures or reopening frozen M1-M3 behavior

### M4-B2: Extended Key Coverage

- `ID`: M4-B2
- `Target files`: `src/runtime/engine.zig`, `src/model.zig`, `src/model/types.zig`, `src/test/relay.zig`, `app_architecture/contracts/INPUT_CONTROL.md`
- `Allowed change type`: runtime encode expansion + tests + contract sync
- `Intent`: add deterministic encoding for remaining core non-printable keys in M4 scope
- `Required behavior`:
  - implement deterministic encode behavior for `INS`, `DEL`, `HOME`, `END`, `PAGEUP`, `PAGEDOWN`
  - encode output must be stable for all modifier combinations currently supported by policy
  - no mutation of parser/screen/history/selection state during encode calls
- `Non-goals`: no function key matrix yet; no mode-specific mouse reporting formats
- `Validation`: `zig build`; `zig build test`; shim grep above
- `Stop conditions`: stop if any key requires host layout/platform keycode coupling

### M4-B3: Function-Key Baseline

- `ID`: M4-B3
- `Target files`: `src/model/types.zig`, `src/model.zig`, `src/runtime/engine.zig`, `src/test/relay.zig`, `app_architecture/contracts/INPUT_CONTROL.md`, `app_architecture/contracts/MODEL_API.md`
- `Allowed change type`: add F-key constants/surface + deterministic encode support + tests
- `Intent`: establish a minimal but explicit function-key encode baseline in M4
- `Required behavior`:
  - add canonical model constants for function keys in scoped range (`F1`-`F12`)
  - add deterministic encode mappings with modifiers per adopted contract
  - include runtime tests proving determinism and reset/resetScreen stability
- `Non-goals`: no full terminal profile compatibility matrix; no host-specific function-key remapping
- `Validation`: `zig build`; `zig build test`; shim grep above
- `Stop conditions`: stop if proposed mappings conflict with frozen M4-B1 contract decisions

### M4-B4: M4 Closeout Evidence Pack

- `ID`: M4-B4
- `Target files`: `src/test/relay.zig`, `app_architecture/contracts/INPUT_CONTROL.md`, `app_architecture/authorities/MILESTONE.md`, `docs/architect/MILESTONE_PROGRESS.md`, `docs/engineer/ACTIVE_QUEUE.md`
- `Allowed change type`: tests + closeout docs
- `Intent`: finish remaining M4 checklist items and prepare milestone freeze transition
- `Required behavior`:
  - parity/replay tests demonstrate representative control-output coverage for implemented M4 scope
  - M4 checklist reflects completed scope only (no overclaims)
  - progress board and queue are updated for post-M4 handoff
- `Non-goals`: no expansion beyond implemented M4 features
- `Validation`: `zig build`; `zig build test`; shim grep above
- `Stop conditions`: stop if required parity cannot be demonstrated without changing frozen milestone behavior

## Report Format

Engineer report must include:

- `#DONE`
- `#OUTSTANDING`
- commit hash and subject for each ticket
- validation commands and results
- files changed per commit
- exact stop-condition details if blocked

## Guardrails

- No compatibility/fallback/workaround paths.
- No app/editor/platform/session/publication imports in parser/event/screen/model/runtime lanes.
- Ticket metadata stays out of Zig source comments.
- Doc-only tickets must not touch source files.
- Unit tests stay inline; integration tests stay in `src/test/relay.zig`.
