//! HT-009: Parser dispatch proof tests.
//! Validates parser state machine and callback dispatch for:
//! - Mixed stream (ASCII + CSI + ASCII)
//! - ESC final passthrough
//! - OSC/APC/DCS termination (BEL and ST)
//! - UTF-8 + ASCII interaction

const std = @import("std");
const parser_mod = @import("terminal/parser.zig");
const stream_mod = parser_mod.stream;
const csi_mod = parser_mod.csi;

pub const EventKind = enum {
    stream_event,
    ascii_slice,
    csi,
    osc,
    apc,
    dcs,
    esc_final,
};

pub const TestSink = struct {
    event_count: usize = 0,
    last_csi_final: u8 = 0,
    last_csi_params: [16]i32 = [_]i32{0} ** 16,
    last_csi_count: u8 = 0,
    last_esc_final: u8 = 0,
    last_osc_len: usize = 0,
    last_osc_term: parser_mod.OscTerminator = .st,
    last_apc_len: usize = 0,
    last_dcs_len: usize = 0,
    last_event_kind: EventKind = .stream_event,

    pub fn toSink(self: *TestSink) parser_mod.Sink {
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

    fn onStreamEvent(ptr: *anyopaque, _: stream_mod.StreamEvent) void {
        const self: *TestSink = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.last_event_kind = .stream_event;
    }

    fn onAsciiSlice(ptr: *anyopaque, _: []const u8) void {
        const self: *TestSink = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.last_event_kind = .ascii_slice;
    }

    fn onCsi(ptr: *anyopaque, action: csi_mod.CsiAction) void {
        const self: *TestSink = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.last_event_kind = .csi;
        self.last_csi_final = action.final;
        self.last_csi_params = action.params;
        self.last_csi_count = action.count;
    }

    fn onOsc(ptr: *anyopaque, data: []const u8, terminator: parser_mod.OscTerminator) void {
        const self: *TestSink = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.last_event_kind = .osc;
        self.last_osc_len = data.len;
        self.last_osc_term = terminator;
    }

    fn onApc(ptr: *anyopaque, data: []const u8) void {
        const self: *TestSink = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.last_event_kind = .apc;
        self.last_apc_len = data.len;
    }

    fn onDcs(ptr: *anyopaque, data: []const u8) void {
        const self: *TestSink = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.last_event_kind = .dcs;
        self.last_dcs_len = data.len;
    }

    fn onEscFinal(ptr: *anyopaque, byte: u8) void {
        const self: *TestSink = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.last_event_kind = .esc_final;
        self.last_esc_final = byte;
    }
};

test "parser dispatch: mixed stream (ASCII + CSI + ASCII)" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("AB\x1b[31mC");

    try std.testing.expect(sink.event_count >= 3);
}

test "parser dispatch: ESC final passthrough" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1bM");

    try std.testing.expectEqual(EventKind.esc_final, sink.last_event_kind);
    try std.testing.expectEqual(@as(u8, 'M'), sink.last_esc_final);
}

test "parser dispatch: OSC terminated by BEL" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b]title\x07");

    try std.testing.expectEqual(EventKind.osc, sink.last_event_kind);
    try std.testing.expectEqual(parser_mod.OscTerminator.bel, sink.last_osc_term);
    try std.testing.expectEqual(@as(usize, 5), sink.last_osc_len);
}

test "parser dispatch: OSC terminated by ST (ESC \\)" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b]url\x1b\\");

    try std.testing.expectEqual(EventKind.osc, sink.last_event_kind);
    try std.testing.expectEqual(parser_mod.OscTerminator.st, sink.last_osc_term);
    try std.testing.expectEqual(@as(usize, 3), sink.last_osc_len);
}

test "parser dispatch: APC terminated by ST" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b_kitty\x1b\\");

    try std.testing.expectEqual(EventKind.apc, sink.last_event_kind);
    try std.testing.expectEqual(@as(usize, 5), sink.last_apc_len);
}

test "parser dispatch: DCS terminated by ST" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1bPdata\x1b\\");

    try std.testing.expectEqual(EventKind.dcs, sink.last_event_kind);
    try std.testing.expectEqual(@as(usize, 4), sink.last_dcs_len);
}

test "parser dispatch: UTF-8 + ASCII interaction" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("A\xE2\x82\xACB");

    try std.testing.expect(sink.event_count >= 2);
}

test "parser dispatch: OSC with stray ESC (continuation)" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b]data\x1bmore\x1b\\");

    try std.testing.expectEqual(EventKind.osc, sink.last_event_kind);
    try std.testing.expect(sink.last_osc_len >= 4);
}

test "parser dispatch: CSI with params" {
    const gpa = std.testing.allocator;
    var sink = TestSink{};
    var parser = try parser_mod.Parser.init(gpa, sink.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b[1;31;40m");

    try std.testing.expectEqual(EventKind.csi, sink.last_event_kind);
    try std.testing.expectEqual(@as(u8, 'm'), sink.last_csi_final);
    try std.testing.expectEqual(@as(i32, 1), sink.last_csi_params[0]);
    try std.testing.expectEqual(@as(i32, 31), sink.last_csi_params[1]);
    try std.testing.expectEqual(@as(i32, 40), sink.last_csi_params[2]);
    try std.testing.expectEqual(@as(u8, 2), sink.last_csi_count);
}
