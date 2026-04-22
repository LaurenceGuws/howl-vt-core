# Semantic Screen Contract

`SEMANTIC_SCREEN_CONTRACT` — updated at HT-055E. Authority for `SemanticEvent`, `semantic.process`, and `ScreenState`.

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
| `style_reset` | — | CSI 0m | Reset all style attributes to defaults |
| `style_bold_on` | — | CSI 1m | Enable bold |
| `style_bold_off` | — | CSI 22m | Disable bold |
| `style_dim_on` | — | CSI 2m | Enable dim |
| `style_dim_off` | — | CSI 22m | Disable dim (shares code with bold_off; both clears bold and dim) |
| `style_strikethrough_on` | — | CSI 9m | Enable strikethrough |
| `style_strikethrough_off` | — | CSI 29m | Disable strikethrough |
| `style_underline_on` | — | CSI 4m | Enable underline |
| `style_underline_off` | — | CSI 24m | Disable underline |
| `style_inverse_on` | — | CSI 7m | Enable inverse video |
| `style_inverse_off` | — | CSI 27m | Disable inverse video |
| `style_fg_color` | `u8` (0-16) | CSI 30-37,39,90-97m | Set foreground indexed color; 0=default, 1-8=basic colors, 9-16=bright ANSI |
| `style_bg_color` | `u8` (0-16) | CSI 40-47,49,100-107m | Set background indexed color; 0=default, 1-8=basic colors, 9-16=bright ANSI |
| `style_fg_256` | `u8` (0-255) | CSI 38;5;<n>m | Set foreground 256-color palette index |
| `style_bg_256` | `u8` (0-255) | CSI 48;5;<n>m | Set background 256-color palette index |
| `style_fg_rgb` | `struct{r:u8,g:u8,b:u8}` | CSI 38;2;r;g;b;m | Set foreground 24-bit RGB color |
| `style_bg_rgb` | `struct{r:u8,g:u8,b:u8}` | CSI 48;2;r;g;b;m | Set background 24-bit RGB color |

## Ownership and Lifetime

The `write_text` slice in `SemanticEvent` is a borrowed reference into the `Bridge` event queue. Its lifetime is bounded by the containing `applyToScreen` call: the slice is valid from when `process` returns it until `bridge.clear()` is called at the end of `applyToScreen`. Screen consumers that need to retain content must copy bytes into their own storage during `apply`.

All other SemanticEvent variants are value types with no heap ownership.

The `ScreenState.cells` buffer (when present) is heap-allocated and owned by the creator. The caller who calls `initWithCells` must call `deinit` with the same allocator.

## Process Mapping Policy

| Event variant | SemanticEvent emitted | Notes |
| --- | --- | --- |
| `style_change` with final A/B/C/D | `cursor_up/down/forward/back` | Param default 1 |
| `style_change` with final H/f | `cursor_position` | 1-based VT params converted to 0-based |
| `style_change` with final J | `erase_display` | Param default 0; modes 0/1/2 only; other values map to 0 |
| `style_change` with final K | `erase_line` | Param default 0; modes 0/1/2 only; other values map to 0 |
| `style_change` with final m | `style_*` variants or `style_operations` | Ordered multi-parameter SGR processing; single param returns single variant; multiple params return batch; unsupported params skipped |
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
- Zero-dimension screens (`rows=0` or `cols=0`) are safe: all operations are no-ops.
- Text writes advance `cursor_col` after each character. When `cursor_col` reaches `cols-1`, it stays there (no line wrap at this seam; no scrolling).
- `line_feed` moves `cursor_row` down one row, clamped at `rows-1`. No scrolling.
- `carriage_return` resets `cursor_col` to 0; `cursor_row` is unchanged.
- `backspace` moves `cursor_col` left one column, saturating at 0.
- `erase_line` zeroes cells and their attributes in the current row; cursor position is unchanged.
  - Mode 0: cursor position through end of line (inclusive).
  - Mode 1: start of line through cursor position (inclusive).
  - Mode 2: entire line.
  - Erased cell attributes reset to defaults (bold=false, fg=0, bg=0).
- `erase_display` zeroes cells and their attributes across rows; cursor position is unchanged.
  - Mode 0: cursor position through end of screen (inclusive).
  - Mode 1: start of screen through cursor position (inclusive).
  - Mode 2: entire screen.
  - Erased cell attributes reset to defaults (bold=false, fg=0, bg=0).
- Erase operations are no-ops when no cell buffer is present (`cells == null`); style state is unaffected.
- Style operations update current-style state; subsequent text writes apply active style to each cell.
  - `style_reset`: clears bold, dim, underline, inverse, strikethrough, restores foreground/background to defaults.
  - `style_bold_on` / `style_bold_off`: toggle bold attribute (SGR 22 clears both bold and dim).
  - `style_dim_on` / `style_dim_off`: toggle dim attribute (SGR 22 clears both bold and dim).
  - `style_strikethrough_on` / `style_strikethrough_off`: toggle strikethrough attribute.
  - `style_underline_on` / `style_underline_off`: toggle underline attribute.
  - `style_inverse_on` / `style_inverse_off`: toggle inverse video attribute.
- `style_fg_color` / `style_bg_color`: set indexed color (payload 0=default, 1-8=basic colors, 9-16=bright ANSI); stored without truncation.
  - Style state is independent of cell content; does not affect non-text operations.
  - Style attributes on a cell are immutable after the cell is written; style state changes do not retroactively affect written cells.
- Cell buffer (when present) is zero-initialized. Unwritten cells contain codepoint 0 with default style (bold=false, dim=false, underline=false, inverse=false, strikethrough=false, fg=0, bg=0).
- Style attribute storage uses u8 fields for fg/bg to preserve indexed colors (0-16) and 256-color indices (0-255) without truncation. Boolean flags for bold, dim, underline, inverse, strikethrough stored separately.
- SGR 22 (normal intensity) clears both bold and dim, matching VT100 behavior; separate semantic events emitted for each.

## SGR (Style) Scope

Implemented:
- Reset (SGR 0)
- Bold on/off (SGR 1, 22)
- Dim on/off (SGR 2, 22)
- Strikethrough on/off (SGR 9, 29)
- Underline on/off (SGR 4, 24)
- Inverse on/off (SGR 7, 27)
- Foreground basic colors (SGR 30-37, 39)
- Background basic colors (SGR 40-47, 49)
- Foreground bright ANSI colors (SGR 90-97)
- Background bright ANSI colors (SGR 100-107)
- Foreground 256-color palette (SGR 38;5;<n>)
- Background 256-color palette (SGR 48;5;<n>)
- Foreground 24-bit RGB true color (SGR 38;2;r;g;b)
- Background 24-bit RGB true color (SGR 48;2;r;g;b)
- Ordered multi-parameter SGR processing (e.g., 1;38;2;255;0;0 for bold + red truecolor)

Color index mapping:
- Indexed colors via `style_fg_color`/`style_bg_color`: payload 0-16
  - 0 = default (reset to terminal default)
  - 1-8 = basic ANSI colors (SGR 30-37, 40-47)
  - 9-16 = bright ANSI colors (SGR 90-97, 100-107)
- 256-color palette via `style_fg_256`/`style_bg_256`: payload 0-255 (SGR 38;5;<n>, 48;5;<n>)
- All indexed colors stored in u8 fg/bg fields without truncation

Malformed sequences policy:
- Extended color forms (38, 48) without matching subparameter form (5 or 2) are ignored safely
- Incomplete extended sequences (e.g., 38;2;r;g without b) are skipped without breaking valid neighbors
- Invalid RGB component values (> 255) are clamped to 0-255 range
- Unknown parameters are always skipped

Deferred (future sprints):
- Blink (SGR 5)
- Underline color (SGR 58, 59)

## Non-Goals

The following are intentionally outside this seam:

- Line wrapping or scrollback
- Wide character (multi-column) glyph handling
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
