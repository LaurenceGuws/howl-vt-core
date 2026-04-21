//! Responsibility: validate parser dispatch behavior and edge boundaries.
//! Ownership: terminal parser test layer.
//! Reason: lock parser contracts with deterministic transcript assertions.

const std = @import("std");
const parser_mod = @import("terminal/parser.zig");
const stream_mod = parser_mod.stream;
const csi_mod = parser_mod.csi;

pub const Event = union(enum) {
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

pub const Harness = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),

    pub fn init(allocator: std.mem.Allocator) Harness {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(Event).initCapacity(allocator, 16) catch unreachable,
        };
    }

    pub fn deinit(self: *Harness) void {
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

    pub fn toSink(self: *Harness) parser_mod.Sink {
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

test "parser: OSC with ST terminator (ESC \\)" {
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

test "parser: split input - OSC partial then completion" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b]data");
    parser.handleSlice("\x1b\\");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqualSlices(u8, "data", harness.events.items[0].osc.data);
}

test "parser: control byte C0 (BEL outside UTF-8)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleByte('A');
    parser.handleByte(0x07);
    parser.handleByte('B');

    try std.testing.expectEqual(@as(usize, 3), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .stream_codepoint);
    try std.testing.expect(harness.events.items[1] == .stream_control);
    try std.testing.expectEqual(@as(u8, 0x07), harness.events.items[1].stream_control);
    try std.testing.expect(harness.events.items[2] == .stream_codepoint);
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
    try std.testing.expectEqual(@as(u8, 2), harness.events.items[0].csi.count);
}

test "boundary: UTF-8 split at leading byte (U+00E9 = é, 0xC3 0xA9)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleByte(0xC3);
    parser.handleByte(0xA9);

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), harness.events.items[0].stream_codepoint);
}

test "boundary: 3-byte UTF-8 split after first byte (U+20AC = €, 0xE2 0x82 0xAC)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleByte(0xE2);
    parser.handleSlice("\x82\xAC");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x20AC), harness.events.items[0].stream_codepoint);
}

test "boundary: 3-byte UTF-8 split after second byte (U+20AC = €, 0xE2 0x82 0xAC)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\xE2\x82");
    parser.handleByte(0xAC);

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x20AC), harness.events.items[0].stream_codepoint);
}

test "boundary: CSI split at digit boundary (1, 3 across calls)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b[1");
    parser.handleSlice("3m");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .csi);
    try std.testing.expectEqual(@as(u8, 'm'), harness.events.items[0].csi.final);
    try std.testing.expectEqual(@as(i32, 13), harness.events.items[0].csi.params[0]);
}

test "boundary: CSI multi-param split between separator and next digit" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b[1;");
    parser.handleSlice("31m");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .csi);
    try std.testing.expectEqual(@as(u8, 'm'), harness.events.items[0].csi.final);
    try std.testing.expectEqual(@as(i32, 1), harness.events.items[0].csi.params[0]);
    try std.testing.expectEqual(@as(i32, 31), harness.events.items[0].csi.params[1]);
}

test "boundary: OSC split in middle of data payload" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b]hello wo");
    parser.handleSlice("rld\x1b\\");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqualSlices(u8, "hello world", harness.events.items[0].osc.data);
    try std.testing.expectEqual(parser_mod.OscTerminator.st, harness.events.items[0].osc.term);
}

test "boundary: APC split before terminator (ST)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b_payload");
    parser.handleSlice("\x1b");
    parser.handleSlice("\\");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .apc);
    try std.testing.expectEqualSlices(u8, "payload", harness.events.items[0].apc);
}

test "boundary: DCS split with 3-part feed (intro, data, terminator)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleByte(0x1B);
    parser.handleByte('P');
    parser.handleSlice("dcs_data");
    parser.handleSlice("\x1b\\");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .dcs);
    try std.testing.expectEqualSlices(u8, "dcs_data", harness.events.items[0].dcs);
}

test "boundary: mixed stream split after ASCII, before escape" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("ABC");
    parser.handleSlice("\x1b[31m");
    parser.handleSlice("XYZ");

    try std.testing.expectEqual(@as(usize, 3), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .ascii_slice);
    try std.testing.expectEqualSlices(u8, "ABC", harness.events.items[0].ascii_slice);
    try std.testing.expect(harness.events.items[1] == .csi);
    try std.testing.expectEqual(@as(u8, 'm'), harness.events.items[1].csi.final);
    try std.testing.expect(harness.events.items[2] == .ascii_slice);
    try std.testing.expectEqualSlices(u8, "XYZ", harness.events.items[2].ascii_slice);
}

test "boundary: OSC with multiple stray ESC sequences (ESC dropped, byte appended)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b]start");
    parser.handleSlice("\x1bm");
    parser.handleSlice("id\x1bdle");
    parser.handleSlice("\x1b\\");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqualSlices(u8, "startmiddle", harness.events.items[0].osc.data);
}

test "boundary: control byte interleaved with ASCII and UTF-8" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleByte('X');
    parser.handleByte(0x07);
    parser.handleSlice("\xC3\xA9");
    parser.handleByte(0x07);
    parser.handleByte('Y');

    try std.testing.expectEqual(@as(usize, 5), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .stream_codepoint);
    try std.testing.expect(harness.events.items[1] == .stream_control);
    try std.testing.expect(harness.events.items[2] == .stream_codepoint);
    try std.testing.expect(harness.events.items[3] == .stream_control);
    try std.testing.expect(harness.events.items[4] == .stream_codepoint);
}
