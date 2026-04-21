const std = @import("std");
const pipeline_mod = @import("terminal/parser_core_event_pipeline.zig");
const screen_mod = @import("terminal/terminal_screen_state.zig");

fn feed(pl: *pipeline_mod.Pipeline, screen: *screen_mod.ScreenState, bytes: []const u8) void {
    pl.feedSlice(bytes);
    pl.applyToScreen(screen);
}

fn feedByte(pl: *pipeline_mod.Pipeline, screen: *screen_mod.ScreenState, byte: u8) void {
    pl.feedByte(byte);
    pl.applyToScreen(screen);
}

test "replay: CUU moves cursor up" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 10;

    feed(&pl, &screen, "\x1b[3A");

    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
}

test "replay: CUD moves cursor down" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 5;

    feed(&pl, &screen, "\x1b[4B");

    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "replay: CUF moves cursor forward" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_col = 10;

    feed(&pl, &screen, "\x1b[5C");

    try std.testing.expectEqual(@as(u16, 15), screen.cursor_col);
}

test "replay: CUB moves cursor back" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_col = 20;

    feed(&pl, &screen, "\x1b[6D");

    try std.testing.expectEqual(@as(u16, 14), screen.cursor_col);
}

test "replay: CUP absolute move" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);

    feed(&pl, &screen, "\x1b[5;20H");

    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "replay: CUP no params moves to origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 10;
    screen.cursor_col = 40;

    feed(&pl, &screen, "\x1b[H");

    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: split CSI across multiple feeds" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 10;

    pl.feedSlice("\x1b[");
    pl.feedSlice("2");
    pl.feedSlice("A");
    pl.applyToScreen(&screen);

    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
}

test "replay: reset clears events and screen reflects only post-reset input" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 10;

    pl.feedSlice("\x1b[5A");
    pl.reset();
    pl.applyToScreen(&screen);

    try std.testing.expectEqual(@as(u16, 10), screen.cursor_row);

    feed(&pl, &screen, "\x1b[2B");
    try std.testing.expectEqual(@as(u16, 12), screen.cursor_row);
}

test "replay: invalid UTF-8 does not corrupt cursor state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 5;
    screen.cursor_col = 10;

    feed(&pl, &screen, "\x80\xFE");

    try std.testing.expectEqual(@as(u16, 5), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 10), screen.cursor_col);
}

test "replay: unsupported CSI does not corrupt cursor state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 5;
    screen.cursor_col = 10;

    feed(&pl, &screen, "\x1b[1m\x1b[0m");

    try std.testing.expectEqual(@as(u16, 5), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 10), screen.cursor_col);
}

test "replay: clamping at screen boundaries" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);

    feed(&pl, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);

    feed(&pl, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 23), screen.cursor_row);

    feed(&pl, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);

    feed(&pl, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 79), screen.cursor_col);
}

test "replay: sequence of moves composes correctly" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);

    feed(&pl, &screen, "\x1b[10;10H");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);

    feed(&pl, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);

    feed(&pl, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 14), screen.cursor_col);

    feed(&pl, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: plain text feed writes to screen cells" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "hello");

    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'o'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "replay: mixed CSI cursor move then text write" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "\x1b[2;5Hhi");

    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(1, 4));
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAt(1, 5));
}

test "replay: CR resets column leaving row unchanged" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "abc\x0Dxy");

    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 1));
}

test "replay: LF advances row" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "ab\x0Acd");

    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(1, 2));
}

test "replay: CR+LF writes to start of next row" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "abc\x0D\x0Adef");

    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(1, 0));
}

test "replay: BS moves cursor left without erasing cell" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "abc\x08");

    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
}

test "replay: split text feed across multiple calls" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    pl.feedSlice("fo");
    pl.applyToScreen(&screen);
    pl.feedSlice("o");
    pl.applyToScreen(&screen);

    try std.testing.expectEqual(@as(u21, 'f'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'o'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'o'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
}

test "replay: UTF-8 codepoint written to cell" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "\xC3\xA9");

    try std.testing.expectEqual(@as(u21, 0xE9), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
}

test "replay: invalid UTF-8 does not corrupt existing text state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "ab");
    feed(&pl, &screen, "\x80\xFE");
    feed(&pl, &screen, "cd");

    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(0, 3));
}

test "replay: reset clears bridge events; screen state unchanged by reset" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "abc");
    pl.feedSlice("xyz");
    pl.reset();
    pl.applyToScreen(&screen);

    // reset discards buffered events; only 'abc' was written
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
}

test "replay: unsupported CSI does not alter cell content or cursor" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "ab");
    feed(&pl, &screen, "\x1b[1m\x1b[0m");

    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "replay: multi-line text via CR+LF sequence" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);

    feed(&pl, &screen, "row0\x0D\x0Arow1\x0D\x0Arow2");

    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, '2'), screen.cellAt(2, 3));
}
