const std = @import("std");
const parser_mod = @import("../parser/parser.zig");
const stream_mod = @import("../parser/stream.zig");
const csi_mod = @import("../parser/csi.zig");
const bridge_mod = @import("../event/bridge.zig");
const pipeline_mod = @import("../event/pipeline.zig");
const screen_mod = @import("../screen/state.zig");
const runtime_mod = @import("../runtime/engine.zig");
const model_mod = @import("../model.zig");

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

test "bridge: preserves CSI leader private and intermediates" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b[?25h\x1b[!p");
    try std.testing.expectEqual(@as(usize, 2), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(u8, '?'), bridge.events.items[0].style_change.leader);
    try std.testing.expect(bridge.events.items[0].style_change.private);
    try std.testing.expectEqual(@as(i32, 25), bridge.events.items[0].style_change.params[0]);
    try std.testing.expectEqual(@as(u8, 0), bridge.events.items[1].style_change.leader);
    try std.testing.expect(!bridge.events.items[1].style_change.private);
    try std.testing.expectEqual(@as(u8, 1), bridge.events.items[1].style_change.intermediates_len);
    try std.testing.expectEqual(@as(u8, '!'), bridge.events.items[1].style_change.intermediates[0]);
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

test "replay: pipeline clear preserves partial CHT parser state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    pl.feedSlice("abc");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    pl.feedSlice("\x1b[2");
    pl.clear();
    try std.testing.expect(pl.isEmpty());
    pl.feedSlice("Ix");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 16));
    try std.testing.expect(pl.isEmpty());
}

test "replay: pipeline clear preserves partial CBT parser state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    pl.feedSlice("a\x1b[2I");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    pl.feedSlice("\x1b[2");
    pl.clear();
    try std.testing.expect(pl.isEmpty());
    pl.feedSlice("Zy");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 0));
    try std.testing.expect(pl.isEmpty());
}

test "replay: pipeline reset drops partial CHT parser state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    pl.feedSlice("\x1b[2");
    pl.reset();
    try std.testing.expect(pl.isEmpty());
    pl.feedSlice("Iw");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'I'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(0, 1));
}

test "replay: pipeline reset drops partial CBT parser state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    pl.feedSlice("a\x1b[2I");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    pl.feedSlice("\x1b[2");
    pl.reset();
    try std.testing.expect(pl.isEmpty());
    pl.feedSlice("Zv");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 18), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'v'), screen.cellAt(0, 17));
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

test "replay: CUD alias 'e' moves cursor down" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 5;
    feed(&pl, &screen, "\x1b[4e");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "replay: CUD alias 'e' zero param defaults to 1" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 5;
    feed(&pl, &screen, "\x1b[e");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
}

test "replay: CUF alias 'a' moves cursor forward" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_col = 10;
    feed(&pl, &screen, "\x1b[5a");
    try std.testing.expectEqual(@as(u16, 15), screen.cursor_col);
}

test "replay: CUF alias 'a' zero param defaults to 1" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_col = 10;
    feed(&pl, &screen, "\x1b[a");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
}

test "replay: CHA alias backtick moves cursor to absolute column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_col = 10;
    feed(&pl, &screen, "\x1b[7`");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_col);
}

test "replay: CHA alias backtick zero param defaults to column 0" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_col = 10;
    feed(&pl, &screen, "\x1b[`");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CUD alias 'e' clamps at last row" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(5, 20);
    screen.cursor_row = 2;
    feed(&pl, &screen, "\x1b[999e");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "replay: CUF alias 'a' clamps at last column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(10, 5);
    feed(&pl, &screen, "\x1b[999a");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "replay: CHA alias backtick clamps at last column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(5, 20);
    feed(&pl, &screen, "\x1b[999`");
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "replay: CNL moves cursor down and resets column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 5;
    screen.cursor_col = 20;
    feed(&pl, &screen, "\x1b[3E");
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CPL moves cursor up and resets column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 8;
    screen.cursor_col = 20;
    feed(&pl, &screen, "\x1b[3F");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: split CNL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("Ex");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split CNL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("Ex");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(7, 0));
}

test "replay: split CPL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("Fx");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split CPL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("Fx");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
}

test "replay: CHA moves cursor to absolute column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 6;
    screen.cursor_col = 12;
    feed(&pl, &screen, "\x1b[5G");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "replay: VPA moves cursor to absolute row" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 12;
    screen.cursor_col = 9;
    feed(&pl, &screen, "\x1b[7d");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
}

test "replay: VPA default param moves cursor to row zero" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 12;
    screen.cursor_col = 9;
    feed(&pl, &screen, "\x1b[d");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
}

test "replay: VPA clamps at last row" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(5, 20);
    feed(&pl, &screen, "\x1b[999d");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: split VPA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("dx");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split VPA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("dx");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(6, 0));
}

test "replay: CHA default param moves cursor to column zero" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(24, 80);
    screen.cursor_row = 4;
    screen.cursor_col = 33;
    feed(&pl, &screen, "\x1b[G");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CHA clamps at last column" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(2, 20);
    feed(&pl, &screen, "\x1b[999G");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "replay: split CHA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("Gx");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split CHA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("\x1b[7");
    pl.feedSlice("Gx");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
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

test "replay: CSI I advances cursor by default tab stops" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "a\x1b[2Ib");
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 16));
}

test "replay: CSI Z moves cursor to previous default tab stop" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "a\x1b[2I\x1b[Zb");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 8));
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

test "replay: DECSTR resets visible screen state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abcdef");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    feed(&pl, &screen, "\x1b[!p");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
}

test "replay: split CHT interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    pl.feedSlice("\x1b[2");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("Ix");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
    try std.testing.expect(pl.isEmpty());
}

test "replay: split CHT after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "abc");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("\x1b[2");
    pl.feedSlice("Ix");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 16));
    try std.testing.expect(pl.isEmpty());
}

test "replay: split CBT interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "a\x1b[2I");
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    pl.feedSlice("\x1b[2");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("Zy");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 19));
    try std.testing.expect(pl.isEmpty());
}

test "replay: split CBT after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&pl, &screen, "a\x1b[2I");
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("\x1b[2");
    pl.feedSlice("Zy");
    pl.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 0));
    try std.testing.expect(pl.isEmpty());
}

test "replay: DEC private cursor visibility toggles mode state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = screen_mod.ScreenState.init(2, 5);
    try std.testing.expect(screen.cursor_visible);
    feed(&pl, &screen, "\x1b[?25l");
    try std.testing.expect(!screen.cursor_visible);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&pl, &screen, "\x1b[?25h");
    try std.testing.expect(screen.cursor_visible);
}

test "replay: interrupted split private cursor mode remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.cursor_visible);
    feed(&pl, &screen, "x");
    pl.feedSlice("\x1b[?2");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("5l");
    pl.applyToScreen(&screen);
    try std.testing.expect(screen.cursor_visible);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 1));
    try std.testing.expect(pl.isEmpty());
}

test "replay: DEC private auto-wrap mode toggles wrap behavior" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.auto_wrap);
    feed(&pl, &screen, "\x1b[?7l");
    try std.testing.expect(!screen.auto_wrap);
    feed(&pl, &screen, "abcdefg");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'g'), screen.cellAt(0, 4));
    feed(&pl, &screen, "\x1b[?7h");
    try std.testing.expect(screen.auto_wrap);
    feed(&pl, &screen, "hi");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAt(1, 0));
}

test "replay: interrupted split private auto-wrap mode remains deterministic" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();
    var screen = try screen_mod.ScreenState.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.auto_wrap);
    feed(&pl, &screen, "x");
    pl.feedSlice("\x1b[?");
    pl.feedSlice("\x1b[!p");
    pl.feedSlice("7l");
    pl.applyToScreen(&screen);
    try std.testing.expect(screen.auto_wrap);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 1));
    try std.testing.expect(pl.isEmpty());
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

test "zero-dim: tab commands remain safe across all zero-dimension variants" {
    const gpa = std.testing.allocator;

    var pl_rows0 = try pipeline_mod.Pipeline.init(gpa);
    defer pl_rows0.deinit();
    var screen_rows0 = screen_mod.ScreenState.init(0, 8);
    feed(&pl_rows0, &screen_rows0, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 0), screen_rows0.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_rows0.cursor_col);

    var pl_cols0 = try pipeline_mod.Pipeline.init(gpa);
    defer pl_cols0.deinit();
    var screen_cols0 = screen_mod.ScreenState.init(8, 0);
    screen_cols0.cursor_row = 3;
    feed(&pl_cols0, &screen_cols0, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 3), screen_cols0.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_cols0.cursor_col);

    var pl_zero = try pipeline_mod.Pipeline.init(gpa);
    defer pl_zero.deinit();
    var screen_zero = screen_mod.ScreenState.init(0, 0);
    feed(&pl_zero, &screen_zero, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 0), screen_zero.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_zero.cursor_col);
}

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
    check_cursor_visible: bool = false,
    expected_cursor_visible: bool = true,
    check_auto_wrap: bool = false,
    expected_auto_wrap: bool = true,
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
    check_cursor_visible: bool = false,
    expected_cursor_visible: bool = true,
    check_auto_wrap: bool = false,
    expected_auto_wrap: bool = true,
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
    if (scenario.check_cursor_visible) {
        try std.testing.expectEqual(scenario.expected_cursor_visible, direct_screen.cursor_visible);
        try std.testing.expectEqual(scenario.expected_cursor_visible, runtime_engine.screen().cursor_visible);
    }
    if (scenario.check_auto_wrap) {
        try std.testing.expectEqual(scenario.expected_auto_wrap, direct_screen.auto_wrap);
        try std.testing.expectEqual(scenario.expected_auto_wrap, runtime_engine.screen().auto_wrap);
    }

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
    if (scenario.check_cursor_visible) {
        try std.testing.expectEqual(scenario.expected_cursor_visible, direct_screen.cursor_visible);
        try std.testing.expectEqual(scenario.expected_cursor_visible, runtime_engine.screen().cursor_visible);
    }
    if (scenario.check_auto_wrap) {
        try std.testing.expectEqual(scenario.expected_auto_wrap, direct_screen.auto_wrap);
        try std.testing.expectEqual(scenario.expected_auto_wrap, runtime_engine.screen().auto_wrap);
    }

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

test "parity: CUD alias 'e' moves cursor down identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUD alias e baseline",
        .rows = 10,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[3e",
        .expected_row = 3,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: CUF alias 'a' moves cursor forward identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CUF alias a baseline",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[10a",
        .expected_row = 0,
        .expected_col = 10,
        .expected_queue_depth = 0,
    });
}

test "parity: CHA alias backtick moves cursor to absolute column identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CHA alias backtick baseline",
        .rows = 24,
        .cols = 80,
        .with_cells = false,
        .input = "\x1b[20C\x1b[15`",
        .expected_row = 0,
        .expected_col = 14,
        .expected_queue_depth = 0,
    });
}

test "parity: CNL moves cursor down and resets column identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CNL baseline",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .input = "\x1b[3E",
        .expected_row = 3,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: CPL moves cursor up and resets column identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CPL baseline",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .input = "\x1b[3F",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: split CNL interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split CNL interrupted by DECSTR bytes",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[7\x1b[!pEx",
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity: split CNL after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split CNL after DECSTR",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[!p\x1b[7Ex",
        .expected_row = 7,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 7, .col = 0, .codepoint = 'x' },
        },
    });
}

test "parity: split CPL interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split CPL interrupted by DECSTR bytes",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[7\x1b[!pFx",
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity: split CPL after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split CPL after DECSTR",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[!p\x1b[7Fx",
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'x' },
        },
    });
}

test "parity: CHA moves cursor to absolute column identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CHA baseline",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .input = "\x1b[7G",
        .expected_row = 0,
        .expected_col = 6,
        .expected_queue_depth = 0,
    });
}

test "parity: VPA moves cursor to absolute row identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "VPA baseline",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .input = "\x1b[7d",
        .expected_row = 6,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: VPA clamps at last row identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "VPA clamp",
        .rows = 5,
        .cols = 20,
        .with_cells = false,
        .input = "\x1b[999d",
        .expected_row = 4,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: split VPA interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split VPA interrupted by DECSTR bytes",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[7\x1b[!pdx",
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity: split VPA after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split VPA after DECSTR",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[!p\x1b[7dx",
        .expected_row = 6,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 6, .col = 0, .codepoint = 'x' },
        },
    });
}

test "parity: CHA clamps at last column identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CHA clamp",
        .rows = 2,
        .cols = 20,
        .with_cells = false,
        .input = "\x1b[999G",
        .expected_row = 0,
        .expected_col = 19,
        .expected_queue_depth = 0,
    });
}

test "parity: split CHA interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split CHA interrupted by DECSTR bytes",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[7\x1b[!pGx",
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity: split CHA after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "split CHA after DECSTR",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[!p\x1b[7Gx",
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
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

test "parity: zero-dim rows=0 tab commands identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "zero-dim rows=0 tabs",
        .rows = 0,
        .cols = 8,
        .with_cells = false,
        .input = "\x09\x1b[2I\x1b[3Z",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: zero-dim cols=0 tab commands identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "zero-dim cols=0 tabs",
        .rows = 8,
        .cols = 0,
        .with_cells = false,
        .input = "\x09\x1b[2I\x1b[3Z",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity: zero-dim rows=0 cols=0 tab commands identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "zero-dim 0x0 tabs",
        .rows = 0,
        .cols = 0,
        .with_cells = false,
        .input = "\x09\x1b[2I\x1b[3Z",
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

test "parity: CHT advances cursor by requested tab stops identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CHT cursor forward tabulation",
        .rows = 3,
        .cols = 20,
        .with_cells = true,
        .input = "a\x1b[2Ib",
        .expected_row = 0,
        .expected_col = 17,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 16, .codepoint = 'b' },
        },
    });
}

test "parity: CBT moves cursor backward by requested tab stops identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CBT cursor backward tabulation",
        .rows = 3,
        .cols = 20,
        .with_cells = true,
        .input = "a\x1b[2I\x1b[Zb",
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

test "parity: CHT saturates at last column identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CHT clamped at last column",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "a\x1b[999Ib",
        .expected_row = 0,
        .expected_col = 19,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 19, .codepoint = 'b' },
        },
    });
}

test "parity: CBT saturates at column zero identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "CBT clamped at column zero",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "a\x1b[3I\x1b[999Zb",
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'b' },
            .{ .row = 0, .col = 1, .codepoint = 0 },
        },
    });
}

test "parity: HT/CHT/CBT interleaving remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "HT + CHT + CBT interleaving",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "a\x09b\x1b[2Zc\x1b[Id",
        .expected_row = 0,
        .expected_col = 9,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'c' },
            .{ .row = 0, .col = 8, .codepoint = 'd' },
        },
    });
}

test "parity: DEC private auto-wrap disable remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "private auto-wrap disable",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .input = "\x1b[?7l",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
        .check_auto_wrap = true,
        .expected_auto_wrap = false,
    });
}

test "parity: DECSTR restores private mode defaults identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "DECSTR restores private defaults",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .input = "\x1b[?25l\x1b[?7l\x1b[!p",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_auto_wrap = true,
        .expected_auto_wrap = true,
    });
}

test "parity: private mode changes after DECSTR remain effective identically" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "private modes after DECSTR",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .input = "\x1b[?25l\x1b[!p\x1b[?7l",
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_auto_wrap = true,
        .expected_auto_wrap = false,
    });
}

test "parity: tab and private modes with DECSTR remain identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "tab + private modes + DECSTR",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "a\x1b[2I\x1b[?7lbc\x1b[!p\x1b[Zd",
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_auto_wrap = true,
        .expected_auto_wrap = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'd' },
            .{ .row = 0, .col = 16, .codepoint = 0 },
        },
    });
}

test "parity: interrupted split private cursor mode remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "interrupted private cursor mode",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "x\x1b[?2\x1b[!p5l",
        .expected_row = 0,
        .expected_col = 5,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'x' },
            .{ .row = 0, .col = 1, .codepoint = '!' },
        },
    });
}

test "parity: interrupted split private auto-wrap mode remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "interrupted private auto-wrap mode",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "x\x1b[?\x1b[!p7l",
        .expected_row = 0,
        .expected_col = 5,
        .expected_queue_depth = 0,
        .check_auto_wrap = true,
        .expected_auto_wrap = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'x' },
            .{ .row = 0, .col = 1, .codepoint = '!' },
        },
    });
}

test "parity: interrupted split CHT stream remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "interrupted split CHT",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "abc\x1b[2\x1b[!pIx",
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity: interrupted split CBT stream remains identical" {
    const gpa = std.testing.allocator;
    try runParityScenario(gpa, .{
        .name = "interrupted split CBT",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .input = "a\x1b[2I\x1b[2\x1b[!pZy",
        .expected_row = 0,
        .expected_col = 19,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 19, .codepoint = 'y' },
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

test "parity-chunked: CHA split into byte fragments remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CHA",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .chunks = &.{ "\x1b", "[", "7", "G" },
        .expected_row = 0,
        .expected_col = 6,
        .expected_queue_depth = 0,
    });
}

test "parity-chunked: CNL split into byte fragments remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CNL",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .chunks = &.{ "\x1b", "[", "3", "E" },
        .expected_row = 3,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity-chunked: CPL split into byte fragments remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CPL",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .chunks = &.{ "\x1b", "[", "3", "F" },
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity-chunked: split CNL interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CNL interrupted by DECSTR bytes",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[7", "\x1b[!p", "Ex" },
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split CNL after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CNL after DECSTR",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[!p", "\x1b[7", "E", "x" },
        .expected_row = 7,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 7, .col = 0, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split CPL interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CPL interrupted by DECSTR bytes",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[7", "\x1b[!p", "Fx" },
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split CPL after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CPL after DECSTR",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[!p", "\x1b[7", "F", "x" },
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: VPA split into byte fragments remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked VPA",
        .rows = 10,
        .cols = 20,
        .with_cells = false,
        .chunks = &.{ "\x1b", "[", "7", "d" },
        .expected_row = 6,
        .expected_col = 0,
        .expected_queue_depth = 0,
    });
}

test "parity-chunked: split VPA interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked VPA interrupted by DECSTR bytes",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[7", "\x1b[!p", "dx" },
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split VPA after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked VPA after DECSTR",
        .rows = 10,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[!p", "\x1b[7", "d", "x" },
        .expected_row = 6,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 6, .col = 0, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split CHA interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CHA interrupted by DECSTR bytes",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[7", "\x1b[!p", "Gx" },
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split CHA after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CHA after DECSTR",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[!p", "\x1b[7", "Gx" },
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: CHT split into byte fragments remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CHT",
        .rows = 3,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a", "\x1b", "[", "2", "I", "b" },
        .expected_row = 0,
        .expected_col = 17,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 16, .codepoint = 'b' },
        },
    });
}

test "parity-chunked: CBT split into byte fragments remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CBT",
        .rows = 3,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a", "\x1b[", "2", "I", "\x1b", "[", "Z", "b" },
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

test "parity-chunked: CHT clamp split across chunks remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CHT clamp",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a", "\x1b[9", "99", "I", "b" },
        .expected_row = 0,
        .expected_col = 19,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 19, .codepoint = 'b' },
        },
    });
}

test "parity-chunked: CBT clamp split across chunks remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CBT clamp",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a", "\x1b[3I", "\x1b[", "99", "9", "Z", "b" },
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'b' },
            .{ .row = 0, .col = 1, .codepoint = 0 },
        },
    });
}

test "parity-chunked: HT/CHT/CBT interleaving split across chunks remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked HT + CHT + CBT interleaving",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a\x09", "b\x1b[", "2", "Z", "c\x1b", "[", "I", "d" },
        .expected_row = 0,
        .expected_col = 9,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'c' },
            .{ .row = 0, .col = 8, .codepoint = 'd' },
        },
    });
}

test "parity-chunked: zero-dim tab commands split across chunks remain identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked zero-dim tabs",
        .rows = 0,
        .cols = 8,
        .with_cells = false,
        .chunks = &.{ "\x09", "\x1b[", "2", "I", "\x1b[3", "Z" },
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
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

test "parity-chunked: DECSTR split across chunks resets before next write identically" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked DECSTR reset",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .chunks = &.{ "abcde", "\x1b[", "!", "p", "z" },
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'z' },
            .{ .row = 0, .col = 1, .codepoint = 0 },
            .{ .row = 1, .col = 0, .codepoint = 0 },
        },
    });
}

test "parity-chunked: DEC private cursor visibility split across chunks remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked private cursor visibility",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .chunks = &.{ "x", "\x1b[?2", "5l", "\x1b[", "?25", "h" },
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: DEC private auto-wrap mode split across chunks remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked private auto-wrap mode",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .chunks = &.{ "\x1b[?7", "l", "abcdefg", "\x1b[?7", "h", "hi" },
        .expected_row = 1,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_auto_wrap = true,
        .expected_auto_wrap = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 4, .codepoint = 'h' },
            .{ .row = 1, .col = 0, .codepoint = 'i' },
        },
    });
}

test "parity-chunked: DECSTR restores private defaults after split private modes identically" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked DECSTR restores private defaults",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .chunks = &.{ "\x1b[?2", "5l", "\x1b[?", "7l", "\x1b[", "!", "p" },
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_auto_wrap = true,
        .expected_auto_wrap = true,
    });
}

test "parity-chunked: private modes after split DECSTR remain effective identically" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked private modes after DECSTR",
        .rows = 2,
        .cols = 5,
        .with_cells = true,
        .chunks = &.{ "\x1b[?25", "l", "\x1b[", "!", "p", "\x1b[?7", "l" },
        .expected_row = 0,
        .expected_col = 0,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_auto_wrap = true,
        .expected_auto_wrap = false,
    });
}

test "parity-chunked: tab and private modes with split DECSTR remain identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked tab + private modes + DECSTR",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a", "\x1b[2", "I", "\x1b[?7", "l", "bc", "\x1b[", "!", "p", "\x1b[", "Z", "d" },
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_auto_wrap = true,
        .expected_auto_wrap = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'd' },
            .{ .row = 0, .col = 16, .codepoint = 0 },
        },
    });
}

test "parity-chunked: private modes after DECSTR with tab navigation remain identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked private modes after DECSTR + tabs",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "\x1b[?25", "l", "a", "\x1b[2I", "b", "\x1b[", "!", "p", "\x1b[?7", "l", "\x1b[?25", "h", "\x1b[2", "I", "c" },
        .expected_row = 0,
        .expected_col = 17,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_auto_wrap = true,
        .expected_auto_wrap = false,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 0 },
            .{ .row = 0, .col = 16, .codepoint = 'c' },
        },
    });
}

test "parity-chunked: split CHT interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CHT interrupted by DECSTR bytes",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[2", "\x1b[!p", "Ix" },
        .expected_row = 0,
        .expected_col = 7,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 3, .codepoint = '!' },
            .{ .row = 0, .col = 6, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split CHT started after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CHT after DECSTR",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "abc", "\x1b[!p", "\x1b[2", "Ix" },
        .expected_row = 0,
        .expected_col = 17,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 16, .codepoint = 'x' },
        },
    });
}

test "parity-chunked: split CBT interrupted by DECSTR bytes remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CBT interrupted by DECSTR bytes",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a\x1b[2I", "\x1b[2", "\x1b[!p", "Zy" },
        .expected_row = 0,
        .expected_col = 19,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'a' },
            .{ .row = 0, .col = 19, .codepoint = 'y' },
        },
    });
}

test "parity-chunked: split CBT started after DECSTR remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked CBT after DECSTR",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "a\x1b[2I", "\x1b[!p", "\x1b[2", "Zy" },
        .expected_row = 0,
        .expected_col = 1,
        .expected_queue_depth = 0,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'y' },
        },
    });
}

test "parity-chunked: interrupted split private cursor mode remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked interrupted private cursor mode",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "x", "\x1b[?2", "\x1b[!p", "5l" },
        .expected_row = 0,
        .expected_col = 5,
        .expected_queue_depth = 0,
        .check_cursor_visible = true,
        .expected_cursor_visible = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'x' },
            .{ .row = 0, .col = 1, .codepoint = '!' },
        },
    });
}

test "parity-chunked: interrupted split private auto-wrap mode remains identical" {
    const gpa = std.testing.allocator;
    try runParityChunkScenario(gpa, .{
        .name = "chunked interrupted private auto-wrap mode",
        .rows = 2,
        .cols = 20,
        .with_cells = true,
        .chunks = &.{ "x", "\x1b[?", "\x1b[!p", "7l" },
        .expected_row = 0,
        .expected_col = 5,
        .expected_queue_depth = 0,
        .check_auto_wrap = true,
        .expected_auto_wrap = true,
        .check_cells = true,
        .cell_checks = &.{
            .{ .row = 0, .col = 0, .codepoint = 'x' },
            .{ .row = 0, .col = 1, .codepoint = '!' },
        },
    });
}



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

test "runtime: clear drops pending HT/CHT/CBT before apply" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("a\x09b\x1b[2I\x1b[Z");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.clear();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 0), engine.screen().cellAt(0, 0));
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

test "runtime: reset clears partial CHT parser state and queued tab work" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("a\x1b[2");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.reset();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    engine.feedSlice("Ib");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 2), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'I'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), engine.screen().cellAt(0, 1));
}

test "runtime: resetScreen clears screen without clearing queued parser events" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 5);
    defer engine.deinit();
    engine.feedSlice("abcde");
    engine.apply();
    try std.testing.expectEqual(@as(u21, 'a'), engine.screen().cellAt(0, 0));
    engine.feedSlice("\x1b[?25l\x1b[?7l");
    engine.apply();
    try std.testing.expect(!engine.screen().cursor_visible);
    try std.testing.expect(!engine.screen().auto_wrap);
    engine.feedSlice("z");
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
    engine.resetScreen();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 0), engine.screen().cellAt(0, 0));
    try std.testing.expect(engine.screen().cursor_visible);
    try std.testing.expect(engine.screen().auto_wrap);
    try std.testing.expectEqual(@as(usize, 1), engine.queuedEventCount());
    engine.apply();
    try std.testing.expectEqual(@as(u21, 'z'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: resetScreen preserves queued HT/CHT application from cleared origin" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("xxxxx");
    engine.apply();
    engine.feedSlice("\x09\x1b[2Iz");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.resetScreen();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 0), engine.screen().cellAt(0, 0));
    engine.apply();
    try std.testing.expectEqual(@as(u21, 'z'), engine.screen().cellAt(0, 19));
    try std.testing.expectEqual(@as(u16, 19), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: resetScreen preserves split CHT and queued mode change" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[?7l\x1b[2");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.resetScreen();
    try std.testing.expect(engine.screen().auto_wrap);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    engine.feedSlice("Ixy");
    engine.apply();
    try std.testing.expect(!engine.screen().auto_wrap);
    try std.testing.expectEqual(@as(u16, 18), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 16));
    try std.testing.expectEqual(@as(u21, 'y'), engine.screen().cellAt(0, 17));
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: resetScreen preserves partial CHT parser state with empty queue" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[2");
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    engine.resetScreen();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    engine.feedSlice("Iw");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 17), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'w'), engine.screen().cellAt(0, 16));
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: resetScreen preserves split CBT and queued cursor visibility change" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("a\x1b[2I");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 16), engine.screen().cursor_col);
    engine.feedSlice("\x1b[?25l\x1b[3");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.resetScreen();
    try std.testing.expect(engine.screen().cursor_visible);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    engine.feedSlice("Zq");
    engine.apply();
    try std.testing.expect(!engine.screen().cursor_visible);
    try std.testing.expectEqual(@as(u16, 1), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'q'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "runtime: reset clears queue/parser without mutating screen modes" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 5);
    defer engine.deinit();
    engine.feedSlice("\x1b[?25l\x1b[?7l");
    engine.apply();
    try std.testing.expect(!engine.screen().cursor_visible);
    try std.testing.expect(!engine.screen().auto_wrap);
    engine.feedSlice("abc\x1b[");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.reset();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expect(!engine.screen().cursor_visible);
    try std.testing.expect(!engine.screen().auto_wrap);
}

test "runtime: reset clears queued mode event and split CHT parser state" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("\x1b[?7l\x1b[2");
    try std.testing.expect(engine.queuedEventCount() > 0);
    engine.reset();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expect(engine.screen().auto_wrap);
    engine.feedSlice("Iu");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 2), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'I'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'u'), engine.screen().cellAt(0, 1));
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

test "runtime: CNL move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[3E");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 3), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
}

test "runtime: CPL move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[3F");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
}

test "runtime: split CNL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[7");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("Ex");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 7), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), engine.screen().cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 6));
}

test "runtime: split CNL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("\x1b[7");
    engine.feedSlice("Ex");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 7), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 1), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(7, 0));
}

test "runtime: split CPL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[7");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("Fx");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 7), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), engine.screen().cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 6));
}

test "runtime: split CPL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("\x1b[7");
    engine.feedSlice("Fx");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 1), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 0));
}

test "runtime: CHA move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[9G");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 8), engine.screen().cursor_col);
}

test "runtime: VPA move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[9d");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 8), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
}

test "runtime: VPA clamp via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 5, 20);
    defer engine.deinit();
    engine.feedSlice("\x1b[999d");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 4), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
}

test "runtime: CUD alias 'e' move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[5e");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
}

test "runtime: CUF alias 'a' move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[9a");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 9), engine.screen().cursor_col);
}

test "runtime: CHA alias backtick move via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 24, 80);
    defer engine.deinit();
    engine.feedSlice("\x1b[9`");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 8), engine.screen().cursor_col);
}

test "runtime: split VPA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[7");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("dx");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 7), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), engine.screen().cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 6));
}

test "runtime: split VPA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("\x1b[7");
    engine.feedSlice("dx");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 6), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 1), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(6, 0));
}

test "runtime: CHA clamp via apply matches direct pipeline" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("\x1b[999G");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 19), engine.screen().cursor_col);
}

test "runtime: split CHA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[7");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("Gx");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 7), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), engine.screen().cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 6));
}

test "runtime: split CHA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("\x1b[7");
    engine.feedSlice("Gx");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 7), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 6));
}

test "runtime: CHT and CBT tab navigation via apply" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("a\x1b[2I\x1b[Zb");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 9), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), engine.screen().cellAt(0, 8));
}

test "runtime: DECSTR restores mode defaults before tab navigation" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("\x1b[?7l\x1b[?25l\x1b[!p\x1b[2Ic");
    engine.apply();
    try std.testing.expect(engine.screen().cursor_visible);
    try std.testing.expect(engine.screen().auto_wrap);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 17), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'c'), engine.screen().cellAt(0, 16));
}

test "runtime: interrupted split CHT stream remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[2");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("Ix");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 7), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), engine.screen().cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 6));
}

test "runtime: interrupted split private cursor mode remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    try std.testing.expect(engine.screen().cursor_visible);
    engine.feedSlice("x");
    engine.apply();
    engine.feedSlice("\x1b[?2");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("5l");
    engine.apply();
    try std.testing.expect(engine.screen().cursor_visible);
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), engine.screen().cellAt(0, 1));
}

test "runtime: interrupted split CBT stream remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    engine.feedSlice("a\x1b[2I");
    engine.apply();
    engine.feedSlice("\x1b[2");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("Zy");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 19), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), engine.screen().cellAt(0, 19));
}

test "runtime: interrupted split private auto-wrap mode remains deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 2, 20);
    defer engine.deinit();
    try std.testing.expect(engine.screen().auto_wrap);
    engine.feedSlice("x");
    engine.apply();
    engine.feedSlice("\x1b[?");
    engine.feedSlice("\x1b[!p");
    engine.feedSlice("7l");
    engine.apply();
    try std.testing.expect(engine.screen().auto_wrap);
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), engine.screen().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), engine.screen().cellAt(0, 1));
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

test "runtime: zero-dimension tab commands are safe and deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 0, 8);
    defer engine.deinit();
    engine.feedSlice("\x09\x1b[2I\x1b[3Z");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
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

test "runtime: initWithCellsAndHistory creates history" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 2, 10, 50);
    defer engine.deinit();
    try std.testing.expectEqual(@as(u16, 50), engine.historyCapacity());
    try std.testing.expectEqual(@as(u16, 0), engine.historyCount());
}

test "runtime: history accumulates via scroll" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 2, 10, 50);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[B\x0A");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 1), engine.historyCount());
    try std.testing.expectEqual(@as(u21, 'a'), engine.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), engine.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), engine.historyRowAt(0, 2));
}

test "runtime: history read returns zero for out-of-bounds" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 2, 10, 50);
    defer engine.deinit();
    engine.feedSlice("abc");
    engine.apply();
    engine.feedSlice("\x1b[B\x0A");
    engine.apply();
    try std.testing.expectEqual(@as(u21, 0), engine.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), engine.historyRowAt(0, 10));
}

test "runtime: direct screen and engine history states match" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 2, 5, 10);
    defer engine.deinit();
    engine.feedSlice("test");
    engine.apply();
    engine.feedSlice("\x1b[B\x0A");
    engine.apply();
    const direct_count = engine.screen().historyCount();
    const engine_count = engine.historyCount();
    try std.testing.expectEqual(direct_count, engine_count);
    for (0..engine_count) |i| {
        for (0..5) |col| {
            const direct_cell = engine.screen().historyRowAt(@intCast(i), @intCast(col));
            const engine_cell = engine.historyRowAt(@intCast(i), @intCast(col));
            try std.testing.expectEqual(direct_cell, engine_cell);
        }
    }
}

test "runtime: history accessor ordering remains stable after wraparound" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 2, 2, 2);
    defer engine.deinit();

    var row_num: u21 = '1';
    var i: u16 = 0;
    while (i < 4) : (i += 1) {
        const pair = [_]u8{ @intCast(row_num), @intCast(row_num) };
        engine.feedSlice("\x1b[H");
        engine.feedSlice(pair[0..]);
        engine.feedSlice("\x1b[B\x0A");
        engine.apply();
        row_num += 1;
    }

    try std.testing.expectEqual(@as(u16, 2), engine.historyCount());
    try std.testing.expectEqual(@as(u21, '4'), engine.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, '4'), engine.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, '3'), engine.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, '3'), engine.historyRowAt(1, 1));
}

test "selection: start and update with viewport coordinates" {
    var sel = model_mod.SelectionState.init();
    sel.start(5, 10);
    var state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 5), state.start.row);
    try std.testing.expectEqual(@as(u16, 10), state.start.col);

    sel.update(7, 15);
    state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 7), state.end.row);
    try std.testing.expectEqual(@as(u16, 15), state.end.col);
}

test "selection: start and update with history coordinates" {
    var sel = model_mod.SelectionState.init();
    sel.start(-3, 2);
    var state = sel.state().?;
    try std.testing.expectEqual(@as(i32, -3), state.start.row);
    try std.testing.expectEqual(@as(u16, 2), state.start.col);

    sel.update(-1, 8);
    state = sel.state().?;
    try std.testing.expectEqual(@as(i32, -1), state.end.row);
    try std.testing.expectEqual(@as(u16, 8), state.end.col);
}

test "selection: span from history to viewport" {
    var sel = model_mod.SelectionState.init();
    sel.start(-2, 0);
    var state = sel.state().?;
    try std.testing.expectEqual(@as(i32, -2), state.start.row);

    sel.update(5, 20);
    state = sel.state().?;
    try std.testing.expectEqual(@as(i32, -2), state.start.row);
    try std.testing.expectEqual(@as(i32, 5), state.end.row);
    try std.testing.expect(state.active);
    try std.testing.expect(state.selecting);
}

test "selection: clear deactivates selection" {
    var sel = model_mod.SelectionState.init();
    sel.start(2, 5);
    try std.testing.expect(sel.state() != null);

    sel.clear();
    try std.testing.expectEqual(@as(?model_mod.TerminalSelection, null), sel.state());
}

test "selection: finish stops selecting but keeps active" {
    var sel = model_mod.SelectionState.init();
    sel.start(3, 7);
    var state = sel.state().?;
    try std.testing.expect(state.selecting);

    sel.finish();
    state = sel.state().?;
    try std.testing.expect(state.active);
    try std.testing.expect(!state.selecting);
}

test "runtime: selection state integrated into engine cursor-only mode" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    try std.testing.expectEqual(@as(?model_mod.TerminalSelection, null), engine.selectionState());
    engine.selectionStart(3, 5);
    const sel = engine.selectionState().?;
    try std.testing.expectEqual(@as(i32, 3), sel.start.row);
    try std.testing.expectEqual(@as(u16, 5), sel.start.col);
}

test "runtime: selection state integrated into engine with cells" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();

    engine.selectionStart(2, 10);
    engine.selectionUpdate(5, 15);
    const sel = engine.selectionState().?;
    try std.testing.expectEqual(@as(i32, 2), sel.start.row);
    try std.testing.expectEqual(@as(i32, 5), sel.end.row);
}

test "runtime: selection state survives reset" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    engine.feedSlice("hello");
    engine.apply();
    engine.selectionStart(0, 1);
    engine.selectionFinish();

    engine.reset();

    const sel = engine.selectionState().?;
    try std.testing.expectEqual(@as(i32, 0), sel.start.row);
    try std.testing.expectEqual(@as(u16, 1), sel.start.col);
    try std.testing.expect(!sel.selecting);
}

test "runtime: selection survives resetScreen" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    engine.feedSlice("text\n");
    engine.apply();
    engine.selectionStart(-1, 2);
    const pre_reset = engine.selectionState().?;
    try std.testing.expect(pre_reset.active);

    engine.resetScreen();

    const post_reset = engine.selectionState().?;
    try std.testing.expectEqual(@as(i32, -1), post_reset.start.row);
    try std.testing.expect(post_reset.active);
}

test "runtime: selection clear deactivates through engine" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    engine.selectionStart(5, 7);
    try std.testing.expect(engine.selectionState() != null);

    engine.selectionClear();
    try std.testing.expectEqual(@as(?model_mod.TerminalSelection, null), engine.selectionState());
}

test "runtime: selection cleared when referencing out-of-bounds history index" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 2, 3, 2);
    defer engine.deinit();

    engine.feedSlice("1\x0A2\x0A3\x0A");
    engine.apply();

    engine.selectionStart(-3, 0);
    try std.testing.expect(engine.selectionState() != null);

    engine.feedSlice("x");
    engine.apply();

    try std.testing.expectEqual(@as(?model_mod.TerminalSelection, null), engine.selectionState());
}

test "runtime: selection not cleared by reset operation" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 5, 10, 3);
    defer engine.deinit();

    engine.feedSlice("test\x1b[H");
    engine.apply();

    engine.selectionStart(0, 2);
    const sel_before = engine.selectionState().?;
    try std.testing.expect(sel_before.active);

    engine.reset();

    const sel_after = engine.selectionState().?;
    try std.testing.expect(sel_after.active);
    try std.testing.expectEqual(@as(i32, 0), sel_after.start.row);
}

test "runtime: selection not cleared by resetScreen operation" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 5, 10, 3);
    defer engine.deinit();

    engine.feedSlice("test");
    engine.apply();

    engine.selectionStart(-1, 5);
    engine.selectionFinish();
    const sel_before = engine.selectionState().?;
    try std.testing.expect(sel_before.active);
    try std.testing.expect(!sel_before.selecting);

    engine.resetScreen();

    const sel_after = engine.selectionState().?;
    try std.testing.expect(sel_after.active);
    try std.testing.expect(!sel_after.selecting);
    try std.testing.expectEqual(@as(i32, -1), sel_after.start.row);
}

test "runtime: encodeKey handles printable ASCII" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const bytes = engine.encodeKey('A', model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 1), bytes.len);
    try std.testing.expectEqual(@as(u8, 'A'), bytes[0]);
}

test "runtime: encodeKey handles special keys" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const enter_bytes = engine.encodeKey(model_mod.VTERM_KEY_ENTER, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 1), enter_bytes.len);
    try std.testing.expectEqual(@as(u8, '\r'), enter_bytes[0]);

    const esc_bytes = engine.encodeKey(model_mod.VTERM_KEY_ESCAPE, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 1), esc_bytes.len);
    try std.testing.expectEqual(@as(u8, '\x1b'), esc_bytes[0]);

    const tab_bytes = engine.encodeKey(model_mod.VTERM_KEY_TAB, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 1), tab_bytes.len);
    try std.testing.expectEqual(@as(u8, '\t'), tab_bytes[0]);
}

test "runtime: encodeKey handles cursor keys" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const up_bytes = engine.encodeKey(model_mod.VTERM_KEY_UP, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 3), up_bytes.len);
    try std.testing.expectEqual(@as(u8, '\x1b'), up_bytes[0]);
    try std.testing.expectEqual(@as(u8, '['), up_bytes[1]);
    try std.testing.expectEqual(@as(u8, 'A'), up_bytes[2]);
}

test "runtime: encodeMouse returns empty when not enabled" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const event = model_mod.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = 5,
        .col = 10,
        .pixel_x = null,
        .pixel_y = null,
        .mod = model_mod.VTERM_MOD_NONE,
        .buttons_down = 0,
    };

    const bytes = engine.encodeMouse(event);
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
}

test "runtime: mouse event supports history row indices" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const history_event = model_mod.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = -2,
        .col = 10,
        .pixel_x = null,
        .pixel_y = null,
        .mod = model_mod.VTERM_MOD_NONE,
        .buttons_down = 0,
    };

    const viewport_event = model_mod.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = 5,
        .col = 10,
        .pixel_x = null,
        .pixel_y = null,
        .mod = model_mod.VTERM_MOD_NONE,
        .buttons_down = 0,
    };

    try std.testing.expect(history_event.row < 0);
    try std.testing.expect(viewport_event.row >= 0);
}

test "runtime: encodeKey handles extended keys (HOME, END, INS, DEL)" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const home_bytes = engine.encodeKey(model_mod.VTERM_KEY_HOME, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 3), home_bytes.len);
    try std.testing.expectEqual(@as(u8, '\x1b'), home_bytes[0]);
    try std.testing.expectEqual(@as(u8, '['), home_bytes[1]);
    try std.testing.expectEqual(@as(u8, 'H'), home_bytes[2]);

    const ins_bytes = engine.encodeKey(model_mod.VTERM_KEY_INS, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 4), ins_bytes.len);
    try std.testing.expectEqualSlices(u8, "\x1b[2~", ins_bytes);

    const del_bytes = engine.encodeKey(model_mod.VTERM_KEY_DEL, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 4), del_bytes.len);
    try std.testing.expectEqualSlices(u8, "\x1b[3~", del_bytes);
}

test "runtime: encodeKey handles page keys (PAGEUP, PAGEDOWN)" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const pageup_bytes = engine.encodeKey(model_mod.VTERM_KEY_PAGEUP, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 4), pageup_bytes.len);
    try std.testing.expectEqualSlices(u8, "\x1b[5~", pageup_bytes);

    const pagedown_bytes = engine.encodeKey(model_mod.VTERM_KEY_PAGEDOWN, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 4), pagedown_bytes.len);
    try std.testing.expectEqualSlices(u8, "\x1b[6~", pagedown_bytes);
}

test "runtime: extended key encoding with modifiers" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const shift_home = engine.encodeKey(model_mod.VTERM_KEY_HOME, model_mod.VTERM_MOD_SHIFT);
    try std.testing.expectEqual(@as(usize, 6), shift_home.len);
    try std.testing.expectEqual(@as(u8, '2'), shift_home[4]);

    const ctrl_del = engine.encodeKey(model_mod.VTERM_KEY_DEL, model_mod.VTERM_MOD_CTRL);
    try std.testing.expectEqual(@as(usize, 6), ctrl_del.len);
    try std.testing.expectEqual(@as(u8, '5'), ctrl_del[4]);
}

test "runtime: extended key encoding survives reset" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    const before_reset = engine.encodeKey(model_mod.VTERM_KEY_INS, model_mod.VTERM_MOD_NONE);
    var buf1: [64]u8 = undefined;
    @memcpy(buf1[0..before_reset.len], before_reset);
    const before_len = before_reset.len;

    engine.reset();

    const after_reset = engine.encodeKey(model_mod.VTERM_KEY_INS, model_mod.VTERM_MOD_NONE);

    try std.testing.expectEqual(before_len, after_reset.len);
    try std.testing.expectEqualSlices(u8, buf1[0..before_len], after_reset);
}

test "runtime: extended key encoding deterministic for repeated calls" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const call1 = engine.encodeKey(model_mod.VTERM_KEY_END, model_mod.VTERM_MOD_ALT);
    var buf1: [64]u8 = undefined;
    @memcpy(buf1[0..call1.len], call1);

    const call2 = engine.encodeKey(model_mod.VTERM_KEY_END, model_mod.VTERM_MOD_ALT);

    try std.testing.expectEqual(call1.len, call2.len);
    try std.testing.expectEqualSlices(u8, buf1[0..call1.len], call2);
}

test "runtime: encodeKey handles function keys F1-F4" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const f1_bytes = engine.encodeKey(model_mod.VTERM_KEY_F1, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 3), f1_bytes.len);
    try std.testing.expectEqualSlices(u8, "\x1b[P", f1_bytes);

    const f2_bytes = engine.encodeKey(model_mod.VTERM_KEY_F2, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[Q", f2_bytes);

    const f3_bytes = engine.encodeKey(model_mod.VTERM_KEY_F3, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[R", f3_bytes);

    const f4_bytes = engine.encodeKey(model_mod.VTERM_KEY_F4, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[S", f4_bytes);
}

test "runtime: encodeKey handles function keys F5-F12" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const f5_bytes = engine.encodeKey(model_mod.VTERM_KEY_F5, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 5), f5_bytes.len);
    try std.testing.expectEqualSlices(u8, "\x1b[15~", f5_bytes);

    const f9_bytes = engine.encodeKey(model_mod.VTERM_KEY_F9, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[20~", f9_bytes);

    const f12_bytes = engine.encodeKey(model_mod.VTERM_KEY_F12, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[24~", f12_bytes);
}

test "runtime: function key encoding with modifiers" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const shift_f1 = engine.encodeKey(model_mod.VTERM_KEY_F1, model_mod.VTERM_MOD_SHIFT);
    try std.testing.expectEqual(@as(usize, 6), shift_f1.len);
    try std.testing.expectEqual(@as(u8, '2'), shift_f1[4]);

    const ctrl_f5 = engine.encodeKey(model_mod.VTERM_KEY_F5, model_mod.VTERM_MOD_CTRL);
    try std.testing.expectEqual(@as(usize, 7), ctrl_f5.len);
    try std.testing.expectEqual(@as(u8, '5'), ctrl_f5[5]);

    const alt_f12 = engine.encodeKey(model_mod.VTERM_KEY_F12, model_mod.VTERM_MOD_ALT);
    try std.testing.expectEqual(@as(usize, 7), alt_f12.len);
    try std.testing.expectEqual(@as(u8, '3'), alt_f12[5]);
}

test "runtime: function key encoding survives reset" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    const before_reset = engine.encodeKey(model_mod.VTERM_KEY_F6, model_mod.VTERM_MOD_NONE);
    var buf1: [64]u8 = undefined;
    @memcpy(buf1[0..before_reset.len], before_reset);
    const before_len = before_reset.len;

    engine.reset();

    const after_reset = engine.encodeKey(model_mod.VTERM_KEY_F6, model_mod.VTERM_MOD_NONE);

    try std.testing.expectEqual(before_len, after_reset.len);
    try std.testing.expectEqualSlices(u8, buf1[0..before_len], after_reset);
}

test "runtime: function key encoding deterministic for repeated calls" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const call1 = engine.encodeKey(model_mod.VTERM_KEY_F11, model_mod.VTERM_MOD_SHIFT);
    var buf1: [64]u8 = undefined;
    @memcpy(buf1[0..call1.len], call1);

    const call2 = engine.encodeKey(model_mod.VTERM_KEY_F11, model_mod.VTERM_MOD_SHIFT);

    try std.testing.expectEqual(call1.len, call2.len);
    try std.testing.expectEqualSlices(u8, buf1[0..call1.len], call2);
}

test "runtime: input encoding is deterministic for repeated calls" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const bytes1 = engine.encodeKey('X', model_mod.VTERM_MOD_SHIFT);
    var buf1: [64]u8 = undefined;
    @memcpy(buf1[0..bytes1.len], bytes1);

    const bytes2 = engine.encodeKey('X', model_mod.VTERM_MOD_SHIFT);

    try std.testing.expectEqual(bytes1.len, bytes2.len);
    try std.testing.expectEqualSlices(u8, buf1[0..bytes1.len], bytes2);
}

test "runtime: input encoding survives reset operation" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    const before_reset = engine.encodeKey(model_mod.VTERM_KEY_ENTER, model_mod.VTERM_MOD_NONE);
    var buf1: [64]u8 = undefined;
    @memcpy(buf1[0..before_reset.len], before_reset);
    const before_len = before_reset.len;

    engine.reset();

    const after_reset = engine.encodeKey(model_mod.VTERM_KEY_ENTER, model_mod.VTERM_MOD_NONE);

    try std.testing.expectEqual(before_len, after_reset.len);
    try std.testing.expectEqualSlices(u8, buf1[0..before_len], after_reset);
}

test "runtime: input encoding survives resetScreen operation" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    engine.feedSlice("test");
    engine.apply();

    const before_reset = engine.encodeKey(model_mod.VTERM_KEY_ESCAPE, model_mod.VTERM_MOD_NONE);
    var buf1: [64]u8 = undefined;
    @memcpy(buf1[0..before_reset.len], before_reset);
    const before_len = before_reset.len;

    engine.resetScreen();

    const after_reset = engine.encodeKey(model_mod.VTERM_KEY_ESCAPE, model_mod.VTERM_MOD_NONE);

    try std.testing.expectEqual(before_len, after_reset.len);
    try std.testing.expectEqualSlices(u8, buf1[0..before_len], after_reset);
}

test "runtime: input does not affect selection state" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    engine.selectionStart(2, 5);
    const before_sel = engine.selectionState().?;

    _ = engine.encodeKey('A', model_mod.VTERM_MOD_NONE);

    const after_sel = engine.selectionState().?;
    try std.testing.expectEqual(before_sel.active, after_sel.active);
    try std.testing.expectEqual(before_sel.start.row, after_sel.start.row);
    try std.testing.expectEqual(before_sel.start.col, after_sel.start.col);
}

test "runtime: input encoding output is not mutable from caller" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    const bytes = engine.encodeKey('B', model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 1), bytes.len);
    try std.testing.expectEqual(@as(u8, 'B'), bytes[0]);
}





test "M4 closeout: keyboard input comprehensive coverage" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    
    const ascii = engine.encodeKey('A', model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(usize, 1), ascii.len);
    try std.testing.expectEqual(@as(u8, 'A'), ascii[0]);

    
    const enter = engine.encodeKey(model_mod.VTERM_KEY_ENTER, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\r", enter);

    const escape = engine.encodeKey(model_mod.VTERM_KEY_ESCAPE, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b", escape);

    const backspace = engine.encodeKey(model_mod.VTERM_KEY_BACKSPACE, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x7f", backspace);

    
    const up = engine.encodeKey(model_mod.VTERM_KEY_UP, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[A", up);

    
    const home = engine.encodeKey(model_mod.VTERM_KEY_HOME, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[H", home);

    const del = engine.encodeKey(model_mod.VTERM_KEY_DEL, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[3~", del);

    
    const f1 = engine.encodeKey(model_mod.VTERM_KEY_F1, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[P", f1);

    const f5 = engine.encodeKey(model_mod.VTERM_KEY_F5, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[15~", f5);

    const f12 = engine.encodeKey(model_mod.VTERM_KEY_F12, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, "\x1b[24~", f12);
}

test "M4 closeout: modifier combinations are deterministic" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    
    const shift_up = engine.encodeKey(model_mod.VTERM_KEY_UP, model_mod.VTERM_MOD_SHIFT);
    try std.testing.expectEqual(@as(usize, 6), shift_up.len);
    try std.testing.expectEqual(@as(u8, '2'), shift_up[4]); 

    var buf_shift: [64]u8 = undefined;
    @memcpy(buf_shift[0..shift_up.len], shift_up);

    const shift_up_2 = engine.encodeKey(model_mod.VTERM_KEY_UP, model_mod.VTERM_MOD_SHIFT);
    try std.testing.expectEqualSlices(u8, buf_shift[0..shift_up.len], shift_up_2);

    
    const alt_down = engine.encodeKey(model_mod.VTERM_KEY_DOWN, model_mod.VTERM_MOD_ALT);
    try std.testing.expectEqual(@as(u8, '3'), alt_down[4]); 

    
    const ctrl_right = engine.encodeKey(model_mod.VTERM_KEY_RIGHT, model_mod.VTERM_MOD_CTRL);
    try std.testing.expectEqual(@as(u8, '5'), ctrl_right[4]); 

    
    const shift_ctrl_left = engine.encodeKey(model_mod.VTERM_KEY_LEFT, model_mod.VTERM_MOD_SHIFT | model_mod.VTERM_MOD_CTRL);
    try std.testing.expectEqual(@as(u8, '6'), shift_ctrl_left[4]); 
}

test "M4 closeout: encoding is reset-stable" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    
    engine.feedSlice("\x1b[2J");
    engine.apply();

    
    const before = engine.encodeKey(model_mod.VTERM_KEY_ENTER, model_mod.VTERM_MOD_NONE);
    var buf_before: [64]u8 = undefined;
    @memcpy(buf_before[0..before.len], before);

    
    engine.reset();

    
    const after = engine.encodeKey(model_mod.VTERM_KEY_ENTER, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, buf_before[0..before.len], after);

    
    engine.resetScreen();
    const after_screen = engine.encodeKey(model_mod.VTERM_KEY_ENTER, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqualSlices(u8, buf_before[0..before.len], after_screen);
}

test "M4 closeout: encoding does not mutate state" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 5, 10, 20);
    defer engine.deinit();

    
    engine.feedSlice("hello");
    engine.apply();
    const screen_before = engine.screen().*;
    const history_before = engine.historyCount();

    
    _ = engine.encodeKey(model_mod.VTERM_KEY_UP, model_mod.VTERM_MOD_SHIFT);
    _ = engine.encodeKey('X', model_mod.VTERM_MOD_CTRL);
    _ = engine.encodeKey(model_mod.VTERM_KEY_F12, model_mod.VTERM_MOD_ALT);

    
    const screen_after = engine.screen().*;
    const history_after = engine.historyCount();

    try std.testing.expectEqual(screen_before.cursor_row, screen_after.cursor_row);
    try std.testing.expectEqual(screen_before.cursor_col, screen_after.cursor_col);
    try std.testing.expectEqual(history_before, history_after);
}

test "M4 closeout: encoding covers extended keys with modifiers" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    
    const shift_home = engine.encodeKey(model_mod.VTERM_KEY_HOME, model_mod.VTERM_MOD_SHIFT);
    try std.testing.expectEqual(@as(usize, 6), shift_home.len);
    try std.testing.expectEqualSlices(u8, "\x1b[1;2H", shift_home);

    
    const ctrl_del = engine.encodeKey(model_mod.VTERM_KEY_DEL, model_mod.VTERM_MOD_CTRL);
    try std.testing.expectEqual(@as(usize, 6), ctrl_del.len);
    try std.testing.expectEqualSlices(u8, "\x1b[3;5~", ctrl_del);

    
    const alt_pageup = engine.encodeKey(model_mod.VTERM_KEY_PAGEUP, model_mod.VTERM_MOD_ALT);
    try std.testing.expectEqual(@as(usize, 6), alt_pageup.len);
    try std.testing.expectEqualSlices(u8, "\x1b[5;3~", alt_pageup);
}

test "M4 closeout: encoding covers function keys with modifiers" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    
    const shift_f2 = engine.encodeKey(model_mod.VTERM_KEY_F2, model_mod.VTERM_MOD_SHIFT);
    try std.testing.expectEqualSlices(u8, "\x1b[1;2Q", shift_f2);

    
    const ctrl_f8 = engine.encodeKey(model_mod.VTERM_KEY_F8, model_mod.VTERM_MOD_CTRL);
    try std.testing.expectEqualSlices(u8, "\x1b[19;5~", ctrl_f8);

    const alt_f11 = engine.encodeKey(model_mod.VTERM_KEY_F11, model_mod.VTERM_MOD_ALT);
    try std.testing.expectEqualSlices(u8, "\x1b[23;3~", alt_f11);
}





test "M5-A2 conformance: clear() empties queue without mutating parser or screen" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    
    engine.feedSlice("ABC\x1b[2J");
    try std.testing.expect(engine.queuedEventCount() > 0);

    const screen_before = engine.screen().*;

    
    engine.clear();

    
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expectEqual(screen_before.cursor_row, engine.screen().cursor_row);
    try std.testing.expectEqual(screen_before.cursor_col, engine.screen().cursor_col);
}

test "M5-A2 conformance: reset() clears parser+queue but preserves screen modes" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 5, 10);
    defer engine.deinit();

    
    engine.feedSlice("\x1b[?25l\x1b[?7h");
    engine.apply();

    const cursor_visible = engine.screen().cursor_visible;
    const auto_wrap = engine.screen().auto_wrap;

    
    engine.feedSlice("test\x1b[");
    try std.testing.expect(engine.queuedEventCount() > 0);

    
    engine.reset();

    
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expectEqual(cursor_visible, engine.screen().cursor_visible);
    try std.testing.expectEqual(auto_wrap, engine.screen().auto_wrap);
}

test "M5-A2 conformance: resetScreen() clears screen but preserves parser+queue" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    
    engine.feedSlice("Hello");
    engine.apply();
    const screen_col = engine.screen().cursor_col;
    try std.testing.expect(screen_col > 0);

    
    engine.feedSlice("\x1b[2J");
    const queued_before = engine.queuedEventCount();

    
    engine.resetScreen();

    
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
    try std.testing.expectEqual(queued_before, engine.queuedEventCount());
}

test "M5-A2 conformance: multiple apply() calls without feed are no-ops" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 5, 10);
    defer engine.deinit();

    
    engine.feedSlice("X");
    engine.apply();
    const col_after_first = engine.screen().cursor_col;

    
    engine.apply();
    engine.apply();

    try std.testing.expectEqual(col_after_first, engine.screen().cursor_col);
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
}

test "M5-A2 conformance: feed operations queue events without applying" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 5, 10);
    defer engine.deinit();

    
    engine.feedByte('A');
    engine.feedByte('B');
    engine.feedByte('C');
    try std.testing.expect(engine.queuedEventCount() > 0);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col); 

    
    engine.feedSlice("\x1b[5;10H");
    try std.testing.expect(engine.queuedEventCount() > 0);
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col); 

    
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.queuedEventCount());
    try std.testing.expectEqual(@as(u16, 9), engine.screen().cursor_col); 
}

test "M5-A2 conformance: encode operations have no observable state effects" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 5, 10, 20);
    defer engine.deinit();

    
    engine.feedSlice("DATA");
    engine.apply();
    engine.selectionStart(0, 5);

    const screen_state = engine.screen().*;
    const selection_state = engine.selectionState().?;
    const history_count = engine.historyCount();
    const queued_count = engine.queuedEventCount();

    
    _ = engine.encodeKey(model_mod.VTERM_KEY_UP, model_mod.VTERM_MOD_SHIFT);
    _ = engine.encodeKey('X', model_mod.VTERM_MOD_NONE);
    _ = engine.encodeKey(model_mod.VTERM_KEY_F12, model_mod.VTERM_MOD_CTRL);

    
    try std.testing.expectEqual(screen_state.cursor_row, engine.screen().cursor_row);
    try std.testing.expectEqual(screen_state.cursor_col, engine.screen().cursor_col);
    try std.testing.expectEqual(selection_state.start.row, engine.selectionState().?.start.row);
    try std.testing.expectEqual(selection_state.start.col, engine.selectionState().?.start.col);
    try std.testing.expectEqual(history_count, engine.historyCount());
    try std.testing.expectEqual(queued_count, engine.queuedEventCount());
}

test "M5-A2 conformance: screen() returns const reference only" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 5, 10);
    defer engine.deinit();

    const screen_ref = engine.screen();

    
    _ = screen_ref.cursor_row;
    _ = screen_ref.cursor_col;
    _ = screen_ref.cursor_visible;

    
    const screen_ref2 = engine.screen();
    try std.testing.expectEqual(screen_ref.cursor_row, screen_ref2.cursor_row);
}

test "M5-A2 conformance: feed/apply/reset ordering" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    
    engine.feedSlice("First");
    engine.apply();
    try std.testing.expect(engine.screen().cursor_col > 0);

    engine.feedSlice("\x1b[H"); 
    try std.testing.expect(engine.queuedEventCount() > 0);

    engine.reset(); 
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expect(engine.screen().cursor_col > 0); 

    
    engine.apply();
    try std.testing.expect(engine.screen().cursor_col > 0);

    
    engine.feedSlice("\x1b[H");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);
}





test "M5-B2 parity: split-feed at CSI boundary preserves queue semantics" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.init(gpa, 10, 20);
    defer engine.deinit();

    
    engine.feedSlice("\x1b[5;1");  
    const queued_mid = engine.queuedEventCount();
    try std.testing.expectEqual(@as(usize, 0), queued_mid);

    engine.feedSlice("0H");  
    const queued_after = engine.queuedEventCount();

    
    try std.testing.expect(queued_after > 0);
    engine.apply();
    try std.testing.expectEqual(@as(u16, 9), engine.screen().cursor_col);
}

test "M5-B2 parity: feed/apply/reset/feed/apply preserves state isolation" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 10, 20);
    defer engine.deinit();

    
    engine.feedSlice("HELLO");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_col);

    
    engine.feedSlice("\x1b[");
    const queued = engine.queuedEventCount();
    try std.testing.expectEqual(@as(usize, 0), queued); 

    
    engine.reset();
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());
    try std.testing.expectEqual(@as(u16, 5), engine.screen().cursor_col); 

    
    engine.feedSlice("WORLD");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 10), engine.screen().cursor_col);
}

test "M5-B2 parity: selection + history interaction during apply" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 5, 10, 20);
    defer engine.deinit();

    
    engine.feedSlice("LINE1\nLINE2\nLINE3");
    engine.apply();

    
    engine.selectionStart(1, 0);
    const sel_before = engine.selectionState().?;
    try std.testing.expectEqual(true, sel_before.active);

    
    engine.feedSlice("\x1b[2J");
    engine.apply();

    
    const sel_after = engine.selectionState();
    try std.testing.expectEqual(true, sel_after.?.active);
    try std.testing.expectEqual(sel_before.start.row, sel_after.?.start.row);
}

test "M5-B2 parity: encode interleaved with feed/apply does not mutate state" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCells(gpa, 5, 10);
    defer engine.deinit();

    engine.feedSlice("ABC");
    engine.apply();
    const col_after_abc = engine.screen().cursor_col;

    
    _ = engine.encodeKey(model_mod.VTERM_KEY_UP, model_mod.VTERM_MOD_SHIFT);
    _ = engine.encodeKey('X', model_mod.VTERM_MOD_NONE);

    
    try std.testing.expectEqual(col_after_abc, engine.screen().cursor_col);

    
    engine.feedSlice("DEF");
    engine.apply();
    try std.testing.expectEqual(col_after_abc + 3, engine.screen().cursor_col);

    
    _ = engine.encodeKey(model_mod.VTERM_KEY_F5, model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(col_after_abc + 3, engine.screen().cursor_col);
}

test "M5-B2 parity: complex state machine sequence" {
    const gpa = std.testing.allocator;
    var engine = try runtime_mod.Engine.initWithCellsAndHistory(gpa, 5, 10, 10);
    defer engine.deinit();

    

    
    engine.feedSlice("A");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 1), engine.screen().cursor_col);

    
    const encoded = engine.encodeKey('B', model_mod.VTERM_MOD_NONE);
    try std.testing.expectEqual(@as(u8, 'B'), encoded[0]);
    try std.testing.expectEqual(@as(u16, 1), engine.screen().cursor_col);

    
    engine.feedSlice("B\x1b[5G");  
    engine.apply();
    try std.testing.expectEqual(@as(u16, 4), engine.screen().cursor_col);

    
    engine.reset();
    try std.testing.expectEqual(@as(u16, 4), engine.screen().cursor_col);
    try std.testing.expectEqual(@as(usize, 0), engine.queuedEventCount());

    
    engine.feedSlice("C\x1b[H");
    engine.apply();
    try std.testing.expectEqual(@as(u16, 0), engine.screen().cursor_col);

    
    try std.testing.expectEqual(@as(u16, 0), engine.historyCount());
}
