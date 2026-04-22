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

**Status:** M1 parser-screen foundation frozen; M2 tab/reset/state interruption matrix complete.

Recent checkpoints:
- RF-601: runtime parity matrix corrected and authority updated
- RF-701: ignored-event and split-feed parity coverage added
- RF-801: root API guard tests added
- RF-901: runtime facade API contract added
- M2-107..M2-130: DEC private mode state (`?25`, `?7`), CHT/CBT (`CSI I/Z`), reset/resetScreen/clear sequencing, split-feed interruption determinism, and replay/parity/runtime contract alignment completed.

**Next:** Continue M2 terminal state breadth beyond the completed tab/reset interruption matrix; pick the next VT behavior frontier with the same replay/parity/runtime contract-first discipline.

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
