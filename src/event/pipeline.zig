//! Responsibility: coordinate parser feed, event queueing, and screen application flow.
//! Ownership: event pipeline module.
//! Reason: provide one seam for incremental byte ingestion and event draining.

const std = @import("std");
const parser_mod = @import("../parser/parser.zig");
const bridge_mod = @import("bridge.zig");
const semantic_mod = @import("semantic.zig");
const screen_mod = @import("../screen/state.zig");

/// Event type alias exposed by the pipeline surface.
pub const Event = bridge_mod.Event;

/// Parser + bridge orchestrator for incremental feed and screen application.
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    bridge: *bridge_mod.Bridge,
    parser: parser_mod.Parser,

    /// Initialize a parser/bridge pipeline with owned resources.
    pub fn init(allocator: std.mem.Allocator) !Pipeline {
        const bridge = try allocator.create(bridge_mod.Bridge);
        bridge.* = bridge_mod.Bridge.init(allocator);
        errdefer {
            bridge.deinit();
            allocator.destroy(bridge);
        }
        const p = try parser_mod.Parser.init(allocator, bridge.toSink());
        return .{ .allocator = allocator, .bridge = bridge, .parser = p };
    }

    /// Release parser and bridge resources owned by this pipeline.
    pub fn deinit(self: *Pipeline) void {
        self.parser.deinit();
        self.bridge.deinit();
        self.allocator.destroy(self.bridge);
    }

    /// Feed one byte into the parser stream.
    pub fn feedByte(self: *Pipeline, byte: u8) void {
        self.parser.handleByte(byte);
    }

    /// Feed a byte slice into the parser stream.
    pub fn feedSlice(self: *Pipeline, bytes: []const u8) void {
        self.parser.handleSlice(bytes);
    }

    /// Return a read-only view of currently queued bridge events.
    pub fn events(self: *const Pipeline) []const Event {
        return self.bridge.events.items;
    }

    /// Return the count of currently queued bridge events.
    pub fn len(self: *const Pipeline) usize {
        return self.bridge.len();
    }

    /// Return true when the bridge queue contains no events.
    pub fn isEmpty(self: *const Pipeline) bool {
        return self.bridge.isEmpty();
    }

    /// Drop queued bridge events without applying them.
    pub fn clear(self: *Pipeline) void {
        self.bridge.clear();
    }

    /// Reset parser state and clear queued bridge events.
    pub fn reset(self: *Pipeline) void {
        self.bridge.clear();
        self.parser.reset();
    }

    /// Apply queued events to `screen` in order, then clear the queue.
    pub fn applyToScreen(self: *Pipeline, screen: *screen_mod.ScreenState) void {
        for (self.bridge.events.items) |ev| {
            if (semantic_mod.process(ev)) |sem_ev| {
                screen.apply(sem_ev);
            }
        }
        self.bridge.clear();
    }
};
