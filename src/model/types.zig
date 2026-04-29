//! Responsibility: define model value types and constants.
//! Ownership: model core data-shape authority.
//! Reason: keep parser shared representations deterministic.

/// Cursor position value type.
pub const CursorPos = struct {
    row: usize,
    col: usize,
};

/// Cursor shape enum.
pub const CursorShape = enum {
    block,
    underline,
    bar,
};

/// Cursor style value type.
pub const CursorStyle = struct {
    shape: CursorShape,
    blink: bool,
};

/// Default cursor style value.
pub const default_cursor_style = CursorStyle{ .shape = .block, .blink = true };

const selection_mod = @import("selection.zig");

/// Selection position re-export.
pub const SelectionPos = selection_mod.SelectionPos;

/// Terminal selection re-export.
pub const TerminalSelection = selection_mod.TerminalSelection;

/// Cell value type.
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

/// Return whether cell is a continuation fragment.
pub fn isCellContinuation(cell: Cell) bool {
    return cell.x != 0 or cell.y != 0;
}

/// Return whether cell is a multi-row root.
pub fn isMultiRowCellRoot(cell: Cell) bool {
    return cell.height > 1 and cell.x == 0 and cell.y == 0;
}

/// Cell attribute value type.
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

/// Color value type.
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

/// Logical key identifier type.
pub const Key = u32;

/// Modifier bitset type.
pub const Modifier = u8;

/// Physical key identifier type.
pub const PhysicalKey = u32;

/// Optional alternate-key metadata.
pub const KeyboardAlternateMetadata = struct {
    physical_key: ?PhysicalKey = null,

    produced_text_utf8: ?[]const u8 = null,

    base_codepoint: ?u32 = null,
    shifted_codepoint: ?u32 = null,
    alternate_layout_codepoint: ?u32 = null,

    text_is_composed: bool = false,
};

/// Mouse button enum.
pub const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
};

/// Mouse event kind enum.
pub const MouseEventKind = enum(u8) {
    press,
    release,
    move,
    wheel,
};

/// Mouse event payload type.
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

/// Logical key constant.
pub const VTERM_KEY_NONE: Key = 0;

/// Logical key constant.
pub const VTERM_KEY_ENTER: Key = 1;

/// Logical key constant.
pub const VTERM_KEY_TAB: Key = 2;

/// Logical key constant.
pub const VTERM_KEY_BACKSPACE: Key = 3;

/// Logical key constant.
pub const VTERM_KEY_ESCAPE: Key = 4;

/// Logical key constant.
pub const VTERM_KEY_UP: Key = 5;

/// Logical key constant.
pub const VTERM_KEY_DOWN: Key = 6;

/// Logical key constant.
pub const VTERM_KEY_LEFT: Key = 7;

/// Logical key constant.
pub const VTERM_KEY_RIGHT: Key = 8;

/// Logical key constant.
pub const VTERM_KEY_INS: Key = 9;

/// Logical key constant.
pub const VTERM_KEY_DEL: Key = 10;

/// Logical key constant.
pub const VTERM_KEY_HOME: Key = 11;

/// Logical key constant.
pub const VTERM_KEY_END: Key = 12;

/// Logical key constant.
pub const VTERM_KEY_PAGEUP: Key = 13;

/// Logical key constant.
pub const VTERM_KEY_PAGEDOWN: Key = 14;

/// Logical key constant.
pub const VTERM_KEY_LEFT_SHIFT: Key = 15;

/// Logical key constant.
pub const VTERM_KEY_RIGHT_SHIFT: Key = 16;

/// Logical key constant.
pub const VTERM_KEY_LEFT_CTRL: Key = 17;

/// Logical key constant.
pub const VTERM_KEY_RIGHT_CTRL: Key = 18;

/// Logical key constant.
pub const VTERM_KEY_LEFT_ALT: Key = 19;

/// Logical key constant.
pub const VTERM_KEY_RIGHT_ALT: Key = 20;

/// Logical key constant.
pub const VTERM_KEY_LEFT_SUPER: Key = 21;

/// Logical key constant.
pub const VTERM_KEY_RIGHT_SUPER: Key = 22;

/// Logical key constant.
pub const VTERM_KEY_F1: Key = 23;

/// Logical key constant.
pub const VTERM_KEY_F2: Key = 24;

/// Logical key constant.
pub const VTERM_KEY_F3: Key = 25;

/// Logical key constant.
pub const VTERM_KEY_F4: Key = 26;

/// Logical key constant.
pub const VTERM_KEY_F5: Key = 27;

/// Logical key constant.
pub const VTERM_KEY_F6: Key = 28;

/// Logical key constant.
pub const VTERM_KEY_F7: Key = 29;

/// Logical key constant.
pub const VTERM_KEY_F8: Key = 30;

/// Logical key constant.
pub const VTERM_KEY_F9: Key = 31;

/// Logical key constant.
pub const VTERM_KEY_F10: Key = 32;

/// Logical key constant.
pub const VTERM_KEY_F11: Key = 33;

/// Logical key constant.
pub const VTERM_KEY_F12: Key = 34;

/// Modifier flag constant.
pub const VTERM_MOD_NONE: Modifier = 0;

/// Modifier flag constant.
pub const VTERM_MOD_SHIFT: Modifier = 1;

/// Modifier flag constant.
pub const VTERM_MOD_ALT: Modifier = 2;

/// Modifier flag constant.
pub const VTERM_MOD_CTRL: Modifier = 4;

/// Build default blank cell value.
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

/// Default foreground color.
pub const default_fg = Color{ .r = 220, .g = 220, .b = 220 };

/// Default background color.
pub const default_bg = Color{ .r = 24, .g = 25, .b = 33 };

/// Default underline color value.
pub const default_underline_color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

/// Default cell-attribute value.
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

/// Default cell value constant.
pub const default_cell = Cell{
    .codepoint = 0,
    .attrs = default_cell_attrs,
};
