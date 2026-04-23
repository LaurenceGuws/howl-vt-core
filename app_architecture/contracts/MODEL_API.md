# Howl Terminal Model API Contract

`MODEL_API_CONTRACT` — frozen as of HT-044.
Authority for `src/model.zig`, `src/model/types.zig`, `src/model/selection.zig`, and `src/model/metrics.zig`.

## Stable Exported Symbols

### Model Module (`src/model.zig`)

**types / selection / metrics** (module exports)
- Responsibility: expose model submodules through one stable root.
- Ownership: model API boundary.
- Breakage: removing or renaming exported submodules.

**CursorPos, CursorShape, CursorStyle, Cell, CellAttrs, Color, SelectionPos, TerminalSelection, SelectionState, Metrics** (re-exports)
- Responsibility: stable consumer-facing type surface for parser/event/screen lanes.
- Ownership: model API boundary.
- Breakage: removing re-exports or changing re-exported type semantics without contract update.

### Types (`src/model/types.zig`)

**CursorPos / CursorShape / CursorStyle**
- Responsibility: cursor position and visual style value types.
- Breakage: field/type/variant changes.

**Cell / CellAttrs / Color**
- Responsibility: cell content and style representation.
- Breakage: field/type changes; semantic changes to color/default behavior.

**SelectionPos / TerminalSelection** (re-exported from selection module, M3)
- Responsibility: selection endpoint and state data representation.
- Ownership: M3 selection primitive.
- Breakage: field/type changes; coordinate representation changes.
- Coordinate semantics: defined in `app_architecture/contracts/HISTORY_SELECTION.md`.

**defaultCell**
- Responsibility: default cell construction helper.
- Breakage: function signature changes or semantic behavior changes.

### Selection (`src/model/selection.zig`)

**SelectionState**
- Responsibility: selection lifecycle transitions (`init`, `clear`, `start`, `update`, `finish`, `state`).
- Ownership: model selection primitive.
- Breakage: method signature changes; active/selecting state-transition changes.

### Metrics (`src/model/metrics.zig`)

**Metrics**
- Responsibility: lightweight runtime metrics accumulation (`init`, `beginFrame`, `noteInput`, `recordDraw`).
- Ownership: model metrics primitive.
- Breakage: field/schema changes; EMA and latency update semantic changes.

## Behavioral Guarantees

- `SelectionState.state()` returns `null` when inactive; otherwise current selection snapshot.
- `SelectionState.start/update/finish/clear` preserve the active/selecting contract implied by method names.
- `Metrics.beginFrame` updates frame EMA only after an initial frame timestamp exists.
- `Metrics.recordDraw` updates draw EMA; updates input-latency metrics only when `last_input_time` is set.

## M3 History and Selection Integration

History and selection are added in M3 as transparent extensions:

- Selection state is independent of visible screen and does not affect M1-M2 cursor/cell behavior.
- Selection is never cleared or invalidated by semantic screen events (`reset()`, DECSTR, `clear()`).
- History storage is optional and allocator-owned; does not affect M1-M2 visible-screen guarantees.
- Selection endpoints use signed coordinates to reference both viewport and history rows.
- History is truncated explicitly only when capacity is reduced, not by any semantic screen operation.
- Zero-cell or zero-dimension screens do not allocate history regardless of M3 configuration.

Detailed history and selection semantics are in `app_architecture/contracts/HISTORY_SELECTION.md`.

## Non-Goals

- No host/session/platform coupling.
- No rendering policy decisions.
- No PTY/protocol dispatch behavior.
- No scrollback/wrap/terminal-runtime policy.
- No text extraction, clipboard, or selection painting (M3 provides coordinate model only).

## Breaking Change Rule

A change is breaking if:
1. An exported model symbol is removed or renamed.
2. Public struct fields or enum variants change.
3. Public function signatures change.
4. Behavioral guarantees above change.

## Breaking Change Approval

Required for any breaking change:
- Explicit mention in commit message (`BREAKING: ...`).
- Rationale describing the necessity.
- Update to this contract document.
- Update to impacted consumer contracts/tests.
