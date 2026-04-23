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

**Status:** M3 frozen. Execute M4-A contract and baseline implementation slice.

M1/M2/M3 are frozen. Do not reopen parser/screen/history/selection behavior unless
an M4 test exposes a direct regression.

## M4-A Tickets

### M4-A1: Input/Control Contract Authority

- `ID`: M4-A1
- `Target files`: new `app_architecture/contracts/INPUT_CONTROL.md`, `app_architecture/contracts/RUNTIME_API.md`, `app_architecture/contracts/MODEL_API.md`
- `Allowed change type`: documentation-only authority update
- `Intent`: define host-neutral input/control model and boundaries before adding new runtime behavior
- `Required content`:
  - canonical input event model and fields (key/modifier/mouse/control)
  - encoding ownership boundary (what is in scope for `howl-terminal` vs host)
  - deterministic behavior requirements and non-goals
  - explicit interactions with existing mode/reset contracts
- `Non-goals`: no Zig source changes; no platform event schemas; no renderer/clipboard policy
- `Validation`: `zig build`; `zig build test`; `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`
- `Stop conditions`: stop if contract requires host/platform coupling or breaks frozen M1-M3 API guarantees

### M4-A2: Runtime Input Encode Surface

- `ID`: M4-A2
- `Target files`: `src/runtime/engine.zig`, `src/model/types.zig`, `src/root.zig`, `src/test/relay.zig`, any new `src/runtime/*` module needed
- `Allowed change type`: add minimal host-neutral input encode surface in runtime
- `Intent`: provide deterministic control-byte output for supported input events without exposing parser/pipeline internals
- `Required behavior`:
  - input API accepts abstract model input types only
  - output bytes are deterministic for covered key/control cases
  - no mutation of frozen history/selection behavior
- `Non-goals`: no host adapters; no platform keycode tables; no IME/editor policy; no compatibility alias APIs
- `Validation`: `zig build`; `zig build test`; shim grep above
- `Stop conditions`: stop if implementation requires host platform event dependencies or incompatible runtime API breaks

### M4-A3: Input Parity and Reset/Mode Contracts

- `ID`: M4-A3
- `Target files`: `src/test/relay.zig`, `app_architecture/contracts/INPUT_CONTROL.md`, `app_architecture/contracts/RUNTIME_API.md`
- `Allowed change type`: tests + contract tightening for implemented M4 input slice
- `Intent`: lock determinism for initial input/control behavior and preserve reset/mode expectations
- `Required behavior`:
  - parity tests for representative input/control sequences
  - explicit reset and mode interaction assertions for new input API
  - contract text reflects implemented behavior exactly
- `Non-goals`: no broad feature expansion beyond the implemented M4-A2 surface
- `Validation`: `zig build`; `zig build test`; shim grep above
- `Stop conditions`: stop if parity cannot be established without reopening frozen M1-M3 semantics

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
