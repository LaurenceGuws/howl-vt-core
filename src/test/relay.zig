//! Responsibility: run integration relay tests across parser, event, and screen modules.
//! Ownership: terminal test integration module.
//! Reason: verify cross-module behavior beyond isolated inline unit tests.

const std = @import("std");
const parser_mod = @import("../parser/parser.zig");
const stream_mod = @import("../parser/stream.zig");
const csi_mod = @import("../parser/csi.zig");
const bridge_mod = @import("../event/bridge.zig");
const pipeline_mod = @import("../event/pipeline.zig");
const screen_mod = @import("../screen/state.zig");

// --- Dispatch harness ---

const Event = union(enum) {
    stream_codepoint: u21,
    stream_control: u8,
    stream_invalid,
    ascii_slice: []const u8,
    csi: struct { final: u8, params: [16]i32, count: u8 },
    osc: struct { data: []const u8, term: parser_mod.OscTerminator },
    apc: []const u8,
    dcs: []const u8,
    esc_final: u8,
};

const Harness = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),

    fn init(allocator: std.mem.Allocator) Harness {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(Event).initCapacity(allocator, 16) catch unreachable,
        };
    }

    fn deinit(self: *Harness) void {
        for (self.events.items) |event| {
            switch (event) {
                .ascii_slice => |data| self.allocator.free(data),
                .osc => |osc_ev| self.allocator.free(osc_ev.data),
                .apc => |data| self.allocator.free(data),
                .dcs => |data| self.allocator.free(data),
                else => {},
            }
        }
        self.events.deinit(self.allocator);
    }

    fn toSink(self: *Harness) parser_mod.Sink {
        return .{
            .ptr = self,
            .onStreamEventFn = onStreamEvent,
            .onAsciiSliceFn = onAsciiSlice,
            .onCsiFn = onCsi,
            .onOscFn = onOsc,
            .onApcFn = onApc,
            .onDcsFn = onDcs,
            .onEscFinalFn = onEscFinal,
        };
    }

    fn onStreamEvent(ptr: *anyopaque, event: stream_mod.StreamEvent) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const ev = switch (event) {
            .codepoint => |cp| Event{ .stream_codepoint = cp },
            .control => |ctrl| Event{ .stream_control = ctrl },
            .invalid => Event.stream_invalid,
        };
        self.events.append(self.allocator, ev) catch {};
    }

    fn onAsciiSlice(ptr: *anyopaque, bytes: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, bytes) catch return;
        self.events.append(self.allocator, Event{ .ascii_slice = owned }) catch {};
    }

    fn onCsi(ptr: *anyopaque, action: csi_mod.CsiAction) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, Event{ .csi = .{
            .final = action.final,
            .params = action.params,
            .count = action.count,
        } }) catch {};
    }

    fn onOsc(ptr: *anyopaque, data: []const u8, term: parser_mod.OscTerminator) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .osc = .{ .data = owned, .term = term } }) catch {};
    }

    fn onApc(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .apc = owned }) catch {};
    }

    fn onDcs(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .dcs = owned }) catch {};
    }

    fn onEscFinal(ptr: *anyopaque, byte: u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, Event{ .esc_final = byte }) catch {};
    }
};

// --- Parser dispatch tests ---

test "parser: mixed stream exact sequence (ASCII+CSI+ASCII)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("AB\x1b[31mC");
    try std.testing.expectEqual(@as(usize, 3), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .ascii_slice);
    try std.testing.expect(harness.events.items[1] == .csi);
    try std.testing.expectEqual(@as(u8, 'm'), harness.events.items[1].csi.final);
    try std.testing.expectEqual(@as(i32, 31), harness.events.items[1].csi.params[0]);
    try std.testing.expect(harness.events.items[2] == .ascii_slice);
}

test "parser: ESC final passthrough (ESC M)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1bM");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .esc_final);
    try std.testing.expectEqual(@as(u8, 'M'), harness.events.items[0].esc_final);
}

test "parser: OSC with BEL terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]title\x07");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqual(parser_mod.OscTerminator.bel, harness.events.items[0].osc.term);
    try std.testing.expectEqualSlices(u8, "title", harness.events.items[0].osc.data);
}

test "parser: OSC with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]url\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqual(parser_mod.OscTerminator.st, harness.events.items[0].osc.term);
    try std.testing.expectEqualSlices(u8, "url", harness.events.items[0].osc.data);
}

test "parser: APC with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b_kitty\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .apc);
    try std.testing.expectEqualSlices(u8, "kitty", harness.events.items[0].apc);
}

test "parser: DCS with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1bPdata\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .dcs);
    try std.testing.expectEqualSlices(u8, "data", harness.events.items[0].dcs);
}

test "parser: split input - partial UTF-8 then completion" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleByte(0xE2);
    parser.handleByte(0x82);
    parser.handleByte(0xAC);
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x20AC), harness.events.items[0].stream_codepoint);
}

test "parser: split input - partial CSI then final byte" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleByte(0x1B);
    parser.handleByte('[');
    parser.handleByte('3');
    parser.handleByte('1');
    parser.handleByte('m');
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .csi);
    try std.testing.expectEqual(@as(u8, 'm'), harness.events.items[0].csi.final);
    try std.testing.expectEqual(@as(i32, 31), harness.events.items[0].csi.params[0]);
}

test "parser: stray ESC in OSC (marker dropped, byte appended)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]ab\x1bcd\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqualSlices(u8, "abcd", harness.events.items[0].osc.data);
}

test "parser: CSI with multiple parameters exact order" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b[1;31;40m");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .csi);
    try std.testing.expectEqual(@as(i32, 1), harness.events.items[0].csi.params[0]);
    try std.testing.expectEqual(@as(i32, 31), harness.events.items[0].csi.params[1]);
    try std.testing.expectEqual(@as(i32, 40), harness.events.items[0].csi.params[2]);
    try std.testing.expectEqual(@as(u8, 3), harness.events.items[0].csi.count);
}

// --- Bridge integration tests ---

test "bridge: maps ASCII text to text event" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("hello");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", bridge.events.items[0].text);
}

test "bridge: maps UTF-8 codepoint to codepoint event" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\xC3\xA9");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), bridge.events.items[0].codepoint);
}

test "bridge: maps control byte to control event" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleByte(0x07);
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .control);
    try std.testing.expectEqual(@as(u8, 0x07), bridge.events.items[0].control);
}

test "bridge: maps CSI sequence to style_change event" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b[31m");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(u8, 'm'), bridge.events.items[0].style_change.final);
    try std.testing.expectEqual(@as(i32, 31), bridge.events.items[0].style_change.params[0]);
}

test "bridge: maps OSC to title_set event" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]My Window\x07");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .title_set);
    try std.testing.expectEqualSlices(u8, "My Window", bridge.events.items[0].title_set);
}

// --- Pipeline integration tests ---

test "pipeline: mixed text and CSI and text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    pl.feedSlice("hello\x1b[1mworld");
    try std.testing.expectEqual(@as(usize, 3), pl.len());
    try std.testing.expect(pl.events()[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", pl.events()[0].text);
    try std.testing.expect(pl.events()[1] == .style_change);
    try std.testing.expect(pl.events()[2] == .text);
    try std.testing.expectEqualSlices(u8, "world", pl.events()[2].text);
}

test "pipeline: reset clears events and parser state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    pl.feedSlice("abc\x1b[1m");
    try std.testing.expectEqual(@as(usize, 2), pl.len());
    pl.reset();
    try std.testing.expect(pl.isEmpty());
    pl.feedSlice("xyz");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expectEqualSlices(u8, "xyz", pl.events()[0].text);
}

test "pipeline: split CSI across feeds" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    pl.feedSlice("\x1b[");
    pl.feedSlice("31m");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .style_change);
    try std.testing.expectEqual(@as(i32, 31), pl.events()[0].style_change.params[0]);
}

test "pipeline: stray ESC in OSC dropped, byte appended" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    pl.feedSlice("\x1b]ti\x1btle\x07");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .title_set);
    try std.testing.expectEqualSlices(u8, "title", pl.events()[0].title_set);
}

// --- End-to-end replay tests (Pipeline + ScreenState) ---

fn feed(pl: *pipeline_mod.Pipeline, screen: *screen_mod.ScreenState, bytes: []const u8) void {
    pl.feedSlice(bytes);
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

test "replay: plain text feed writes to screen cells" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "hello");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
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

test "replay: CSI K erases from cursor to end of line" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "hello");
    screen.cursor_col = 2;
    feed(&pl, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "replay: CSI J erases from cursor to end of screen" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 3, 5);
    defer screen.deinit(gpa);
    screen.cursor_row = 0; screen.cursor_col = 0;
    feed(&pl, &screen, "AAAAA");
    screen.cursor_row = 1; screen.cursor_col = 0;
    feed(&pl, &screen, "BBBBB");
    screen.cursor_row = 2; screen.cursor_col = 0;
    feed(&pl, &screen, "CCCCC");
    screen.cursor_row = 1; screen.cursor_col = 2;
    feed(&pl, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(2, 0));
}

test "replay: cursor move then CSI K erase to end of line" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abcdef");
    feed(&pl, &screen, "\x1b[1;4H");
    feed(&pl, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 5));
}

test "replay: existing text and cursor paths unaffected by erase additions" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "hello\x0D\x0Aworld");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "replay: text then CSI m bold then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "plain");
    feed(&pl, &screen, "\x1b[1m");
    feed(&pl, &screen, "bold");
    try std.testing.expectEqual(false, screen.cells_attr.?[0].bold);
    try std.testing.expectEqual(false, screen.cells_attr.?[4].bold);
    try std.testing.expectEqual(true, screen.cells_attr.?[5].bold);
    try std.testing.expectEqual(true, screen.cells_attr.?[8].bold);
}

test "replay: text with fg color changes" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "red");
    feed(&pl, &screen, "\x1b[31m");
    feed(&pl, &screen, "green");
    feed(&pl, &screen, "\x1b[39m");
    feed(&pl, &screen, "none");
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 2), screen.cells_attr.?[3].fg);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[8].fg);
}

test "replay: style reset clears attributes" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[1m");
    feed(&pl, &screen, "\x1b[31m");
    feed(&pl, &screen, "styled");
    feed(&pl, &screen, "\x1b[0m");
    feed(&pl, &screen, "reset");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].bold);
    try std.testing.expectEqual(@as(u8, 2), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(false, screen.cells_attr.?[6].bold);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[6].fg);
}

test "replay: mixed cursor move and style and text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[1m");
    feed(&pl, &screen, "\x1b[31m");
    feed(&pl, &screen, "row0");
    feed(&pl, &screen, "\x1b[2;1H");
    feed(&pl, &screen, "row1");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expectEqual(true, screen.cells_attr.?[20].bold);
    try std.testing.expectEqual(@as(u8, 2), screen.cells_attr.?[20].fg);
}

test "replay: parser CSI 38;5;n then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[38;5;196m");
    feed(&pl, &screen, "red");
    try std.testing.expectEqual(@as(u8, 196), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 196), screen.cells_attr.?[1].fg);
    try std.testing.expectEqual(@as(u8, 196), screen.cells_attr.?[2].fg);
}

test "replay: parser CSI 48;5;n then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[48;5;21m");
    feed(&pl, &screen, "bg");
    try std.testing.expectEqual(@as(u8, 21), screen.cells_attr.?[0].bg);
    try std.testing.expectEqual(@as(u8, 21), screen.cells_attr.?[1].bg);
}

test "replay: mixed cursor and 256-color style" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[38;5;226m");
    feed(&pl, &screen, "yellow");
    feed(&pl, &screen, "\x1b[2;1H");
    feed(&pl, &screen, "next");
    try std.testing.expectEqual(@as(u8, 226), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 226), screen.cells_attr.?[20].fg);
}

test "replay: parser CSI 38;2;r;g;b foreground RGB then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[38;2;255;0;0m");
    feed(&pl, &screen, "rgb");
    try std.testing.expect(screen.cells_attr.?[0].fg_rgb != null);
    try std.testing.expectEqual(@as(u8, 255), screen.cells_attr.?[0].fg_rgb.?.r);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].fg_rgb.?.g);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].fg_rgb.?.b);
    try std.testing.expect(screen.cells_attr.?[1].fg_rgb != null);
    try std.testing.expect(screen.cells_attr.?[2].fg_rgb != null);
}

test "replay: parser CSI 48;2;r;g;b background RGB then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[48;2;0;255;0m");
    feed(&pl, &screen, "bgc");
    try std.testing.expect(screen.cells_attr.?[0].bg_rgb != null);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].bg_rgb.?.r);
    try std.testing.expectEqual(@as(u8, 255), screen.cells_attr.?[0].bg_rgb.?.g);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].bg_rgb.?.b);
}

test "replay: mixed indexed and RGB colors with cursor movement" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[38;5;196m");
    feed(&pl, &screen, "red");
    feed(&pl, &screen, "\x1b[38;2;0;255;0m");
    feed(&pl, &screen, "green");
    feed(&pl, &screen, "\x1b[1;1H");
    feed(&pl, &screen, "go");
    try std.testing.expectEqual(@as(u8, 196), screen.cells_attr.?[0].fg);
    try std.testing.expect(screen.cells_attr.?[3].fg_rgb != null);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[3].fg_rgb.?.r);
}

test "replay: malformed RGB sequence (incomplete) ignored safely" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[38;2;255m");
    feed(&pl, &screen, "x");
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].fg);
    try std.testing.expect(screen.cells_attr.?[0].fg_rgb == null);
}

test "replay: parser CSI 90 bright foreground black then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[90m");
    feed(&pl, &screen, "dark");
    try std.testing.expectEqual(@as(u8, 9), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 9), screen.cells_attr.?[3].fg);
}

test "replay: parser CSI 97 bright foreground white then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[97m");
    feed(&pl, &screen, "bright");
    try std.testing.expectEqual(@as(u8, 16), screen.cells_attr.?[0].fg);
}

test "replay: parser CSI 100 bright background black then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[100m");
    feed(&pl, &screen, "bg");
    try std.testing.expectEqual(@as(u8, 9), screen.cells_attr.?[0].bg);
}

test "replay: parser CSI 107 bright background white then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[107m");
    feed(&pl, &screen, "white");
    try std.testing.expectEqual(@as(u8, 16), screen.cells_attr.?[0].bg);
}

test "replay: mixed bright and RGB and reset" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[91m");
    feed(&pl, &screen, "br");
    feed(&pl, &screen, "\x1b[38;2;0;255;0m");
    feed(&pl, &screen, "gr");
    feed(&pl, &screen, "\x1b[0m");
    feed(&pl, &screen, "x");
    try std.testing.expectEqual(@as(u8, 10), screen.cells_attr.?[0].fg);
    try std.testing.expect(screen.cells_attr.?[2].fg_rgb != null);
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[4].fg);
    try std.testing.expect(screen.cells_attr.?[4].fg_rgb == null);
}

test "replay: malformed bright SGR does not corrupt subsequent valid style" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[99m");
    feed(&pl, &screen, "x");
    feed(&pl, &screen, "\x1b[92m");
    feed(&pl, &screen, "y");
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 11), screen.cells_attr.?[1].fg);
}

test "replay: parser CSI 4 underline on then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[4m");
    feed(&pl, &screen, "under");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].underline);
    try std.testing.expectEqual(true, screen.cells_attr.?[4].underline);
}

test "replay: parser CSI 24 underline off then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[4m");
    feed(&pl, &screen, "u1");
    feed(&pl, &screen, "\x1b[24m");
    feed(&pl, &screen, "u2");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].underline);
    try std.testing.expectEqual(false, screen.cells_attr.?[2].underline);
}

test "replay: parser CSI 7 inverse on then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[7m");
    feed(&pl, &screen, "inv");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].inverse);
    try std.testing.expectEqual(true, screen.cells_attr.?[2].inverse);
}

test "replay: parser CSI 27 inverse off then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[7m");
    feed(&pl, &screen, "i1");
    feed(&pl, &screen, "\x1b[27m");
    feed(&pl, &screen, "i2");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].inverse);
    try std.testing.expectEqual(false, screen.cells_attr.?[2].inverse);
}

test "replay: mixed style batch with bold underline and color" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[1;4;31m");
    feed(&pl, &screen, "bux");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].bold);
    try std.testing.expectEqual(true, screen.cells_attr.?[0].underline);
    try std.testing.expectEqual(@as(u8, 2), screen.cells_attr.?[0].fg);
}

test "replay: reset clears underline and inverse before next write" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[4;7m");
    feed(&pl, &screen, "s1");
    feed(&pl, &screen, "\x1b[0m");
    feed(&pl, &screen, "s2");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].underline);
    try std.testing.expectEqual(true, screen.cells_attr.?[0].inverse);
    try std.testing.expectEqual(false, screen.cells_attr.?[2].underline);
    try std.testing.expectEqual(false, screen.cells_attr.?[2].inverse);
}

test "replay: parser CSI 2 dim on then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[2m");
    feed(&pl, &screen, "dim");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].dim);
    try std.testing.expectEqual(true, screen.cells_attr.?[2].dim);
}

test "replay: parser CSI 22 clears bold and dim then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[1;2m");
    feed(&pl, &screen, "a");
    feed(&pl, &screen, "\x1b[22m");
    feed(&pl, &screen, "b");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].bold);
    try std.testing.expectEqual(true, screen.cells_attr.?[0].dim);
    try std.testing.expectEqual(false, screen.cells_attr.?[1].bold);
    try std.testing.expectEqual(false, screen.cells_attr.?[1].dim);
}

test "replay: parser CSI 9 strikethrough on then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[9m");
    feed(&pl, &screen, "strike");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].strikethrough);
    try std.testing.expectEqual(true, screen.cells_attr.?[5].strikethrough);
}

test "replay: parser CSI 29 strikethrough off then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[9m");
    feed(&pl, &screen, "a");
    feed(&pl, &screen, "\x1b[29m");
    feed(&pl, &screen, "b");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].strikethrough);
    try std.testing.expectEqual(false, screen.cells_attr.?[1].strikethrough);
}

test "replay: mixed style batch with dim strikethrough and color" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[2;9;32m");
    feed(&pl, &screen, "m");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].dim);
    try std.testing.expectEqual(true, screen.cells_attr.?[0].strikethrough);
    try std.testing.expectEqual(@as(u8, 3), screen.cells_attr.?[0].fg);
}

test "replay: malformed dim parameter does not corrupt subsequent valid style" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[5m");
    feed(&pl, &screen, "x");
    feed(&pl, &screen, "\x1b[2m");
    feed(&pl, &screen, "y");
    try std.testing.expectEqual(false, screen.cells_attr.?[0].dim);
    try std.testing.expectEqual(true, screen.cells_attr.?[1].dim);
}

test "replay: parser CSI 5 blink on then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[5m");
    feed(&pl, &screen, "on");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].blink);
    try std.testing.expectEqual(true, screen.cells_attr.?[1].blink);
}

test "replay: parser CSI 25 blink off affects subsequent text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[5m");
    feed(&pl, &screen, "a");
    feed(&pl, &screen, "\x1b[25m");
    feed(&pl, &screen, "b");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].blink);
    try std.testing.expectEqual(false, screen.cells_attr.?[1].blink);
}

test "replay: mixed style batch with blink color and underline" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[5;31;4m");
    feed(&pl, &screen, "m");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].blink);
    try std.testing.expectEqual(@as(u8, 2), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(true, screen.cells_attr.?[0].underline);
}

test "replay: reset clears blink for following writes" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[5m");
    feed(&pl, &screen, "a");
    feed(&pl, &screen, "\x1b[0m");
    feed(&pl, &screen, "b");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].blink);
    try std.testing.expectEqual(false, screen.cells_attr.?[1].blink);
}

test "replay: malformed style params do not block subsequent valid blink" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[38;2;255m");
    feed(&pl, &screen, "x");
    feed(&pl, &screen, "\x1b[5m");
    feed(&pl, &screen, "y");
    try std.testing.expectEqual(false, screen.cells_attr.?[0].blink);
    try std.testing.expectEqual(true, screen.cells_attr.?[1].blink);
}

test "replay: underline with indexed underline color then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[4m");
    feed(&pl, &screen, "\x1b[58;5;123m");
    feed(&pl, &screen, "u");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].underline);
    try std.testing.expectEqual(@as(?u8, 123), screen.cells_attr.?[0].underline_color);
    try std.testing.expect(screen.cells_attr.?[0].underline_color_rgb == null);
}

test "replay: underline with rgb underline color then text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[4m");
    feed(&pl, &screen, "\x1b[58;2;9;8;7m");
    feed(&pl, &screen, "u");
    try std.testing.expectEqual(true, screen.cells_attr.?[0].underline);
    try std.testing.expectEqual(@as(?u8, null), screen.cells_attr.?[0].underline_color);
    try std.testing.expect(screen.cells_attr.?[0].underline_color_rgb != null);
    try std.testing.expectEqual(@as(u8, 9), screen.cells_attr.?[0].underline_color_rgb.?.r);
}

test "replay: reset clears underline color before following text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[4;58;5;33m");
    feed(&pl, &screen, "a");
    feed(&pl, &screen, "\x1b[0m");
    feed(&pl, &screen, "b");
    try std.testing.expectEqual(@as(?u8, 33), screen.cells_attr.?[0].underline_color);
    try std.testing.expectEqual(@as(?u8, null), screen.cells_attr.?[1].underline_color);
}

test "replay: malformed 58 does not block subsequent valid style" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[58;2;255m");
    feed(&pl, &screen, "x");
    feed(&pl, &screen, "\x1b[4;58;5;77m");
    feed(&pl, &screen, "y");
    try std.testing.expectEqual(@as(?u8, null), screen.cells_attr.?[0].underline_color);
    try std.testing.expectEqual(true, screen.cells_attr.?[1].underline);
    try std.testing.expectEqual(@as(?u8, 77), screen.cells_attr.?[1].underline_color);
}

test "replay: mixed ordered underline color style batch continuity" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[4;58;5;81m");
    feed(&pl, &screen, "a");
    feed(&pl, &screen, "\x1b[59m");
    feed(&pl, &screen, "b");
    feed(&pl, &screen, "\x1b[58;2;1;2;3m");
    feed(&pl, &screen, "c");
    try std.testing.expectEqual(@as(?u8, 81), screen.cells_attr.?[0].underline_color);
    try std.testing.expectEqual(@as(?u8, null), screen.cells_attr.?[1].underline_color);
    try std.testing.expect(screen.cells_attr.?[2].underline_color_rgb != null);
    try std.testing.expectEqual(@as(u8, 1), screen.cells_attr.?[2].underline_color_rgb.?.r);
}

test "replay: long mixed SGR chain remains stable under cap" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 40);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[1;4;7;38;5;196;58;5;120;22;24;27;31;48;2;1;2;3m");
    feed(&pl, &screen, "x");
    const attr = screen.cells_attr.?[0];
    try std.testing.expectEqual(false, attr.bold);
    try std.testing.expectEqual(false, attr.underline);
    try std.testing.expectEqual(false, attr.inverse);
    try std.testing.expectEqual(@as(u8, 2), attr.fg);
    try std.testing.expect(attr.bg_rgb == null);
    try std.testing.expectEqual(@as(u8, 120), attr.underline_color.?);
}

test "replay: style chain beyond op cap truncates deterministically" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 40);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[1;22;22;22;22;22;22;22;22;31m");
    feed(&pl, &screen, "x");
    const attr = screen.cells_attr.?[0];
    try std.testing.expectEqual(false, attr.bold);
    try std.testing.expectEqual(false, attr.dim);
    try std.testing.expectEqual(@as(u8, 0), attr.fg);
}

test "replay: malformed and overflow sequence recovers for following writes" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 40);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "\x1b[1;22;22;22;22;22;22;22;22;31m");
    feed(&pl, &screen, "\x1b[38;2;255m");
    feed(&pl, &screen, "a");
    feed(&pl, &screen, "\x1b[32m");
    feed(&pl, &screen, "b");
    try std.testing.expectEqual(@as(u8, 0), screen.cells_attr.?[0].fg);
    try std.testing.expectEqual(@as(u8, 3), screen.cells_attr.?[1].fg);
}
