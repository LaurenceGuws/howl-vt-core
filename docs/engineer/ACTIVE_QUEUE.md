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

**Status:** RF-B4 (RF-401, RF-402, RF-403) completed by engineer execution.

RF-401: Added 7 explicit zero-dimension variant tests covering rows=0/cols>0, rows>0/cols=0, and rows=0/cols=0 cases. Verified cursor movement (saturates), text writes (no-op), erase (no-op), and control sequences (deterministic) under zero-dimension conditions. All tests pass.

RF-402: Updated SEMANTIC_SCREEN.md and M1_FOUNDATION.md to clarify architect policy: text/erase are no-ops when no cell plane, cursor arithmetic continues with saturation. Removed ambiguous "all-op no-op" language; encoded explicit policy.

RF-403: Queue rewritten with RF-B4 completion; zero-dimension policy ambiguity closed.

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
