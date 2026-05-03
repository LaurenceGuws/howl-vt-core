//! Responsibility: define terminal grid value types and defaults.
//! Ownership: grid data shape authority.
//! Reason: keep visible cell/cursor/color schema near the grid model.

const selection_owner = @import("../selection.zig");

const Selection = selection_owner.Selection;

const CursorPos = struct {
    row: usize,
    col: usize,
};

const CursorShape = enum {
    block,
    underline,
    bar,
};

const CursorStyle = struct {
    shape: CursorShape,
    blink: bool,
};

const default_cursor_style = CursorStyle{ .shape = .block, .blink = true };

const SelectionPos = Selection.SelectionPos;
const TerminalSelection = Selection.TerminalSelection;

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

const CellAttrs = struct {
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

const Cell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [2]u32 = .{ 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    attrs: CellAttrs,
};

fn isCellContinuation(cell: Cell) bool {
    return cell.x != 0 or cell.y != 0;
}

fn isMultiRowCellRoot(cell: Cell) bool {
    return cell.height > 1 and cell.x == 0 and cell.y == 0;
}

const default_fg = Color{ .r = 220, .g = 220, .b = 220 };
const default_bg = Color{ .r = 24, .g = 25, .b = 33 };
const default_underline_color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

const default_cell_attrs = CellAttrs{
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

const default_cell = Cell{
    .codepoint = 0,
    .attrs = default_cell_attrs,
};

fn defaultCell() Cell {
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
