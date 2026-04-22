//! Responsibility: maintain cursor and optional cell buffer state.
//! Ownership: screen state module.
//! Reason: apply semantic events deterministically with clamped boundaries.

const std = @import("std");
const semantic_mod = @import("../event/semantic.zig");

/// Semantic event alias applied by screen state.
pub const SemanticEvent = semantic_mod.SemanticEvent;

/// Cursor and optional cell-buffer state with deterministic clamped updates.
pub const ScreenState = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cells: ?[]u21,

    pub fn init(rows: u16, cols: u16) ScreenState {
        return .{ .rows = rows, .cols = cols, .cursor_row = 0, .cursor_col = 0, .cells = null };
    }

    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !ScreenState {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]u21 = if (size > 0) blk: {
            const buf = try allocator.alloc(u21, size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        return .{ .rows = rows, .cols = cols, .cursor_row = 0, .cursor_col = 0, .cells = cells };
    }

    pub fn deinit(self: *ScreenState, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
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
        }
    }

    fn writeCell(self: *ScreenState, cp: u21) void {
        if (self.cols == 0 or self.rows == 0) return;
        if (self.cells) |c| {
            c[@as(usize, self.cursor_row) * self.cols + self.cursor_col] = cp;
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
