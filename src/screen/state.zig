//! Responsibility: maintain cursor and optional cell buffer state.
//! Ownership: screen state module.
//! Reason: apply semantic events deterministically with clamped boundaries.

const std = @import("std");
const semantic_mod = @import("../event/semantic.zig");

/// Semantic event alias applied by screen state.
pub const SemanticEvent = semantic_mod.SemanticEvent;

/// RGB color type alias.
const Rgb = semantic_mod.Rgb;

/// Cursor and optional cell-buffer state with deterministic clamped updates.
const CellAttr = struct {
    bold: bool = false,
    dim: bool = false,
    underline: bool = false,
    blink: bool = false,
    inverse: bool = false,
    strikethrough: bool = false,
    fg: u8 = 0,
    bg: u8 = 0,
    fg_rgb: ?Rgb = null,
    bg_rgb: ?Rgb = null,
};

pub const ScreenState = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cells: ?[]u21,
    cells_attr: ?[]CellAttr,
    current_bold: bool,
    current_dim: bool = false,
    current_underline: bool = false,
    current_blink: bool = false,
    current_inverse: bool = false,
    current_strikethrough: bool = false,
    current_fg: u8,
    current_bg: u8,
    current_fg_rgb: ?Rgb = null,
    current_bg_rgb: ?Rgb = null,

    pub fn init(rows: u16, cols: u16) ScreenState {
        return .{
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .cells = null,
            .cells_attr = null,
            .current_bold = false,
            .current_dim = false,
            .current_underline = false,
            .current_blink = false,
            .current_inverse = false,
            .current_strikethrough = false,
            .current_fg = 0,
            .current_bg = 0,
            .current_fg_rgb = null,
            .current_bg_rgb = null,
        };
    }

    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !ScreenState {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]u21 = if (size > 0) blk: {
            const buf = try allocator.alloc(u21, size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const cells_attr: ?[]CellAttr = if (size > 0) blk: {
            const buf = try allocator.alloc(CellAttr, size);
            @memset(buf, .{ .bold = false, .dim = false, .underline = false, .blink = false, .inverse = false, .strikethrough = false, .fg = 0, .bg = 0, .fg_rgb = null, .bg_rgb = null });
            break :blk buf;
        } else null;
        return .{
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .cells = cells,
            .cells_attr = cells_attr,
            .current_bold = false,
            .current_dim = false,
            .current_underline = false,
            .current_blink = false,
            .current_inverse = false,
            .current_strikethrough = false,
            .current_fg = 0,
            .current_bg = 0,
            .current_fg_rgb = null,
            .current_bg_rgb = null,
        };
    }

    pub fn deinit(self: *ScreenState, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        if (self.cells_attr) |ca| allocator.free(ca);
        self.cells = null;
        self.cells_attr = null;
    }

    pub fn cellAt(self: *const ScreenState, row: u16, col: u16) u21 {
        const c = self.cells orelse return 0;
        if (row >= self.rows or col >= self.cols) return 0;
        return c[@as(usize, row) * self.cols + col];
    }

    pub fn apply(self: *ScreenState, event: SemanticEvent) void {
        switch (event) {
            .cursor_up => |n| self.cursor_row = self.cursor_row -| n,
            .cursor_down => |n| self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1),
            .cursor_forward => |n| self.cursor_col = @min(self.cursor_col +| n, self.cols -| 1),
            .cursor_back => |n| self.cursor_col = self.cursor_col -| n,
            .cursor_position => |pos| {
                self.cursor_row = @min(pos.row, self.rows -| 1);
                self.cursor_col = @min(pos.col, self.cols -| 1);
            },
            .write_text => |s| {
                for (s) |byte| {
                    self.writeCell(@intCast(byte));
                }
            },
            .write_codepoint => |cp| self.writeCell(cp),
            .line_feed => self.cursor_row = @min(self.cursor_row +| 1, self.rows -| 1),
            .carriage_return => self.cursor_col = 0,
            .backspace => self.cursor_col = self.cursor_col -| 1,
            .erase_display => |mode| self.eraseDisplay(mode),
            .erase_line => |mode| self.eraseLine(mode),
            .style_reset => {
                self.current_bold = false;
                self.current_dim = false;
                self.current_underline = false;
                self.current_blink = false;
                self.current_inverse = false;
                self.current_strikethrough = false;
                self.current_fg = 0;
                self.current_bg = 0;
                self.current_fg_rgb = null;
                self.current_bg_rgb = null;
            },
            .style_bold_on => self.current_bold = true,
            .style_bold_off => self.current_bold = false,
            .style_dim_on => self.current_dim = true,
            .style_dim_off => self.current_dim = false,
            .style_strikethrough_on => self.current_strikethrough = true,
            .style_strikethrough_off => self.current_strikethrough = false,
            .style_underline_on => self.current_underline = true,
            .style_underline_off => self.current_underline = false,
            .style_blink_on => self.current_blink = true,
            .style_blink_off => self.current_blink = false,
            .style_inverse_on => self.current_inverse = true,
            .style_inverse_off => self.current_inverse = false,
            .style_fg_color => |color| self.current_fg = color,
            .style_bg_color => |color| self.current_bg = color,
            .style_fg_256 => |color| self.current_fg = color,
            .style_bg_256 => |color| self.current_bg = color,
            .style_fg_rgb => |rgb| self.current_fg_rgb = rgb,
            .style_bg_rgb => |rgb| self.current_bg_rgb = rgb,
            .style_operations => |batch| {
                var i: u8 = 0;
                while (i < batch.count) : (i += 1) {
                    const op = batch.ops[i];
                    switch (op) {
                        .reset => {
                            self.current_bold = false;
                            self.current_dim = false;
                            self.current_underline = false;
                            self.current_blink = false;
                            self.current_inverse = false;
                            self.current_strikethrough = false;
                            self.current_fg = 0;
                            self.current_bg = 0;
                            self.current_fg_rgb = null;
                            self.current_bg_rgb = null;
                        },
                        .bold_on => self.current_bold = true,
                        .bold_off => self.current_bold = false,
                        .dim_on => self.current_dim = true,
                        .dim_off => self.current_dim = false,
                        .strikethrough_on => self.current_strikethrough = true,
                        .strikethrough_off => self.current_strikethrough = false,
                        .underline_on => self.current_underline = true,
                        .underline_off => self.current_underline = false,
                        .blink_on => self.current_blink = true,
                        .blink_off => self.current_blink = false,
                        .inverse_on => self.current_inverse = true,
                        .inverse_off => self.current_inverse = false,
                        .fg_color => |color| self.current_fg = color,
                        .bg_color => |color| self.current_bg = color,
                        .fg_256 => |color| self.current_fg = color,
                        .bg_256 => |color| self.current_bg = color,
                        .fg_rgb => |rgb| self.current_fg_rgb = rgb,
                        .bg_rgb => |rgb| self.current_bg_rgb = rgb,
                    }
                }
            },
        }
    }

    fn eraseDisplay(self: *ScreenState, mode: u2) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        const cursor_pos = @as(usize, self.cursor_row) * self.cols + self.cursor_col;
        const default_attr: CellAttr = .{ .bold = false, .dim = false, .underline = false, .blink = false, .inverse = false, .strikethrough = false, .fg = 0, .bg = 0, .fg_rgb = null, .bg_rgb = null };
        switch (mode) {
            0 => {
                @memset(c[cursor_pos..], 0);
                if (self.cells_attr) |ca| @memset(ca[cursor_pos..], default_attr);
            },
            1 => {
                @memset(c[0 .. cursor_pos + 1], 0);
                if (self.cells_attr) |ca| @memset(ca[0 .. cursor_pos + 1], default_attr);
            },
            2 => {
                @memset(c, 0);
                if (self.cells_attr) |ca| @memset(ca, default_attr);
            },
            3 => {},
        }
    }

    fn eraseLine(self: *ScreenState, mode: u2) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        const row_start = @as(usize, self.cursor_row) * self.cols;
        const default_attr: CellAttr = .{ .bold = false, .dim = false, .underline = false, .blink = false, .inverse = false, .strikethrough = false, .fg = 0, .bg = 0, .fg_rgb = null, .bg_rgb = null };
        switch (mode) {
            0 => {
                @memset(c[row_start + self.cursor_col .. row_start + self.cols], 0);
                if (self.cells_attr) |ca| @memset(ca[row_start + self.cursor_col .. row_start + self.cols], default_attr);
            },
            1 => {
                @memset(c[row_start .. row_start + self.cursor_col + 1], 0);
                if (self.cells_attr) |ca| @memset(ca[row_start .. row_start + self.cursor_col + 1], default_attr);
            },
            2 => {
                @memset(c[row_start .. row_start + self.cols], 0);
                if (self.cells_attr) |ca| @memset(ca[row_start .. row_start + self.cols], default_attr);
            },
            3 => {},
        }
    }

    fn writeCell(self: *ScreenState, cp: u21) void {
        if (self.cols == 0 or self.rows == 0) return;
        const offset = @as(usize, self.cursor_row) * self.cols + self.cursor_col;
        if (self.cells) |c| {
            c[offset] = cp;
        }
        if (self.cells_attr) |ca| {
            ca[offset] = .{
                .bold = self.current_bold,
                .dim = self.current_dim,
                .underline = self.current_underline,
                .blink = self.current_blink,
                .inverse = self.current_inverse,
                .strikethrough = self.current_strikethrough,
                .fg = self.current_fg,
                .bg = self.current_bg,
                .fg_rgb = self.current_fg_rgb,
                .bg_rgb = self.current_bg_rgb,
            };
        }
        if (self.cursor_col < self.cols - 1) {
            self.cursor_col += 1;
        }
    }
};

test "screen: initial cursor at origin" {
    const s = ScreenState.init(24, 80);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: cursor_up moves row" {
    var s = ScreenState.init(24, 80);
    s.cursor_row = 5;
    s.apply(SemanticEvent{ .cursor_up = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
}

test "screen: cursor_up clamped at 0" {
    var s = ScreenState.init(24, 80);
    s.cursor_row = 1;
    s.apply(SemanticEvent{ .cursor_up = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
}

test "screen: cursor_down clamped at last row" {
    var s = ScreenState.init(24, 80);
    s.cursor_row = 20;
    s.apply(SemanticEvent{ .cursor_down = 10 });
    try std.testing.expectEqual(@as(u16, 23), s.cursor_row);
}

test "screen: cursor_forward clamped at last col" {
    var s = ScreenState.init(24, 80);
    s.cursor_col = 75;
    s.apply(SemanticEvent{ .cursor_forward = 10 });
    try std.testing.expectEqual(@as(u16, 79), s.cursor_col);
}

test "screen: cursor_position absolute move" {
    var s = ScreenState.init(24, 80);
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 10, .col = 40 } });
    try std.testing.expectEqual(@as(u16, 10), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 40), s.cursor_col);
}

test "screen: zero rows/cols do not panic" {
    var s = ScreenState.init(0, 0);
    s.apply(SemanticEvent{ .cursor_down = 5 });
    s.apply(SemanticEvent{ .cursor_forward = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
}

test "screen: write_text stores bytes in cells" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abc" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
}

test "screen: write_text clamped at last col" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcdefgh" });
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'h'), s.cellAt(0, 4));
}

test "screen: line_feed advances row" {
    var s = ScreenState.init(4, 10);
    s.cursor_row = 1;
    s.apply(SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
}

test "screen: carriage_return resets col" {
    var s = ScreenState.init(4, 10);
    s.cursor_col = 7;
    s.apply(SemanticEvent.carriage_return);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: backspace moves col left" {
    var s = ScreenState.init(4, 10);
    s.cursor_col = 5;
    s.apply(SemanticEvent.backspace);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
}

test "screen: cellAt out of bounds returns 0" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(10, 0));
}

test "screen: erase_line mode 0 clears from cursor to end of line" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "helloworld" });
    s.cursor_col = 5;
    s.apply(SemanticEvent{ .erase_line = 0 });
    try std.testing.expectEqual(@as(u21, 'h'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 9));
    try std.testing.expectEqual(@as(u16, 5), s.cursor_col);
}

test "screen: erase_line mode 1 clears from start to cursor" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "helloworld" });
    s.cursor_col = 4;
    s.apply(SemanticEvent{ .erase_line = 1 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'w'), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
}

test "screen: erase_line mode 2 clears full line" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "helloworld" });
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .erase_line = 2 });
    for (0..10) |i| {
        try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, @intCast(i)));
    }
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
}

test "screen: erase_display mode 0 clears from cursor to end of screen" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor_row = 0; s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "AAAAA" });
    s.cursor_row = 1; s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "BBBBB" });
    s.cursor_row = 2; s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "CCCCC" });
    s.cursor_row = 1; s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_display = 0 });
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "screen: erase_display mode 1 clears from start to cursor" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor_row = 0; s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "AAAAA" });
    s.cursor_row = 1; s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "BBBBB" });
    s.cursor_row = 2; s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "CCCCC" });
    s.cursor_row = 1; s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_display = 1 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "screen: erase_display mode 2 clears entire screen" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor_row = 1; s.cursor_col = 2;
    s.apply(SemanticEvent{ .write_text = "AB" });
    s.cursor_row = 1; s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_display = 2 });
    for (0..3) |r| {
        for (0..5) |c_| {
            try std.testing.expectEqual(@as(u21, 0), s.cellAt(@intCast(r), @intCast(c_)));
        }
    }
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "screen: erase ops no-op without cell buffer" {
    var s = ScreenState.init(4, 10);
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .erase_line = 2 });
    s.apply(SemanticEvent{ .erase_display = 2 });
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
}

test "screen: style_bold_on applies to written cell" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent{ .write_text = "a" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    const attr = s.cells_attr.?[0];
    try std.testing.expectEqual(true, attr.bold);
}

test "screen: style_fg_color applies to written cell" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .style_fg_color = 2 });
    s.apply(SemanticEvent{ .write_text = "x" });
    const attr = s.cells_attr.?[0];
    try std.testing.expectEqual(@as(u8, 2), attr.fg);
}

test "screen: style_reset clears all style state" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent.style_dim_on);
    s.apply(SemanticEvent.style_underline_on);
    s.apply(SemanticEvent.style_blink_on);
    s.apply(SemanticEvent.style_inverse_on);
    s.apply(SemanticEvent.style_strikethrough_on);
    s.apply(SemanticEvent{ .style_fg_color = 3 });
    s.apply(SemanticEvent{ .style_bg_color = 5 });
    s.apply(SemanticEvent.style_reset);
    try std.testing.expectEqual(false, s.current_bold);
    try std.testing.expectEqual(false, s.current_dim);
    try std.testing.expectEqual(false, s.current_underline);
    try std.testing.expectEqual(false, s.current_blink);
    try std.testing.expectEqual(false, s.current_inverse);
    try std.testing.expectEqual(false, s.current_strikethrough);
    try std.testing.expectEqual(@as(u8, 0), s.current_fg);
    try std.testing.expectEqual(@as(u8, 0), s.current_bg);
}

test "screen: multiple writes preserve style across cells" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent{ .style_fg_color = 4 });
    s.apply(SemanticEvent{ .write_text = "abc" });
    for (0..3) |i| {
        const attr = s.cells_attr.?[i];
        try std.testing.expectEqual(true, attr.bold);
        try std.testing.expectEqual(@as(u8, 4), attr.fg);
    }
}

test "screen: style_bold_off disables bold" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent{ .write_text = "a" });
    s.apply(SemanticEvent.style_bold_off);
    s.apply(SemanticEvent{ .write_text = "b" });
    try std.testing.expectEqual(true, s.cells_attr.?[0].bold);
    try std.testing.expectEqual(false, s.cells_attr.?[1].bold);
}

test "screen: style reset with default values" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent.style_reset);
    s.apply(SemanticEvent{ .write_text = "x" });
    const attr = s.cells_attr.?[0];
    try std.testing.expectEqual(false, attr.bold);
    try std.testing.expectEqual(@as(u8, 0), attr.fg);
    try std.testing.expectEqual(@as(u8, 0), attr.bg);
}

test "screen: no cell attributes without cell buffer" {
    var s = ScreenState.init(4, 10);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent{ .write_text = "a" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    try std.testing.expectEqual(true, s.current_bold);
}

test "screen: color 8 (white) preserved without truncation" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .style_fg_color = 8 });
    s.apply(SemanticEvent{ .write_text = "w" });
    try std.testing.expectEqual(@as(u8, 8), s.cells_attr.?[0].fg);
}

test "screen: background color 8 preserved" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .style_bg_color = 8 });
    s.apply(SemanticEvent{ .write_text = "w" });
    try std.testing.expectEqual(@as(u8, 8), s.cells_attr.?[0].bg);
}

test "screen: color reset (0) distinct from white (8)" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .style_fg_color = 8 });
    s.apply(SemanticEvent{ .write_text = "w" });
    s.apply(SemanticEvent{ .style_fg_color = 0 });
    s.apply(SemanticEvent{ .write_text = "d" });
    try std.testing.expectEqual(@as(u8, 8), s.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 0), s.cells_attr.?[1].fg);
}

test "screen: erase_line mode 0 clears attributes" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent{ .style_fg_color = 4 });
    s.apply(SemanticEvent{ .write_text = "styled" });
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_line = 0 });
    try std.testing.expectEqual(true, s.cells_attr.?[0].bold);
    try std.testing.expectEqual(true, s.cells_attr.?[1].bold);
    try std.testing.expectEqual(false, s.cells_attr.?[2].bold);
    try std.testing.expectEqual(@as(u8, 0), s.cells_attr.?[2].fg);
}

test "screen: erase_display mode 2 clears all attributes" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent{ .style_fg_color = 5 });
    s.apply(SemanticEvent{ .write_text = "text" });
    s.apply(SemanticEvent{ .erase_display = 2 });
    for (0..15) |i| {
        const attr = s.cells_attr.?[i];
        try std.testing.expectEqual(false, attr.bold);
        try std.testing.expectEqual(@as(u8, 0), attr.fg);
    }
}

test "screen: write with fg 256-color persists" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .style_fg_256 = 196 });
    s.apply(SemanticEvent{ .write_text = "red" });
    try std.testing.expectEqual(@as(u8, 196), s.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 196), s.cells_attr.?[1].fg);
    try std.testing.expectEqual(@as(u8, 196), s.cells_attr.?[2].fg);
}

test "screen: write with bg 256-color persists" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .style_bg_256 = 21 });
    s.apply(SemanticEvent{ .write_text = "bg" });
    try std.testing.expectEqual(@as(u8, 21), s.cells_attr.?[0].bg);
    try std.testing.expectEqual(@as(u8, 21), s.cells_attr.?[1].bg);
}

test "screen: style_dim_on applies to written cell" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_dim_on);
    s.apply(SemanticEvent{ .write_text = "d" });
    try std.testing.expectEqual(true, s.cells_attr.?[0].dim);
}

test "screen: style_dim_off disables dim on next write" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_dim_on);
    s.apply(SemanticEvent{ .write_text = "a" });
    s.apply(SemanticEvent.style_dim_off);
    s.apply(SemanticEvent{ .write_text = "b" });
    try std.testing.expectEqual(true, s.cells_attr.?[0].dim);
    try std.testing.expectEqual(false, s.cells_attr.?[1].dim);
}

test "screen: style_strikethrough_on applies to written cell" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_strikethrough_on);
    s.apply(SemanticEvent{ .write_text = "s" });
    try std.testing.expectEqual(true, s.cells_attr.?[0].strikethrough);
}

test "screen: style_strikethrough_off disables strikethrough on next write" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_strikethrough_on);
    s.apply(SemanticEvent{ .write_text = "a" });
    s.apply(SemanticEvent.style_strikethrough_off);
    s.apply(SemanticEvent{ .write_text = "b" });
    try std.testing.expectEqual(true, s.cells_attr.?[0].strikethrough);
    try std.testing.expectEqual(false, s.cells_attr.?[1].strikethrough);
}

test "screen: style_blink_on applies to written cell" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_blink_on);
    s.apply(SemanticEvent{ .write_text = "b" });
    try std.testing.expectEqual(true, s.cells_attr.?[0].blink);
}

test "screen: style_blink_off disables blink on next write" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_blink_on);
    s.apply(SemanticEvent{ .write_text = "a" });
    s.apply(SemanticEvent.style_blink_off);
    s.apply(SemanticEvent{ .write_text = "b" });
    try std.testing.expectEqual(true, s.cells_attr.?[0].blink);
    try std.testing.expectEqual(false, s.cells_attr.?[1].blink);
}

test "screen: style_operations blink_off clears blink flag" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_blink_on);
    var ops: [16]semantic_mod.StyleOp = undefined;
    @memset(&ops, semantic_mod.StyleOp.reset);
    ops[0] = .blink_off;
    s.apply(SemanticEvent{ .style_operations = .{ .ops = ops, .count = 1 } });
    s.apply(SemanticEvent{ .write_text = "x" });
    try std.testing.expectEqual(false, s.cells_attr.?[0].blink);
}

test "screen: style_operations bold_off and dim_off clear both flags" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent.style_bold_on);
    s.apply(SemanticEvent.style_dim_on);
    var ops: [16]semantic_mod.StyleOp = undefined;
    @memset(&ops, semantic_mod.StyleOp.reset);
    ops[0] = .bold_off;
    ops[1] = .dim_off;
    s.apply(SemanticEvent{ .style_operations = .{ .ops = ops, .count = 2 } });
    s.apply(SemanticEvent{ .write_text = "x" });
    try std.testing.expectEqual(false, s.cells_attr.?[0].bold);
    try std.testing.expectEqual(false, s.cells_attr.?[0].dim);
}
