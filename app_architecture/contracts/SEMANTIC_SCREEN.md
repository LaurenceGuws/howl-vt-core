# Semantic Screen Contract

Authority for `SemanticEvent`, `semantic.process`, and `ScreenState` on the M1 parser-to-screen foundation seam.

M1 scope is non-style core behavior: cursor motion, text and codepoint writes, carriage controls, and erase-in-display / erase-in-line. The package root exposes this seam as `parser`, `pipeline`, `semantic`, and `screen` (see `app_architecture/authorities/M1_FOUNDATION.md`). Bridge `Event.style_change` is the CSI carrier for cursor and erase sequences only at this milestone; SGR and other finals are ignored for screen mapping.

## SemanticEvent Variants

| Variant | Payload | Source | Meaning |
| --- | --- | --- | --- |
| `cursor_up` | `u16` | CSI A | Move cursor up N rows; default 1 if param absent/zero |
| `cursor_down` | `u16` | CSI B | Move cursor down N rows; default 1 |
| `cursor_forward` | `u16` | CSI C | Move cursor right N cols; default 1 |
| `cursor_back` | `u16` | CSI D | Move cursor left N cols; default 1 |
| `cursor_position` | `{row: u16, col: u16}` | CSI H/f | Absolute 0-based position; defaults to origin |
| `write_text` | `[]const u8` | Event.text | Sequence of printable ASCII bytes to write at cursor |
| `write_codepoint` | `u21` | Event.codepoint | Single Unicode scalar to write at cursor |
| `line_feed` | — | Event.control(0x0A) | Move cursor to next row |
| `carriage_return` | — | Event.control(0x0D) | Reset cursor column to 0 |
| `backspace` | — | Event.control(0x08) | Move cursor one column left |
| `erase_display` | `u2` | CSI J | Erase screen region; mode 0=below, 1=above, 2=full |
| `erase_line` | `u2` | CSI K | Erase line region; mode 0=right, 1=left, 2=full |
| `reset_screen` | — | CSI ! p (DECSTR) | Reset screen state to origin and clear cells |

## Ownership and Lifetime

The `write_text` slice in `SemanticEvent` is a borrowed reference into the `Bridge` event queue. Its lifetime is bounded by the containing `applyToScreen` call: the slice is valid from when `process` returns it until `bridge.clear()` is called at the end of `applyToScreen`. Screen consumers that need to retain content must copy bytes into their own storage during `apply`.

All other SemanticEvent variants are value types with no heap ownership.

The `ScreenState.cells` buffer (when present) is heap-allocated and owned by the creator. The caller who calls `initWithCells` must call `deinit` with the same allocator.

`ScreenState.reset()` resets cursor position to origin, clears pending wrap state, and zeroes the owned cell buffer when present. It preserves dimensions and allocation ownership.

## Pipeline seam (`Pipeline` apply boundary)

M1 deterministic host feeding uses `event.Pipeline` over the parser and bridge. These invariants hold regardless of screen buffer presence:

- `Pipeline.clear()` drops all queued bridge events without calling `applyToScreen`; nothing is applied to `ScreenState`.
- `Pipeline.reset()` clears the bridge queue and resets the parser (including partial escape/CSI state); bytes after reset decode as if the parser were freshly initialized.
- Each `applyToScreen` call walks the current bridge queue exactly once, applies `semantic.process` for each event in order, then clears the bridge. A second `applyToScreen` with no intervening `feedByte` / `feedSlice` sees an empty queue and does not mutate `ScreenState`.

## Process Mapping Policy

| Event variant | SemanticEvent emitted | Notes |
| --- | --- | --- |
| `style_change` with final A/B/C/D | `cursor_up/down/forward/back` | Param default 1 |
| `style_change` with final H/f | `cursor_position` | 1-based VT params converted to 0-based |
| `style_change` with final J | `erase_display` | Param default 0; modes 0/1/2 only; other values map to 0 |
| `style_change` with final K | `erase_line` | Param default 0; modes 0/1/2 only; other values map to 0 |
| `style_change` with intermediate `!` and final p | `reset_screen` | DECSTR; no leader/private marker |
| `style_change` with other finals | `null` | Explicitly ignored |
| `text` | `write_text` | Borrowed slice |
| `codepoint` | `write_codepoint` | Value copy |
| `control` 0x0A | `line_feed` | — |
| `control` 0x0D | `carriage_return` | — |
| `control` 0x08 | `backspace` | — |
| `control` 0x09 | `horizontal_tab` | Default tab stops every 8 columns |
| `control` other | `null` | Explicitly ignored |
| `title_set` | `null` | Not a screen content event at this seam |
| `invalid_sequence` | `null` | Explicitly ignored |

## Ignored-Event Invariants

- `title_set`, `invalid_sequence`, non-mapped controls, and non-mapped CSI finals do not mutate `ScreenState` cursor or cell contents at this seam.
- APC/DCS/ESC-final parser callbacks are bridge-dropped and never enter `SemanticEvent` processing.
- `applyToScreen` still drains the bridge queue after processing, even when every queued event is ignored by semantic mapping.
- Split-feed chunking does not change the ignored-event rule: equivalent byte streams must yield identical screen/queue end state regardless of chunk boundaries.

## ScreenState Behavioral Guarantees

- Cursor row and column are always within `[0, rows-1]` and `[0, cols-1]` respectively, enforced by saturating arithmetic on every mutation.
- Cursor movement commands (`cursor_up`, `cursor_down`, `cursor_forward`, `cursor_back`) saturate at screen boundaries; repeated moves beyond edges remain clamped.
- `cursor_position` (CUP) places cursor within bounds; out-of-range params saturate to valid grid.
- Control sequences (CR/LF/BS) maintain row/column invariants: CR resets column, LF advances row, BS moves left; all saturate at edges.
- Horizontal tab advances to the next default 8-column tab stop, clamped at the last column.
- Text writes advance `cursor_col` after each character. Filling the last column arms pending wrap; the next text/codepoint write moves to column 0 on the next row before writing.
- Pending wrap at the bottom row scrolls the visible cell buffer up by one row and clears the new bottom row before writing.
- `line_feed` moves `cursor_row` down one row. At the bottom row it scrolls the visible cell buffer up by one row when cells are present. Column unchanged.
- `carriage_return` resets `cursor_col` to 0; `cursor_row` is unchanged.
- `backspace` moves `cursor_col` left one column, saturating at 0; `cursor_row` is unchanged.
- `erase_line` zeroes cells in the current row; cursor position is unchanged.
  - Mode 0: cursor position through end of line (inclusive).
  - Mode 1: start of line through cursor position (inclusive).
  - Mode 2: entire line.
- `erase_display` zeroes cells across rows; cursor position is unchanged.
  - Mode 0: cursor position through end of screen (inclusive).
  - Mode 1: start of screen through cursor position (inclusive).
- Mode 2: entire screen.
- `reset_screen` / `reset` returns cursor to origin, clears pending wrap, and zeroes existing cells without changing dimensions.

## Zero-Dimension Screen Behavior

- A screen with `rows=0` or `cols=0` has no effective cell plane.
- Text write operations are complete no-ops when no cell plane exists (`rows=0` or `cols=0`); cursor position is not affected.
- Erase operations are complete no-ops when no cell buffer is present (`cells == null`).
- Cursor movement operations follow saturating arithmetic regardless of screen dimensions; a `0×0` screen clamps all moves to origin `(0, 0)`.
- Pipeline clear/reset/apply are safe and deterministic on zero-dimension screens; no cells are written or corrupted.
- All zero-dimension behavior is covered by integration replay tests in `src/test/relay.zig`.

## Non-Goals

The following are intentionally outside this seam:

- Scrollback/history
- Configurable tab stops
- Wide character (multi-column) glyph handling
- Color, style, or attribute storage
- Mode-set sequences (SM/RM/DECSET)
- VT control beyond the mapped M2 controls
- Host, session, PTY, or platform coupling

## Breaking Change Rule

A change is breaking if:

1. A `SemanticEvent` variant is added, removed, or renamed
2. The payload type of any variant changes
3. The mapping policy for any `Event` variant changes (emit vs null)
4. `ScreenState` cursor boundary semantics change
5. The ownership rule for `write_text` lifetime changes
6. `ScreenState.init`, `initWithCells`, or `reset` signature/semantics change

## Breaking Change Approval

Required for any breaking-change:

- Explicit mention in commit message ("BREAKING: ...")
- Rationale explaining the necessity
- Update to this document
- Update to consumers of affected API

## Runtime Facade Integration

The `runtime.Engine` facade (in `src/runtime/engine.zig`) composes `Pipeline` and `ScreenState` into a single interface. The facade is a transparent wrapper that does not modify semantic behavior: it calls `Pipeline.feedByte()`, `Pipeline.applyToScreen()`, and `ScreenState` methods exactly as an external host would.

The facade provides convenience for hosts that want to avoid direct parser/bridge/semantic imports. It does not change any M1 contracts or guarantees documented here; it merely packages the existing deterministic flow into a cleaner async API.
