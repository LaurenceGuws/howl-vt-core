//! Responsibility: screen state behavior and edge-case tests.
//! Ownership: screen mutation conformance verification.
//! Reason: keep production screen module free from embedded test bulk.

const std = @import("std");
const screen_mod = @import("../screen/state.zig");
const semantic_mod = @import("../event/semantic.zig");

const ScreenState = screen_mod.ScreenState;
const SemanticEvent = semantic_mod.SemanticEvent;
test "screen: initial cursor at origin" {
    const s = ScreenState.init(24, 80);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: reset clears cursor wrap and cells" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcdef" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    s.reset();
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
    try std.testing.expect(s.cursor_visible);
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
}

test "screen: cursor_visible mode toggles without moving cursor" {
    var s = ScreenState.init(2, 5);
    s.cursor_row = 1;
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .cursor_visible = false });
    try std.testing.expect(!s.cursor_visible);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
    s.apply(SemanticEvent{ .cursor_visible = true });
    try std.testing.expect(s.cursor_visible);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
}

test "screen: auto_wrap mode toggles and does not move cursor" {
    var s = ScreenState.init(2, 5);
    s.cursor_row = 1;
    s.cursor_col = 4;
    s.apply(SemanticEvent{ .auto_wrap = false });
    try std.testing.expect(!s.auto_wrap);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
    s.apply(SemanticEvent{ .auto_wrap = true });
    try std.testing.expect(s.auto_wrap);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
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

test "screen: cursor_next_line moves row and resets column" {
    var s = ScreenState.init(24, 80);
    s.cursor_row = 5;
    s.cursor_col = 40;
    s.apply(SemanticEvent{ .cursor_next_line = 3 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: cursor_prev_line moves row and resets column" {
    var s = ScreenState.init(24, 80);
    s.cursor_row = 5;
    s.cursor_col = 40;
    s.apply(SemanticEvent{ .cursor_prev_line = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: cursor_horizontal_absolute updates column only" {
    var s = ScreenState.init(24, 80);
    s.cursor_row = 12;
    s.cursor_col = 20;
    s.apply(SemanticEvent{ .cursor_horizontal_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 12), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor_col);
}

test "screen: cursor_vertical_absolute updates row only" {
    var s = ScreenState.init(24, 80);
    s.cursor_row = 12;
    s.cursor_col = 20;
    s.apply(SemanticEvent{ .cursor_vertical_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 7), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 20), s.cursor_col);
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

test "screen: write_text wraps to next row after filled column" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcdefgh" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'h'), s.cellAt(1, 2));
}

test "screen: exact line fill leaves cursor at last column until next write" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcde" });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 4));
    s.apply(SemanticEvent{ .write_text = "f" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(1, 0));
}

test "screen: wrap at bottom scrolls cell buffer up" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcde" });
    s.apply(SemanticEvent{ .write_text = "fghij" });
    s.apply(SemanticEvent{ .write_text = "k" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'j'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'k'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
}

test "screen: disabled auto_wrap keeps writing at last column" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .auto_wrap = false });
    s.apply(SemanticEvent{ .write_text = "abcdefg" });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'd'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'g'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
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

test "screen: horizontal_tab advances to next default tab stop" {
    var s = ScreenState.init(4, 20);
    s.cursor_col = 3;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 8), s.cursor_col);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 16), s.cursor_col);
}

test "screen: horizontal_tab clamps at last column" {
    var s = ScreenState.init(4, 20);
    s.cursor_col = 17;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 19), s.cursor_col);
}

test "screen: horizontal_tab_forward advances by requested stop count" {
    var s = ScreenState.init(4, 20);
    s.cursor_col = 1;
    s.apply(SemanticEvent{ .horizontal_tab_forward = 2 });
    try std.testing.expectEqual(@as(u16, 16), s.cursor_col);
}

test "screen: horizontal_tab_forward clamps at last column" {
    var s = ScreenState.init(4, 20);
    s.cursor_col = 17;
    s.apply(SemanticEvent{ .horizontal_tab_forward = 2 });
    try std.testing.expectEqual(@as(u16, 19), s.cursor_col);
}

test "screen: horizontal_tab_back moves to previous default tab stop" {
    var s = ScreenState.init(4, 20);
    s.cursor_col = 17;
    s.apply(SemanticEvent{ .horizontal_tab_back = 2 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor_col);
}

test "screen: horizontal_tab_back clamps at column zero" {
    var s = ScreenState.init(4, 20);
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .horizontal_tab_back = 2 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
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
    s.cursor_row = 0;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "AAAAA" });
    s.cursor_row = 1;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "BBBBB" });
    s.cursor_row = 2;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "CCCCC" });
    s.cursor_row = 1;
    s.cursor_col = 2;
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
    s.cursor_row = 0;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "AAAAA" });
    s.cursor_row = 1;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "BBBBB" });
    s.cursor_row = 2;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "CCCCC" });
    s.cursor_row = 1;
    s.cursor_col = 2;
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
    s.cursor_row = 1;
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .write_text = "AB" });
    s.cursor_row = 1;
    s.cursor_col = 2;
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

test "screen: initWithCells has no history by default" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u16, 0), s.history_capacity);
    try std.testing.expect(s.history == null);
}

test "screen: initWithCellsAndHistory allocates bounded history" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCellsAndHistory(gpa, 4, 10, 100);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u16, 100), s.history_capacity);
    try std.testing.expect(s.history != null);
    try std.testing.expectEqual(@as(u16, 0), s.history_count);
}

test "screen: scrollUp captures row to history" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCellsAndHistory(gpa, 2, 10, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abc" });
    s.cursor_row = 1;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "xyz" });
    s.cursor_col = 0;
    s.apply(SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(u16, 1), s.history_count);
    const h = s.history.?;
    try std.testing.expectEqual(@as(u21, 'a'), h[0]);
    try std.testing.expectEqual(@as(u21, 'b'), h[1]);
    try std.testing.expectEqual(@as(u21, 'c'), h[2]);
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'z'), s.cellAt(0, 2));
}

test "screen: history capacity limits with wraparound" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCellsAndHistory(gpa, 2, 2, 2);
    defer s.deinit(gpa);
    var row_num: u21 = '1';
    var i: u16 = 0;
    while (i < 5) : (i += 1) {
        s.cursor_col = 0;
        s.cursor_row = 0;
        for (0..2) |_| {
            s.apply(SemanticEvent{ .write_codepoint = row_num });
        }
        if (i < 4) {
            s.cursor_row = 1;
            s.apply(SemanticEvent.line_feed);
        }
        row_num += 1;
    }
    try std.testing.expectEqual(@as(u16, 2), s.history_count);
    try std.testing.expectEqual(@as(u21, '4'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, '4'), s.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, '3'), s.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, '3'), s.historyRowAt(1, 1));
}

test "screen: reset does not truncate history" {
    const gpa = std.testing.allocator;
    var s = try ScreenState.initWithCellsAndHistory(gpa, 2, 5, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "test1" });
    s.cursor_row = 1;
    s.apply(SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(u16, 1), s.history_count);
    s.reset();
    try std.testing.expectEqual(@as(u16, 1), s.history_count);
}
