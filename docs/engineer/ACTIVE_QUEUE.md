# Howl Terminal Active Queue

Execution-only queue for current engineer loop.

## Ownership

- Architect writes and replaces this file every loop.
- Engineer executes only listed tickets.
- Engineer does not plan, redesign, or expand scope.

## Scope Anchor

- Scope authority: `app_architecture/authorities/SCOPE.md`
- Milestone authority: `app_architecture/authorities/MILESTONE.md`
- Architect workflow: `docs/architect/WORKFLOW.md`

## Current Loop

**Status:** M1 parser-screen foundation frozen; M2 checklist in closeout phase.

Recent checkpoints:
- RF-601: runtime parity matrix corrected and authority updated
- RF-701: ignored-event and split-feed parity coverage added
- RF-801: root API guard tests added
- RF-901: runtime facade API contract added
- M2-107..M2-130: DEC private mode state (`?25`, `?7`), CHT/CBT (`CSI I/Z`), reset/resetScreen/clear sequencing, split-feed interruption determinism, and replay/parity/runtime contract alignment completed.
- M2-131..M2-143: interruption matrix consolidation expanded across absolute and line-position cursor streams (`G`, `d`, `E`, `F`) with authority alignment.

**Next (ordered M2 closeout):**
1. Run final M2 breadth-gap audit against current semantic mapping and replay surface.
2. Implement or explicitly defer each in-scope gap with replay/parity/runtime proof and authority updates.
3. Execute M2 freeze pass: set milestone board/docs to `M2 done`, and hand off next milestone frontier.

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
