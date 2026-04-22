# Howl Terminal Active Queue

Execution-only queue for current engineer loop.

## Ownership

- Architect writes and replaces this file every loop.
- Engineer executes only listed tickets.
- Engineer does not plan, redesign, or expand scope.

## Scope Anchor

- Scope authority: `app_architecture/authorities/SCOPE.md`
- Milestone authority: `app_architecture/authorities/M1_FOUNDATION.md`
- Architect workflow: `docs/architect/WORKFLOW.md`

## Current Loop

**Status:** RF-B5 (RF-501, RF-502, RF-503, RF-504) completed by engineer execution.

RF-501: Implemented host-neutral runtime.Engine facade composing Pipeline + ScreenState. API: init/initWithCells/deinit, feedByte/feedSlice, apply/clear/reset, screenRef/screenMut, queuedEventCount. Exported from src/root.zig. Transparent wrapper with no behavioral changes to underlying components.

RF-502: Added 18 integration tests for runtime facade covering: lifecycle safety, feed+apply parity with direct pipeline, clear/reset behavior, queue introspection, zero-dimension safety, complex sequences. All tests pass; facade verified as transparent wrapper.

RF-503: Updated M1_FOUNDATION.md, SEMANTIC_SCREEN.md, and README.md to document runtime facade as host-neutral convenience layer. Clarified that facade does not extend VT semantics; it packages deterministic parser→pipeline→semantic→screen flow into simpler async API.

RF-504: Queue rewritten with RF-B5 completion; M1 runtime facade complete.

**Next:** Await architect-published batch for the following loop. No open engineer tickets.

## Ticket Format (Required)

Each ticket must include:
- `ID`
- `Target files`
- `Allowed change type`
- `Non-goals`
- `Validation`
- `Stop conditions`

## Guardrails

- No compatibility/fallback/workaround paths.
- No app/editor/platform/session/publication imports in parser/event/screen lanes.
- Ticket metadata stays out of Zig source comments.
- Doc-only tickets must not touch source files.
- Unit tests stay inline; integration tests stay in `src/test/relay.zig`.
