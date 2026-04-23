# History and Selection Contract

Authority for history storage, selection state, and coordinate model for M3 History and Selection milestone.

Defines the shared coordinate space, history capacity policy, and selection lifecycle across viewport and retained rows.

## Coordinate Model

### Viewport Coordinates
- Visible cell plane: rows `[0, rows-1]`, cols `[0, cols-1]`.
- Corresponds to `ScreenState.cursor_row`, `ScreenState.cursor_col` and visible cells on the active screen.
- Always present when `ScreenState` exists.

### History Coordinates
- Rows scrolled off the top during bottom-row scroll, captured in bounded allocator-owned storage.
- History row numbering: row `-1` is the most recent off-screen row (first to scroll off), row `-H` is the oldest retained row.
- History is optional and created only when cell storage exists and history capacity is configured.
- Zero-capacity or no-cell screens do not allocate history.

### Selection Coordinate Representation
- Selection start and end each have: `row` (signed; negative = history, 0-based = viewport), `col` (unsigned; 0-based).
- Selection is inactive when `state()` returns `null`.
- When active, selection spans from `start` to `end` with the natural order (no swap required).

## History Storage

### Ownership and Lifecycle
- History buffer is allocator-owned when created with cell storage.
- History capacity is explicit and immutable per `ScreenState` lifetime; passed at init time.
- Zero capacity means no history is retained; line feed at bottom row scrolls the visible buffer but does not preserve scrolled rows.
- No-cell screens (created with `ScreenState.init`, not `initWithCells`) do not allocate history regardless of configured capacity.

### Scroll Capture Behavior
- `line_feed` at bottom row and pending-wrap bottom scroll each capture the outgoing top row into history (when cells and capacity exist).
- Each captured row is stored in FIFO order; when history is full, the oldest row is discarded.
- History capacity does not include the visible viewport; a screen with 24 visible rows and 100-line history holds 124 total lines.

### History Access
- History is readable through runtime const facade only; no direct mutable access.
- History rows are stable; reallocation does not occur after initial allocation.
- Capacity is bounded; no overflow can occur.

## Selection Lifecycle

### State Transitions
- Inactive (`null`): initial state or after `clear()`.
- Active: after `start(row, col)`.
- Selecting: during `update(row, col)` calls while active.
- Finished: after `finish(row, col)` completes the selection; remains accessible until `clear()`.

### Coordinate Scope
- `start(row, col)` can reference viewport or history rows; col is always in viewport range.
- `update(row, col)` and `finish(row, col)` follow same scoping rules.
- Selection endpoints are stored exactly as provided; no clamping or normalization.

## Reset, Clear, and DECSTR Effects

### `ScreenState.reset()` / `resetScreen()`
- Resets cursor to origin, clears visible cells, restores mode defaults.
- Does **not** clear selection state.
- Does **not** truncate history.
- Selection remains valid and unchanged across `reset()`.

### Runtime `reset()`
- Resets parser and clears queued events (does not mutate screen).
- Does not affect selection state or history.
- Used to discard incomplete escape sequences and pending text.

### Runtime `resetScreen()`
- Calls `ScreenState.reset()` (clears visible cells, resets cursor and modes).
- Does **not** clear selection or truncate history.
- Parser and queued events are preserved.

### DECSTR (`CSI ! p`)
- Semantic `reset_screen` event: resets cursor to origin, clears visible cells, restores modes.
- Identical to `ScreenState.reset()` semantics from M2 SEMANTIC_SCREEN.md.
- Does **not** clear selection state.
- Does **not** truncate history.

### Runtime `clear()`
- Drops queued bridge events without applying them to screen.
- Does not mutate screen state, history, or selection.
- Used to cancel pending input before `apply()`.

## Selection Invalidation Rules

### Triggering Events
- Selection is **not** cleared by `reset()`, `resetScreen()`, DECSTR, or `clear()`.
- Selection is **not** invalidated by visible-screen scroll (line feed at bottom, pending wrap).

### History Truncation
- If history capacity is reduced, oldest rows are discarded.
- If both selection endpoints fall entirely within discarded rows, selection is invalidated (`state()` returns `null`).
- If one endpoint falls in discarded history and the other is in retained history or viewport, selection remains valid and spans the retained range.
- Selection invalidation is explicit and deterministic based on configured capacity change.

### Explicit Invalidation
- Selection is cleared by calling `clear()` on `SelectionState`.
- No other M3 operations invalidate selection.

## Zero-Dimension and No-Cell Behavior

- A screen with `rows=0` or `cols=0` has no cell plane and does not allocate history.
- A screen created with `ScreenState.init()` (no cells) does not allocate history.
- Selection state is independent of cell plane and can be valid on cursor-only screens.
- `reset()` and DECSTR are safe on zero-dimension screens and follow `ScreenState` contract (no-ops for cell operations).

## Non-Goals

The following are intentionally outside this contract:

- Host UI gesture interpretation (mouse, keyboard, clipboard).
- Text extraction or normalization from selection.
- Renderer highlighting policy or color palette.
- Alternate screen mode or buffer switching.
- Wide character (multi-column) glyph handling in selection.
- Selection auto-scroll or dynamic bounds adjustment.
- Platform integration (drag-drop, accessibility, IME).

## Breaking Change Rule

A change is breaking if:

1. Selection coordinates change representation or meaning.
2. Selection is cleared by `reset()`, DECSTR, or `clear()`.
3. History is truncated by `reset()` or DECSTR.
4. Selection is invalidated by visible-screen scroll.
5. History capacity becomes mutable or unbounded.
6. History becomes accessible through mutable facade.

## Breaking Change Approval

Required for any breaking change:

- Explicit mention in commit message (`BREAKING: ...`).
- Rationale explaining necessity.
- Update this contract document.
- Update model API, runtime API, and semantic screen contracts if affected.
- Update M3 replay/parity/runtime tests to validate new behavior.
