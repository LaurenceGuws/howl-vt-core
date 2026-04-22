//! Responsibility: translate parser sink callbacks into owned event records.
//! Ownership: event bridge module.
//! Reason: isolate parser callback handling from semantic and screen layers.

const std = @import("std");
const parser_mod = @import("../parser/parser.zig");
const stream_mod = @import("../parser/stream.zig");
const csi_mod = @import("../parser/csi.zig");

/// Parser-facing event record emitted by the bridge queue.
pub const Event = union(enum) {
    text: []const u8,
    codepoint: u21,
    control: u8,
    style_change: struct {
        final: u8,
        params: [16]i32,
        param_count: u8,
    },
    title_set: []const u8,
    invalid_sequence,
};

/// Owns queued parser events and exposes a parser `Sink` implementation.
pub const Bridge = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),

    pub fn init(allocator: std.mem.Allocator) Bridge {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(Event).initCapacity(allocator, 32) catch unreachable,
        };
    }

    pub fn deinit(self: *Bridge) void {
        self.clear();
        self.events.deinit(self.allocator);
    }

    pub fn len(self: *const Bridge) usize {
        return self.events.items.len;
    }

    pub fn isEmpty(self: *const Bridge) bool {
        return self.events.items.len == 0;
    }

    pub fn clear(self: *Bridge) void {
        for (self.events.items) |event| {
            switch (event) {
                .text, .title_set => |data| self.allocator.free(data),
                else => {},
            }
        }
        self.events.clearRetainingCapacity();
    }

    pub fn drainInto(self: *Bridge, dest: *std.ArrayList(Event), dest_allocator: std.mem.Allocator) !void {
        try dest.appendSlice(dest_allocator, self.events.items);
        self.events.clearRetainingCapacity();
    }

    pub fn toSink(self: *Bridge) parser_mod.Sink {
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
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        const ce = switch (event) {
            .codepoint => |cp| Event{ .codepoint = cp },
            .control => |ctrl| Event{ .control = ctrl },
            .invalid => Event.invalid_sequence,
        };
        self.events.append(self.allocator, ce) catch {};
    }

    fn onAsciiSlice(ptr: *anyopaque, bytes: []const u8) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, bytes) catch return;
        self.events.append(self.allocator, Event{ .text = owned }) catch {};
    }

    fn onCsi(ptr: *anyopaque, action: csi_mod.CsiAction) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, Event{
            .style_change = .{
                .final = action.final,
                .params = action.params,
                .param_count = action.count,
            },
        }) catch {};
    }

    fn onOsc(ptr: *anyopaque, data: []const u8, term: parser_mod.OscTerminator) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        _ = term;
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .title_set = owned }) catch {};
    }

    fn onApc(_: *anyopaque, _: []const u8) void {}
    fn onDcs(_: *anyopaque, _: []const u8) void {}
    fn onEscFinal(_: *anyopaque, _: u8) void {}
};
