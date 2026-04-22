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
const runtime_mod = @import("../runtime/engine.zig");

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

test "replay: pipeline clear drops pending bridge events before apply" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    pl.feedSlice("dropped");
    try std.testing.expect(pl.len() > 0);
    pl.clear();
    try std.testing.expect(pl.isEmpty());
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: pipeline reset clears queued events and partial CSI" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 12, 40);
    defer screen.deinit(gpa);
    screen.cursor_row = 10;
    screen.cursor_col = 0;
    pl.feedSlice("x\x1b[3");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    pl.reset();
    try std.testing.expect(pl.isEmpty());
    pl.feedSlice("A");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 10), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(10, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(10, 1));
}

test "replay: applyToScreen drains bridge once repeat apply is no-op" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    pl.feedSlice("\x1b[4C");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expect(pl.isEmpty());
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    pl.feedSlice("z");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u21, 'z'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
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

test "replay: CUP alternate final f positions cursor" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    feed(&pl, &screen, "\x1b[4;7f");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_col);
}

test "replay: CSI J mode 2 erases full screen" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 4);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "AAAA");
    feed(&pl, &screen, "\x0D\x0A");
    feed(&pl, &screen, "BBBB");
    feed(&pl, &screen, "\x1b[H\x1b[2J");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 3));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CSI J mode 1 erases through cursor inclusive" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 3, 4);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "AAAA");
    feed(&pl, &screen, "\x0D\x0A");
    feed(&pl, &screen, "BBBB");
    feed(&pl, &screen, "\x0D\x0A");
    feed(&pl, &screen, "CCCC");
    screen.cursor_row = 1;
    screen.cursor_col = 2;
    feed(&pl, &screen, "\x1b[1J");
    try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 2));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "replay: CSI K mode 1 erases line start through cursor" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 6);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abcdef");
    screen.cursor_col = 2;
    feed(&pl, &screen, "\x1b[1K");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'f'), screen.cellAt(0, 5));
}

test "replay: CSI K mode 2 erases entire current line" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "hello");
    feed(&pl, &screen, "\x1b[2;1H");
    feed(&pl, &screen, "world");
    feed(&pl, &screen, "\x1b[1;1H");
    feed(&pl, &screen, "\x1b[2K");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CSI J invalid param maps to mode 0 through end of screen" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 4);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "AAAA");
    feed(&pl, &screen, "\x0D\x0A");
    feed(&pl, &screen, "BBBB");
    screen.cursor_row = 0;
    screen.cursor_col = 1;
    feed(&pl, &screen, "\x1b[9J");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
}

test "replay: split CSI erase across parser feeds" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 1, 5);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "hello");
    screen.cursor_col = 2;
    pl.feedSlice("\x1b[");
    pl.feedSlice("1K");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 3));
}

test "replay: control BEL does not move cursor or alter cells" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "ab\x07c");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
}

// --- Edge determinism tests: cursor/control saturation at boundaries ---

test "edge: CUU repeated moves from top clamps at row 0" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 3;
    feed(&pl, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    feed(&pl, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    feed(&pl, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&pl, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&pl, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
}

test "edge: CUD repeated moves from bottom clamps at last row" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(10, 80);
    screen.cursor_row = 7;
    feed(&pl, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
    feed(&pl, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    feed(&pl, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    feed(&pl, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "edge: CUF repeated moves from right clamps at last column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 12);
    screen.cursor_col = 10;
    feed(&pl, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
}

test "edge: CUB repeated moves from left clamps at column 0" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_col = 3;
    feed(&pl, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: mixed cursor moves (up/down/left/right) maintain saturation at edges" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(8, 8);
    feed(&pl, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&pl, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    feed(&pl, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    feed(&pl, &screen, "\x1b[5A\x1b[2C");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    feed(&pl, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
}

// --- Edge determinism tests: CR/LF/BS interaction on edges ---

test "edge: CR at column 0 leaves cursor unchanged" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 2;
    screen.cursor_col = 0;
    feed(&pl, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: LF at bottom row clamps at last row" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 5, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 4;
    screen.cursor_col = 5;
    feed(&pl, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&pl, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    feed(&pl, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "edge: BS at column 0 clamps at column 0" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 1;
    screen.cursor_col = 0;
    feed(&pl, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: CR then LF sequences from edge positions" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 5, 10);
    defer screen.deinit(gpa);
    screen.cursor_col = 9;
    screen.cursor_row = 0;
    feed(&pl, &screen, "\x0D\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    screen.cursor_row = 4;
    feed(&pl, &screen, "\x0D\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "edge: BS then CUB sequence does not corrupt cursor" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_col = 5;
    feed(&pl, &screen, "\x08\x08\x08\x08\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[3D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x08\x08\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: CR does not move row; LF only moves row; BS only moves column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 8, 15);
    defer screen.deinit(gpa);
    screen.cursor_row = 3;
    screen.cursor_col = 10;
    feed(&pl, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

// --- Edge determinism tests: zero-dimension screens remain safe ---

test "edge: zero-dimension pipeline clear and reset are safe" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(0, 0);
    pl.feedSlice("test\x1b[5A");
    pl.clear();
    try std.testing.expect(pl.isEmpty());
    pl.applyToScreen(&screen);
    pl.feedSlice("more\x1b[1B");
    pl.reset();
    try std.testing.expect(pl.isEmpty());
    pl.applyToScreen(&screen);
}

// --- Zero-dimension variant tests (rows=0, cols>0 | rows>0, cols=0 | rows=0, cols=0) ---

test "zero-dim: rows=0, cols=8: cursor moves saturate, text/erase are safe no-ops" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(0, 8);
    feed(&pl, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&pl, &screen, "\x1b[3D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&pl, &screen, "hello");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&pl, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "zero-dim: rows=8, cols=0: cursor moves saturate, text/erase are safe no-ops" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(8, 0);
    feed(&pl, &screen, "\x1b[3B");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "text");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=0: all cursor moves saturate at origin, text/erase safe" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(0, 0);
    feed(&pl, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "xyz");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[2J");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=8: CR/LF/BS control sequence determinism" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(0, 8);
    screen.cursor_col = 5;
    feed(&pl, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[3C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    feed(&pl, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "zero-dim: rows=8, cols=0: CR/LF/BS control sequence determinism" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(8, 0);
    screen.cursor_row = 3;
    feed(&pl, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=0: CUP absolute position saturates at origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(0, 0);
    feed(&pl, &screen, "\x1b[999;999H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=10: repeated erase operations remain safe" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(0, 10);
    screen.cursor_col = 5;
    feed(&pl, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&pl, &screen, "\x1b[2K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&pl, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&pl, &screen, "\x1b[1J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&pl, &screen, "\x1b[2J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "zero-dim: rows=10, cols=0: repeated text writes remain safe" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(10, 0);
    screen.cursor_row = 3;
    feed(&pl, &screen, "test");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\xC3\xA9");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "more");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

// --- Runtime engine facade parity matrix ---

const CellCheck = struct {
    row: u16,
    col: u16,
    codepoint: u21,
};

const ParityScenario = struct {
    name: []const u8,
    rows: u16,
    cols: u16,
    with_cells: bool,
    input: []const u8,
    expected_row: u16,
    expected_col: u16,
    expected_queue_depth: usize,
    check_cells: bool = false,
    cell_checks: []const CellCheck = &.{},
};

const ParityChunkScenario = struct {
    name: []const u8,
    rows: u16,
    cols: u16,
    with_cells: bool,
    chunks: []const []const u8,
    expected_row: u16,
    expected_col: u16,
    expected_queue_depth: usize,
    check_cells: bool = false,
    cell_checks: []const CellCheck = &.{},
};

fn runParityScenario(gpa: std.mem.Allocator, scenario: ParityScenario) !void {
    var direct_pl = try pipeline_mod.Pipeline.init(gpa);
    defer direct_pl.deinit();
    var direct_screen = if (scenario.with_cells)
        try screen_mod.ScreenState.initWithCells(gpa, scenario.rows, scenario.cols)
    else
        screen_mod.ScreenState.init(scenario.rows, scenario.cols);
    defer if (scenario.with_cells) direct_screen.deinit(gpa);

    var runtime_engine = if (scenario.with_cells)
        try runtime_mod.Engine.initWithCells(gpa, scenario.rows, scenario.cols)
    else
        try runtime_mod.Engine.init(gpa, scenario.rows, scenario.cols);
    defer runtime_engine.deinit();

    direct_pl.feedSlice(scenario.input);
    direct_pl.applyToScreen(&direct_screen);

    runtime_engine.feedSlice(scenario.input);
    runtime_engine.apply();

    try std.testing.expectEqual(scenario.expected_row, direct_screen.cursor_row);
    try std.testing.expectEqual(scenario.expected_row, runtime_engine.screen().cursor_row);
    try std.testing.expectEqual(scenario.expected_col, direct_screen.cursor_col);
    try std.testing.expectEqual(scenario.expected_col, runtime_engine.screen().cursor_col);
    try std.testing.expectEqual(scenario.expected_queue_depth, direct_pl.len());
    try std.testing.expectEqual(scenario.expected_queue_depth, runtime_engine.queuedEventCount());

    if (scenario.check_cells) {
        for (scenario.cell_checks) |check| {
            const direct_cell = direct_screen.cellAt(check.row, check.col);
            const runtime_cell = runtime_engine.screen().cellAt(check.row, check.col);
            try std.testing.expectEqual(direct_cell, check.codepoint);
            try std.testing.expectEqual(runtime_cell, check.codepoint);
        }
    }
}

fn runParityChunkScenario(gpa: std.mem.Allocator, scenario: ParityChunkScenario) !void {
    var direct_pl = try pipeline_mod.Pipeline.init(gpa);
    defer direct_pl.deinit();
    var direct_screen = if (scenario.with_cells)
        try screen_mod.ScreenState.initWithCells(gpa, scenario.rows, scenario.cols)
    else
        screen_mod.ScreenState.init(scenario.rows, scenario.cols);
    defer if (scenario.with_cells) direct_screen.deinit(gpa);

    var runtime_engine = if (scenario.with_cells)
        try runtime_mod.Engine.initWithCells(gpa, scenario.rows, scenario.cols)
    else
        try runtime_mod.Engine.init(gpa, scenario.rows, scenario.cols);
    defer runtime_engine.deinit();

    for (scenario.chunks) |chunk| {
        direct_pl.feedSlice(chunk);
        runtime_engine.feedSlice(chunk);
    }
    direct_pl.applyToScreen(&direct_screen);
    runtime_engine.apply();

    try std.testing.expectEqual(scenario.expected_row, direct_screen.cursor_row);
    try std.testing.expectEqual(scenario.expected_row, runtime_engine.screen().cursor_row);
    try std.testing.expectEqual(scenario.expected_col, direct_screen.cursor_col);
    try std.testing.expectEqual(scenario.expected_col, runtime_engine.screen().cursor_col);
    try std.testing.expectEqual(scenario.expected_queue_depth, direct_pl.len());
    try std.testing.expectEqual(scenario.expected_queue_depth, runtime_engine.queuedEventCount());

    if (scenario.check_cells) {
        for (scenario.cell_checks) |check| {
            const direct_cell = direct_screen.cellAt(check.row, check.col);
            const runtime_cell = runtime_engine.screen().cellAt(check.row, check.col);
            try std.testing.expectEqual(direct_cell, check.codepoint);
            try std.testing.expectEqual(runtime_cell, check.codepoint);
        }
    }
}

test "parity: CUU moves cursor up identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUU baseline",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[5A",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: CUD moves cursor down identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUD baseline",
        .rows = 10,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[3B",
        .expected_row = 3,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: CUF moves cursor forward identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUF baseline",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[10C",
        .expected_row = 0,
        .expected_col = 10,
        .expected_queue_depth = 0,
    });
}

test "parity: CUB moves cursor back identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUB from position",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[20C\x1b[5D",
        .expected_row = 0,
        .expected_col = 15,
        .expected_queue_depth = 0,
    });
}

test "parity: CUP absolute position identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUP absolute",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[10;20H",
        .expected_row = 9,
        .expected_col = 19,
        .expected_queue_depth = 0,
    });
}

test "parity: CUP alternate final 'f' identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUP with f",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[5;10f",
        .expected_row = 4,
        .expected_col = 9,
        .expected_queue_depth = 0,
    });
}

test "parity: CR resets column identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CR resets column",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[10C\x0D",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: LF advances row identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "LF advances row",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x0A\x0A\x0A",
        .expected_row = 3,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: BS moves left identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "BS moves left",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[15C\x08\x08\x08",
        .expected_row = 0,
        .expected_col = 12,
        .expected_queue_depth = 0,
    });
}

test "parity: CRLF sequence identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CRLF combo",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[5C\x0D\x0A\x1b[3C",
        .expected_row = 1,
        .expected_col = 3,
        .expected_queue_depth = 0,
    });
}

test "parity: erase-line mode 0 (to end) identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "EL mode 0",
        .rows = 4,
        .cols = 20,
        .with_cells = true,
        .input = "hello\x1b[2D\x1b[K",
        .expected_row = 0,
        .expected_col = 3,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'h' },
            .{ .row = 0, .col = 1, .codepoint = 'e' },
            .{ .row = 0, .col = 2, .codepoint = 'l' },
            .{ .row = 0, .col = 3, .codepoint = 0 },
        },
    });
}

test "parity: erase-line mode 1 (from start) identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "EL mode 1",
        .rows = 4,
        .cols = 20,
        .with_cells = true,
        .input = "hello\x1b[2D\x1b[1K",
        .expected_row = 0,
        .expected_col = 3,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 0 },
            .{ .row = 0, .col = 3, .codepoint = 0 },
            .{ .row = 0, .col = 4, .codepoint = 'o' },
        },
    });
}

test "parity: erase-line mode 2 (full line) identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "EL mode 2",
        .rows = 4,
        .cols = 20,
        .with_cells = true,
        .input = "test\x1b[2K",
        .expected_row = 0,
        .expected_col = 4,
        .expected_queue_depth = 0,
    });
}

test "parity: erase-display mode 0 (to end) identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "ED mode 0",
        .rows = 3,
        .cols = 5,
        .with_cells = true,
        .input = "AAAAA\x0D\x0ABBBBB\x0D\x0ACCCCC\x1b[1;2H\x1b[J",
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'A' },
            .{ .row = 0, .col = 1, .codepoint = 0 },
            .{ .row = 1, .col = 0, .codepoint = 0 },
            .{ .row = 2, .col = 0, .codepoint = 0 },
        },
    });
}

test "parity: erase-display mode 2 (full) identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "ED mode 2",
        .rows = 3,
        .cols = 5,
        .with_cells = true,
        .input = "AAAAA\x0D\x0ABBBBB\x0D\x0ACCCCC\x1b[2J",
        .expected_row = 2,
        .expected_col = 4,
        .expected_queue_depth = 0,
    });
}

test "parity: split CSI across feeds identically" {
    const gpa = std.testing.allocator;
    var direct_pl = try pipeline_mod.Pipeline.init(gpa);
    defer direct_pl.deinit();
    var direct_screen = screen_mod.ScreenState.init(24, 80);

    var runtime_engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer runtime_engine.deinit();

    direct_pl.feedSlice("\x1b[");
    direct_pl.feedSlice("5");
    direct_pl.feedSlice("C");
    direct_pl.applyToScreen(&direct_screen);

    runtime_engine.feedSlice("\x1b[");
    runtime_engine.feedSlice("5");
    runtime_engine.feedSlice("C");
    runtime_engine.apply();

    try std.testing.expectEqual(direct_screen.cursor_col, runtime_engine.screen().cursor_col);
}

test "parity: text write with cells identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "text write",
        .rows = 4,
        .cols = 20,
        .with_cells = true,
        .input = "hello",
        .expected_row = 0,
        .expected_col = 5,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'h' },
            .{ .row = 0, .col = 1, .codepoint = 'e' },
            .{ .row = 0, .col = 2, .codepoint = 'l' },
            .{ .row = 0, .col = 3, .codepoint = 'l' },
            .{ .row = 0, .col = 4, .codepoint = 'o' },
        },
    });
}

test "parity: text wrap and bottom scroll identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "text wrap and scroll",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .input = "abcdefghijk",
        .expected_row = 1,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'f' },
            .{ .row = 0, .col = 4, .codepoint = 'j' },
            .{ .row = 1, .col = 0, .codepoint = 'k' },
            .{ .row = 1, .col = 1, .codepoint = 0 },
        },
    });
}

test "parity: UTF-8 codepoint identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "UTF-8 write",
        .rows = 4,
        .cols = 20,
        .with_cells = true,
        .input = "\xC3\xA9",
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 0xE9 },
        },
    });
}

test "parity: zero-dim rows=0 identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "zero-dim rows=0",
        .rows = 0,
        .cols = 10,
        .with_cells = false,
        .input = "text\x1b[5C\x1b[3A",
        .expected_row = 0,
        .expected_col = 5,
        .expected_queue_depth = 0,
    });
}

test "parity: zero-dim cols=0 identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "zero-dim cols=0",
        .rows = 10,
        .cols = 0,
        .with_cells = false,
        .input = "text\x1b[5B\x1b[3D",
        .expected_row = 5,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: zero-dim rows=0 cols=0 identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "zero-dim 0×0",
        .rows = 0,
        .cols = 0,
        .with_cells = false,
        .input = "test\x1b[999A\x1b[999C\x1b[J",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: invalid erase mode maps to 0 identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "invalid J mode->0",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .input = "AAAAA\x0D\x0ABBBBB\x1b[9J",
        .expected_row = 1,
        .expected_col = 4,
        .expected_queue_depth = 0,
    });
}

test "parity: mixed sequence identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "mixed complex",
        .rows = 5,
        .cols = 15,
        .with_cells = true,
        .input = "line1\x0D\x0Aline2\x1b[2;5H",
        .expected_row = 1,
        .expected_col = 4,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'l' },
            .{ .row = 1, .col = 0, .codepoint = 'l' },
            .{ .row = 1, .col = 4, .codepoint = '2' },
        },
    });
}

test "parity: OSC BEL title event ignored by screen state identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "OSC BEL ignored",
        .rows = 2,
        .cols = 10,
        .with_cells = true,
        .input = "ab\x1b]title\x07cd",
        .expected_row = 0,
        .expected_col = 4,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 0, .col = 2, .codepoint = 'c' },
            .{ .row = 0, .col = 3, .codepoint = 'd' },
        },
    });
}

test "parity: APC payload is dropped and screen remains deterministic" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "APC dropped",
        .rows = 2,
        .cols = 10,
        .with_cells = true,
        .input = "ab\x1b_payload\x1b\\cd",
        .expected_row = 0,
        .expected_col = 4,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 0, .col = 2, .codepoint = 'c' },
            .{ .row = 0, .col = 3, .codepoint = 'd' },
        },
    });
}

test "parity: DCS payload is dropped and screen remains deterministic" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "DCS dropped",
        .rows = 2,
        .cols = 10,
        .with_cells = true,
        .input = "ab\x1bPpayload\x1b\\cd",
        .expected_row = 0,
        .expected_col = 4,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 0, .col = 2, .codepoint = 'c' },
            .{ .row = 0, .col = 3, .codepoint = 'd' },
        },
    });
}

test "parity: ESC final passthrough is dropped at bridge seam" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "ESC final dropped",
        .rows = 2,
        .cols = 10,
        .with_cells = true,
        .input = "ab\x1bMcd",
        .expected_row = 0,
        .expected_col = 4,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 0, .col = 2, .codepoint = 'c' },
            .{ .row = 0, .col = 3, .codepoint = 'd' },
        },
    });
}

test "parity: non-mapped controls are ignored while mapped controls apply" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "control filtering",
        .rows = 3,
        .cols = 10,
        .with_cells = true,
        .input = "a\x07b\x0bc\x0A",
        .expected_row = 1,
        .expected_col = 3,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 0, .col = 2, .codepoint = 'c' },
        },
    });
}

test "parity: horizontal tab advances to default stops identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "horizontal tab",
        .rows = 3,
        .cols = 20,
        .with_cells = true,
        .input = "a\x09b",
        .expected_row = 0,
        .expected_col = 9,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 8, .codepoint = 'b' },
        },
    });
}

test "parity-chunked: UTF-8 split decode with CRLF remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked utf8 + CRLF",
        .rows = 3,
        .cols = 10,
        .with_cells = true,
        .chunks = &.{ "\xC3", "\xA9", "\x0D", "\x0A" },
        .expected_row = 1,
        .expected_col = 0,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 0xE9 },
        },
    });
}

test "parity-chunked: CSI erase split into byte fragments remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CSI erase",
        .rows = 2,
        .cols = 6,
        .with_cells = true,
        .chunks = &.{ "hello", "\x1b", "[", "1", "K" },
        .expected_row = 0,
        .expected_col = 5,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 0 },
            .{ .row = 0, .col = 4, .codepoint = 0 },
        },
    });
}

test "parity-chunked: OSC BEL split across chunks is ignored identically" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked OSC BEL ignored",
        .rows = 2,
        .cols = 10,
        .with_cells = true,
        .chunks = &.{ "ab", "\x1b]", "ti", "tle", "\x07", "cd" },
        .expected_row = 0,
        .expected_col = 4,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 0, .col = 2, .codepoint = 'c' },
            .{ .row = 0, .col = 3, .codepoint = 'd' },
        },
    });
}

test "parity-chunked: OSC ST split across chunks is ignored identically" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked OSC ST ignored",
        .rows = 2,
        .cols = 10,
        .with_cells = true,
        .chunks = &.{ "ab", "\x1b]title", "\x1b", "\\", "cd" },
        .expected_row = 0,
        .expected_col = 4,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 0, .col = 2, .codepoint = 'c' },
            .{ .row = 0, .col = 3, .codepoint = 'd' },
        },
    });
}

test "parity-chunked: mixed control and cursor stream remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked mixed control",
        .rows = 3,
        .cols = 10,
        .with_cells = true,
        .chunks = &.{ "ab\x0D", "\x0A\x1b[2C", "cd\x08" },
        .expected_row = 1,
        .expected_col = 3,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 1, .codepoint = 'b' },
            .{ .row = 1, .col = 2, .codepoint = 'c' },
            .{ .row = 1, .col = 3, .codepoint = 'd' },
        },
    });
}

// --- Runtime engine facade tests ---

test "runtime: init and deinit lifecycle" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    try std.testing.expectEqual(@as(u16, 24), engine.screen().rows);
    try std.testing.expectEqual(@as(u16, 80), engine.screen().cols);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: initWithCells and deinit with allocated cells" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 4, 20);
    defer engine.deinit();
    try std.testing.expectEqual(@as(u16, 4), engine.screen().rows);
    try std.testing.expectEqual(@as(u16, 20), engine.screen().cols);
    try std.testing.expect(engine.screen().cells != null);
    try std.testing.expectEqual(@as(u21, 0), engine.screen().cellAt(0, 0));
}

test "runtime: feedByte and feedSlice accumulate in queue" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    engine.feedByte('A');
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
    engine.feedSlice("BC");
    try std.testing.expectEqual(@as(usize, 2), engine.queuedEventCount());
}

test "runtime: apply drains queue and updates screen" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 4, 20);
    defer engine.deinit();
    engine.feedSlice("hello");
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
    engine.apply();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expectEqual(@as(u21, 'h'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'o'), engine.screen().cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_col);
}

test "runtime: clear drops pending events" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("text\x1b[5A");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.clear();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
}

test "runtime: reset clears queue and parser state" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("abc\x1b[");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.reset();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    engine.feedSlice("xyz");
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
}

test "runtime: resetScreen clears screen without clearing queued parser events" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 5);
    defer engine.deinit();
    engine.feedSlice("abcde");
    engine.apply();
    try std.testing.expectEqual(@as(u21, 'a'), engine.screen().cellAt(0, 0));
    engine.feedSlice("z");
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
    engine.resetScreen();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 0), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
    engine.apply();
    try std.testing.expectEqual(@as(u21, 'z'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: cursor move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[5;10H");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 4), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 9), engine.screen().cursor_col);
}

test "runtime: text write and erase via apply" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 4, 20);
    defer engine.deinit();
    engine.feedSlice("hello");
    engine.apply();
    try std.testing.expectEqual(@as(u21, 'h'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_col);
    engine.feedSlice("\x1b[K");
    engine.apply();
    try std.testing.expectEqual(@as(u21, 0), engine.screen().cellAt(0, 5));
}

test "runtime: repeated apply without feed is no-op" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 4, 20);
    defer engine.deinit();
    engine.feedSlice("test");
    engine.apply();
    const col1 = engine.screen().cursor_col;
    engine.apply();
    try std.testing.expectEqual(col1, engine.screen().cursor_col);
    engine.apply();
    try std.testing.expectEqual(col1, engine.screen().cursor_col);
}

test "runtime: zero-dimension init is safe" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 0, 0);
    defer engine.deinit();
    engine.feedSlice("text\x1b[5A\x1b[999C\x1b[J");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
}

test "runtime: queuedEventCount after clear is zero" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[1m\x1b[31mtext");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.clear();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: queuedEventCount after reset is zero" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("abc\x1b[31m");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.reset();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: queuedEventCount after apply is zero" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("hello\x1b[5A");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.apply();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: feed after clear accumulates new events" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("old");
    engine.clear();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    engine.feedSlice("new");
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
}

test "runtime: complex sequence with cursor/text/erase" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 15);
    defer engine.deinit();
    engine.feedSlice("line0");
    engine.apply();
    engine.feedSlice("\x0D\x0A");
    engine.apply();
    engine.feedSlice("line1");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 1), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'l'), engine.screen().cellAt(1, 0));
}
