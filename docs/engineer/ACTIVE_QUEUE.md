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

**Status:** RF-B5R (RF-551, RF-552, RF-553, RF-554) completed by engineer execution.

RF-551: API conformance correction: renamed internal field from 'screen' to 'state'; removed non-required screenRef/screenMut accessors; added required screen() method. Facade now exposes exactly specified API: init/initWithCells/deinit, feedByte/feedSlice, apply/clear/reset, screen, queuedEventCount.

RF-552: Updated 17 runtime tests to use screen() instead of screenRef(); removed screenMut test. All tests pass; facade verified against corrected API.

RF-553: Aligned M1_FOUNDATION.md and README.md to document corrected API: screen() replaces screenRef/screenMut; clarified screen() returns const reference.

RF-554: Queue rewritten with RF-B5R completion; API conformance verified.

**Next:** Await architect acceptance and next batch. No open engineer tickets.

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
