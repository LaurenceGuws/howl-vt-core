//! Host-neutral terminal engine facade.
//! Composes parser, pipeline, and screen into a single runtime interface.
//! No behavioral changes to underlying components; this is a convenience surface.

const pipeline_mod = @import("../event/pipeline.zig");
const screen_mod = @import("../screen/state.zig");

pub const Engine = struct {
    allocator: std.mem.Allocator,
    pipeline: pipeline_mod.Pipeline,
    screen: screen_mod.ScreenState,

    /// Initialize engine without cell buffer (screen cursor-only).
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Engine {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        const screen = screen_mod.ScreenState.init(rows, cols);
        return Engine{
            .allocator = allocator,
            .pipeline = pipeline,
            .screen = screen,
        };
    }

    /// Initialize engine with cell buffer (full screen state).
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Engine {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var screen = try screen_mod.ScreenState.initWithCells(allocator, rows, cols);
        errdefer screen.deinit(allocator);
        return Engine{
            .allocator = allocator,
            .pipeline = pipeline,
            .screen = screen,
        };
    }

    /// Deinitialize engine and release all resources.
    pub fn deinit(self: *Engine) void {
        self.screen.deinit(self.allocator);
        self.pipeline.deinit();
    }

    /// Feed a single byte to the engine.
    pub fn feedByte(self: *Engine, byte: u8) void {
        self.pipeline.feedByte(byte);
    }

    /// Feed a slice of bytes to the engine.
    pub fn feedSlice(self: *Engine, bytes: []const u8) void {
        self.pipeline.feedSlice(bytes);
    }

    /// Apply pending bridge events to screen state.
    /// Drains the event queue and updates screen accordingly.
    pub fn apply(self: *Engine) void {
        self.pipeline.applyToScreen(&self.screen);
    }

    /// Clear pending bridge events without applying to screen.
    pub fn clear(self: *Engine) void {
        self.pipeline.clear();
    }

    /// Reset parser and clear pending events.
    pub fn reset(self: *Engine) void {
        self.pipeline.reset();
    }

    /// Get const reference to current screen state.
    pub fn screen(self: *const Engine) *const screen_mod.ScreenState {
        return &self.screen;
    }

    /// Get count of pending bridge events before apply.
    pub fn queuedEventCount(self: *const Engine) usize {
        return self.pipeline.len();
    }
};
