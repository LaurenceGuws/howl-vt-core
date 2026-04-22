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

**SelectionPos / TerminalSelection** (re-exported from selection module)
- Responsibility: selection data representation.
- Breakage: field/type changes.

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

## Non-Goals

- No host/session/platform coupling.
- No rendering policy decisions.
- No PTY/protocol dispatch behavior.
- No scrollback/wrap/terminal-runtime policy.

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
