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

**Status:** M2 frozen; awaiting M3 scope definition.

## M2 Freeze Handoff

M2 Terminal State Breadth is **complete and frozen**. All checklist items are implemented and covered by deterministic replay/parity/runtime test evidence:

- Wrap semantics (`A`/`B`/`C`/`D`/`E`/`F` cursor motion, line wrapping, scroll behavior)
- Tab semantics (`I`/`Z`/HT tabulation, clamping, split-feed interruption)
- Mode semantics (`?25`/`?7` cursor visibility and auto-wrap)
- Reset/state consistency (`clear`, `reset`, `resetScreen`, DECSTR)
- Cursor alias semantics (`a`/`e`/`` ` `` as aliases for CUF/CUD/CHA)

Contract and test coverage are in `app_architecture/contracts/SEMANTIC_SCREEN.md` and `src/test/relay.zig`.

## Next Milestone

M3 **History and Selection** is planned but not yet scoped. Awaiting architect design and milestone breakdown.

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
