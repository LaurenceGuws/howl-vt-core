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

## Ownership and Lifetime

The `write_text` slice in `SemanticEvent` is a borrowed reference into the `Bridge` event queue. Its lifetime is bounded by the containing `applyToScreen` call: the slice is valid from when `process` returns it until `bridge.clear()` is called at the end of `applyToScreen`. Screen consumers that need to retain content must copy bytes into their own storage during `apply`.

All other SemanticEvent variants are value types with no heap ownership.

The `ScreenState.cells` buffer (when present) is heap-allocated and owned by the creator. The caller who calls `initWithCells` must call `deinit` with the same allocator.

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
| `style_change` with other finals | `null` | Explicitly ignored |
| `text` | `write_text` | Borrowed slice |
| `codepoint` | `write_codepoint` | Value copy |
| `control` 0x0A | `line_feed` | — |
| `control` 0x0D | `carriage_return` | — |
| `control` 0x08 | `backspace` | — |
| `control` other | `null` | Explicitly ignored |
| `title_set` | `null` | Not a screen content event at this seam |
| `invalid_sequence` | `null` | Explicitly ignored |

## ScreenState Behavioral Guarantees

- Cursor row and column are always within `[0, rows-1]` and `[0, cols-1]` respectively, enforced by saturating arithmetic on every mutation.
- Zero-dimension screens (`rows=0` or `cols=0`) are safe: pipeline clear/reset/apply are no-ops for cell operations.
- Cursor movement commands (`cursor_up`, `cursor_down`, `cursor_forward`, `cursor_back`) saturate at screen boundaries; repeated moves beyond edges remain clamped.
- `cursor_position` (CUP) places cursor within bounds; out-of-range params saturate to valid grid.
- Text writes advance `cursor_col` after each character. When `cursor_col` reaches `cols-1`, it stays there (no line wrap at this seam; no scrolling).
- `line_feed` moves `cursor_row` down one row, clamped at `rows-1`. Column unchanged. No scrolling.
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
- Erase operations are no-ops when no cell buffer is present (`cells == null`).
- Cell buffer (when present) is zero-initialized. Unwritten cells contain codepoint 0.
- Control sequence edges (CR at column 0, LF at bottom row, BS at column 0, CUU/CUD/CUF/CUB beyond bounds) maintain deterministic saturation: movement and erase remain safe and predictable at all boundary conditions.

## Non-Goals

The following are intentionally outside this seam:

- Line wrapping or scrollback
- Wide character (multi-column) glyph handling
- Color, style, or attribute storage
- Mode-set sequences (SM/RM/DECSET)
- Tab stops or HT/VT control
- Host, session, PTY, or platform coupling

## Breaking Change Rule

A change is breaking if:

1. A `SemanticEvent` variant is added, removed, or renamed
2. The payload type of any variant changes
3. The mapping policy for any `Event` variant changes (emit vs null)
4. `ScreenState` cursor boundary semantics change
5. The ownership rule for `write_text` lifetime changes
6. `ScreenState.init` or `initWithCells` signature changes

## Breaking Change Approval

Required for any breaking-change:

- Explicit mention in commit message ("BREAKING: ...")
- Rationale explaining the necessity
- Update to this document
- Update to consumers of affected API
