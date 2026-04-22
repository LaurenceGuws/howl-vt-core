# Howl Terminal Scope Authority

Purpose: define what `howl-terminal` owns, what it does not own, and how this
repo fits the broader Howl family.

## Product Identity

`howl-terminal` is a portable terminal engine. It is a backend package, not a
host app.

## In Scope

- VT parser and tokenization behavior
- Semantic mapping from parser events to terminal operations
- Terminal state model (screen/grid/cursor/history/selection as milestones land)
- Deterministic engine-side runtime surfaces required to feed bytes and read
  state
- Replayable tests for semantic behavior and invariants
- Stable package-facing API for host consumption

## Out of Scope

- GUI host concerns
- Android/JNI/export app lifecycle integration
- Renderer/frontend ownership
- Packaging and app distribution
- Editor/workspace concerns

## Ownership Split

- `howl-terminal`: terminal backend and portable engine behavior
- `howl-hosts`: GUI/platform/app runtime ownership and demos
- `howl-shared`: reusable supporting packages

## Quality Bar

- No compatibility/fallback/workaround paths
- Deterministic behavior first
- Replay tests are authority for behavior claims
- Architecture docs define rules; milestone docs define direction
- Active queues track only current work surface
- Engineer execution control is governed by `docs/architect/WORKFLOW.md`.
