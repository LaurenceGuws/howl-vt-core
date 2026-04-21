const std = @import("std");
const parser_mod = @import("parser.zig");
const bridge_mod = @import("parser_core_event_bridge.zig");
const semantic_mod = @import("parser_core_semantic_consumer.zig");
const screen_mod = @import("terminal_screen_state.zig");

pub const CoreEvent = bridge_mod.CoreEvent;

pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    bridge: *bridge_mod.ParserCoreBridge,
    parser: parser_mod.Parser,

    pub fn init(allocator: std.mem.Allocator) !Pipeline {
        const bridge = try allocator.create(bridge_mod.ParserCoreBridge);
        bridge.* = bridge_mod.ParserCoreBridge.init(allocator);
        errdefer {
            bridge.deinit();
            allocator.destroy(bridge);
        }
        const p = try parser_mod.Parser.init(allocator, bridge.toSink());
        return .{ .allocator = allocator, .bridge = bridge, .parser = p };
    }

    pub fn deinit(self: *Pipeline) void {
        self.parser.deinit();
        self.bridge.deinit();
        self.allocator.destroy(self.bridge);
    }

    pub fn feedByte(self: *Pipeline, byte: u8) void {
        self.parser.handleByte(byte);
    }

    pub fn feedSlice(self: *Pipeline, bytes: []const u8) void {
        self.parser.handleSlice(bytes);
    }

    pub fn events(self: *const Pipeline) []const CoreEvent {
        return self.bridge.events.items;
    }

    pub fn len(self: *const Pipeline) usize {
        return self.bridge.len();
    }

    pub fn isEmpty(self: *const Pipeline) bool {
        return self.bridge.isEmpty();
    }

    pub fn clear(self: *Pipeline) void {
        self.bridge.clear();
    }

    pub fn reset(self: *Pipeline) void {
        self.bridge.clear();
        self.parser.reset();
    }

    pub fn applyToScreen(self: *Pipeline, screen: *screen_mod.ScreenState) void {
        for (self.bridge.events.items) |ev| {
            if (semantic_mod.process(ev)) |sem_ev| {
                screen.apply(sem_ev);
            }
        }
        self.bridge.clear();
    }
};
