//! Responsibility: define terminal model value types and default style helpers.
//! Ownership: terminal model core type definitions.
//! Reason: provide a single source of truth for parser/runtime shared data shapes.

/// Cursor row/column position in model space.
pub const CursorPos = struct {
    row: usize,
    col: usize,
};

/// Visual cursor shape variants.
pub const CursorShape = enum {
    block,
    underline,
    bar,
};

/// Cursor appearance style (shape + blink policy).
pub const CursorStyle = struct {
    shape: CursorShape,
    blink: bool,
};

/// Default cursor style used when no explicit style is configured.
pub const default_cursor_style = CursorStyle{ .shape = .block, .blink = true };

const selection_mod = @import("selection.zig");

/// Selection position re-export from selection module.
pub const SelectionPos = selection_mod.SelectionPos;
/// Selection struct re-export from selection module.
pub const TerminalSelection = selection_mod.TerminalSelection;

/// Terminal cell value including codepoint, composition, geometry, and attrs.
pub const Cell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [2]u32 = .{ 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    attrs: CellAttrs,
};

/// Return true when cell is a continuation fragment of a wide/tall glyph.
pub fn isCellContinuation(cell: Cell) bool {
    return cell.x != 0 or cell.y != 0;
}

/// Return true when cell is the root of a multi-row glyph.
pub fn isMultiRowCellRoot(cell: Cell) bool {
    return cell.height > 1 and cell.x == 0 and cell.y == 0;
}

/// Cell styling and hyperlink metadata.
pub const CellAttrs = struct {
    fg: Color,
    bg: Color,
    bold: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    underline: bool,
    underline_color: Color,
    link_id: u32,
};

/// RGBA color value.
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

/// Logical key identifier used by runtime input encoding.
pub const Key = u32;
/// Modifier bitset used by runtime input encoding.
pub const Modifier = u8;
/// Optional physical key identifier for layout-aware metadata.
pub const PhysicalKey = u32;

/// Optional metadata for alternate keyboard reporting paths.
pub const KeyboardAlternateMetadata = struct {
    // Logical/physical key identity for layout-aware alternate reporting.
    physical_key: ?PhysicalKey = null,
    // UTF-8 text produced by the event (if any).
    produced_text_utf8: ?[]const u8 = null,
    // Layout-derived codepoints used for kitty alternate-key reporting.
    base_codepoint: ?u32 = null,
    shifted_codepoint: ?u32 = null,
    alternate_layout_codepoint: ?u32 = null,
    // Marks IME/compose output where alternate inference may be suppressed.
    text_is_composed: bool = false,
};

/// Mouse button identity for mouse input events.
pub const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
};

/// Mouse event kind for mouse input events.
pub const MouseEventKind = enum(u8) {
    press,
    release,
    move,
    wheel,
};

/// Host-neutral mouse event payload for input encoding.
pub const MouseEvent = struct {
    kind: MouseEventKind,
    button: MouseButton,
    row: i32,
    col: u16,
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
    mod: Modifier,
    buttons_down: u8,
};

/// Logical key constant for "no key".
pub const VTERM_KEY_NONE: Key = 0;
/// Logical key constant for Enter.
pub const VTERM_KEY_ENTER: Key = 1;
/// Logical key constant for Tab.
pub const VTERM_KEY_TAB: Key = 2;
/// Logical key constant for Backspace.
pub const VTERM_KEY_BACKSPACE: Key = 3;
/// Logical key constant for Escape.
pub const VTERM_KEY_ESCAPE: Key = 4;
/// Logical key constant for Up arrow.
pub const VTERM_KEY_UP: Key = 5;
/// Logical key constant for Down arrow.
pub const VTERM_KEY_DOWN: Key = 6;
/// Logical key constant for Left arrow.
pub const VTERM_KEY_LEFT: Key = 7;
/// Logical key constant for Right arrow.
pub const VTERM_KEY_RIGHT: Key = 8;
/// Logical key constant for Insert.
pub const VTERM_KEY_INS: Key = 9;
/// Logical key constant for Delete.
pub const VTERM_KEY_DEL: Key = 10;
/// Logical key constant for Home.
pub const VTERM_KEY_HOME: Key = 11;
/// Logical key constant for End.
pub const VTERM_KEY_END: Key = 12;
/// Logical key constant for Page Up.
pub const VTERM_KEY_PAGEUP: Key = 13;
/// Logical key constant for Page Down.
pub const VTERM_KEY_PAGEDOWN: Key = 14;
/// Logical key constant for left Shift key.
pub const VTERM_KEY_LEFT_SHIFT: Key = 15;
/// Logical key constant for right Shift key.
pub const VTERM_KEY_RIGHT_SHIFT: Key = 16;
/// Logical key constant for left Ctrl key.
pub const VTERM_KEY_LEFT_CTRL: Key = 17;
/// Logical key constant for right Ctrl key.
pub const VTERM_KEY_RIGHT_CTRL: Key = 18;
/// Logical key constant for left Alt key.
pub const VTERM_KEY_LEFT_ALT: Key = 19;
/// Logical key constant for right Alt key.
pub const VTERM_KEY_RIGHT_ALT: Key = 20;
/// Logical key constant for left Super key.
pub const VTERM_KEY_LEFT_SUPER: Key = 21;
/// Logical key constant for right Super key.
pub const VTERM_KEY_RIGHT_SUPER: Key = 22;
/// Logical key constant for function key F1.
pub const VTERM_KEY_F1: Key = 23;
/// Logical key constant for function key F2.
pub const VTERM_KEY_F2: Key = 24;
/// Logical key constant for function key F3.
pub const VTERM_KEY_F3: Key = 25;
/// Logical key constant for function key F4.
pub const VTERM_KEY_F4: Key = 26;
/// Logical key constant for function key F5.
pub const VTERM_KEY_F5: Key = 27;
/// Logical key constant for function key F6.
pub const VTERM_KEY_F6: Key = 28;
/// Logical key constant for function key F7.
pub const VTERM_KEY_F7: Key = 29;
/// Logical key constant for function key F8.
pub const VTERM_KEY_F8: Key = 30;
/// Logical key constant for function key F9.
pub const VTERM_KEY_F9: Key = 31;
/// Logical key constant for function key F10.
pub const VTERM_KEY_F10: Key = 32;
/// Logical key constant for function key F11.
pub const VTERM_KEY_F11: Key = 33;
/// Logical key constant for function key F12.
pub const VTERM_KEY_F12: Key = 34;

/// Modifier constant for no active modifiers.
pub const VTERM_MOD_NONE: Modifier = 0;
/// Modifier constant for Shift.
pub const VTERM_MOD_SHIFT: Modifier = 1;
/// Modifier constant for Alt.
pub const VTERM_MOD_ALT: Modifier = 2;
/// Modifier constant for Ctrl.
pub const VTERM_MOD_CTRL: Modifier = 4;

/// Create a default blank cell with default foreground/background styling.
pub fn defaultCell() Cell {
    return Cell{
        .codepoint = 0,
        .width = 1,
        .attrs = CellAttrs{
            .fg = default_fg,
            .bg = default_bg,
            .bold = false,
            .blink = false,
            .blink_fast = false,
            .reverse = false,
            .underline = false,
            .underline_color = default_fg,
            .link_id = 0,
        },
    };
}

/// Default foreground color used by terminal cells.
pub const default_fg = Color{ .r = 220, .g = 220, .b = 220 };
/// Default background color used by terminal cells.
pub const default_bg = Color{ .r = 24, .g = 25, .b = 33 };
/// Default underline color value (transparent means inherit/default behavior).
pub const default_underline_color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
/// Default cell attribute set used for freshly initialized cells.
pub const default_cell_attrs = CellAttrs{
    .fg = default_fg,
    .bg = default_bg,
    .bold = false,
    .blink = false,
    .blink_fast = false,
    .reverse = false,
    .underline = false,
    .underline_color = default_underline_color,
    .link_id = 0,
};
/// Default cell value used when clearing or initializing cell buffers.
pub const default_cell = Cell{
    .codepoint = 0,
    .attrs = default_cell_attrs,
};
