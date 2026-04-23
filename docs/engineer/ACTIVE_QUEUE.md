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

**Status:** M1 frozen; M2 closeout execution wave active.

### TICKET M2-CLOSE-01: Cursor Alias Semantics Pack (`a`, `e`, `` ` ``)

**Target files**
- `src/event/semantic.zig`
- `src/screen/state.zig`
- `src/test/relay.zig`
- `app_architecture/contracts/SEMANTIC_SCREEN.md`

**Allowed change type**
- Add semantic mappings for cursor alias finals:
  - `CSI a` -> horizontal relative position (alias of CUF behavior)
  - `CSI e` -> vertical relative position (alias of CUD behavior)
  - `CSI \`` -> horizontal absolute position (alias of CHA behavior)
- Add deterministic replay/parity/parity-chunked/runtime coverage for each alias.
- Add edge checks (default param, clamp behavior) for each alias.
- Update contract mapping/guarantees for alias coverage.

**Non-goals**
- Do not change parser/bridge ownership boundaries.
- Do not alter existing semantics for `A/B/C/D/E/F/G/H/f/d/I/Z/J/K/?25/?7/DECSTR`.
- Do not add host/runtime API surface.

**Validation**
- `zig build`
- `zig build test`
- `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`

**Stop conditions**
- If alias mapping requires parser or bridge architecture changes, stop and report.
- If any existing replay/parity scenario changes behavior unexpectedly, stop and report exact failing tests before patching.

### TICKET M2-CLOSE-02: Alias Interruption Matrix (`DECSTR` ordering)

**Target files**
- `src/test/relay.zig`
- `app_architecture/contracts/SEMANTIC_SCREEN.md`
- `app_architecture/contracts/RUNTIME_API.md`

**Allowed change type**
- Extend interruption-order coverage for `a/e/\`` with both stream classes:
  - split alias interrupted by DECSTR bytes
  - split alias started after DECSTR
- Add evidence in all lanes:
  - direct replay
  - parity (non-chunked)
  - parity (chunked)
  - runtime integration
- Update interruption coverage index/scope text in contracts.

**Non-goals**
- Do not introduce new semantic variants beyond alias work from M2-CLOSE-01.
- Do not rewrite existing interruption assertions for previously covered families unless required by failing tests.

**Validation**
- `zig build`
- `zig build test`
- `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`

**Stop conditions**
- If interruption behavior is nondeterministic between direct and runtime paths, stop and report minimal repro bytes + observed divergence.
- If contract wording would conflict with current tested behavior, stop and report proposed wording delta.

### TICKET M2-CLOSE-03: M2 Breadth Closure + Freeze Prep

**Target files**
- `app_architecture/authorities/MILESTONE.md`
- `docs/architect/MILESTONE_PROGRESS.md`
- `docs/engineer/ACTIVE_QUEUE.md`

**Allowed change type**
- Mark M2 checklist items complete only if backed by merged tests/contracts.
- Replace queue with explicit M2 freeze handoff or next-milestone entrypoint.
- Align milestone progress wording to final M2 outcome.

**Non-goals**
- No source changes in `src/**`.
- No new feature scope in this ticket.

**Validation**
- `zig build`
- `zig build test`

**Stop conditions**
- If any M2 checklist item lacks authoritative test coverage, stop and list the missing coverage item(s) rather than marking done.

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
