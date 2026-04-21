const std = @import("std");
const parser_mod = @import("parser.zig");

pub const CoreEvent = union(enum) {
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

pub const ParserCoreBridge = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(CoreEvent),

    pub fn init(allocator: std.mem.Allocator) ParserCoreBridge {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(CoreEvent).initCapacity(allocator, 32) catch unreachable,
        };
    }

    pub fn deinit(self: *ParserCoreBridge) void {
        self.clear();
        self.events.deinit(self.allocator);
    }

    pub fn len(self: *const ParserCoreBridge) usize {
        return self.events.items.len;
    }

    pub fn isEmpty(self: *const ParserCoreBridge) bool {
        return self.events.items.len == 0;
    }

    pub fn clear(self: *ParserCoreBridge) void {
        for (self.events.items) |event| {
            switch (event) {
                .text, .title_set => |data| self.allocator.free(data),
                else => {},
            }
        }
        self.events.clearRetainingCapacity();
    }

    pub fn drainInto(self: *ParserCoreBridge, dest: *std.ArrayList(CoreEvent), dest_allocator: std.mem.Allocator) !void {
        try dest.appendSlice(dest_allocator, self.events.items);
        self.events.clearRetainingCapacity();
    }

    pub fn toSink(self: *ParserCoreBridge) parser_mod.Sink {
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

    fn onStreamEvent(ptr: *anyopaque, event: parser_mod.stream.StreamEvent) void {
        const self: *ParserCoreBridge = @ptrCast(@alignCast(ptr));
        const ce = switch (event) {
            .codepoint => |cp| CoreEvent{ .codepoint = cp },
            .control => |ctrl| CoreEvent{ .control = ctrl },
            .invalid => CoreEvent.invalid_sequence,
        };
        self.events.append(self.allocator, ce) catch {};
    }

    fn onAsciiSlice(ptr: *anyopaque, bytes: []const u8) void {
        const self: *ParserCoreBridge = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, bytes) catch return;
        self.events.append(self.allocator, CoreEvent{ .text = owned }) catch {};
    }

    fn onCsi(ptr: *anyopaque, action: parser_mod.csi.CsiAction) void {
        const self: *ParserCoreBridge = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, CoreEvent{
            .style_change = .{
                .final = action.final,
                .params = action.params,
                .param_count = action.count,
            },
        }) catch {};
    }

    fn onOsc(ptr: *anyopaque, data: []const u8, term: parser_mod.OscTerminator) void {
        const self: *ParserCoreBridge = @ptrCast(@alignCast(ptr));
        _ = term;
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, CoreEvent{ .title_set = owned }) catch {};
    }

    fn onApc(_: *anyopaque, _: []const u8) void {}
    fn onDcs(_: *anyopaque, _: []const u8) void {}
    fn onEscFinal(_: *anyopaque, _: u8) void {}
};
