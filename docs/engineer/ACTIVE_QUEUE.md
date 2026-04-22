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

**Status:** RF-B3 (RF-301, RF-302, RF-303) completed by engineer execution.

RF-301: Added 14 edge-determinism integration tests covering CUU/CUD/CUF/CUB saturation at boundaries, CR/LF/BS interaction on edges, and zero-dimension pipeline safety. Stopped at zero-dimension cursor behavior mismatch (documented in contract as no-op, but cursor moves during non-cell operations).

RF-302: Updated SEMANTIC_SCREEN.md and M1_FOUNDATION.md to document cursor saturation guarantees, control sequence edge invariants, and zero-dimension screen safety.

RF-303: Queue rewritten for RF-B4 wait.

**Next:** Await architect decision on zero-dimension cursor behavior (contract vs runtime) and publication of next batch.

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
