//! Host-neutral terminal engine facade.
//! Composes parser, pipeline, and screen into a single runtime interface.
//! No behavioral changes to underlying components; this is a convenience surface.

const std = @import("std");
const pipeline_mod = @import("../event/pipeline.zig");
const screen_mod = @import("../screen/state.zig");

pub const Engine = struct {
    allocator: std.mem.Allocator,
    pipeline: pipeline_mod.Pipeline,
    state: screen_mod.ScreenState,

    /// Initialize engine without cell buffer (screen cursor-only).
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Engine {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        const state = screen_mod.ScreenState.init(rows, cols);
        return Engine{
            .allocator = allocator,
            .pipeline = pipeline,
            .state = state,
        };
    }

    /// Initialize engine with cell buffer (full screen state).
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Engine {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try screen_mod.ScreenState.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        return Engine{
            .allocator = allocator,
            .pipeline = pipeline,
            .state = state,
        };
    }

    /// Initialize engine with cell buffer and bounded history (M3+).
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Engine {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try screen_mod.ScreenState.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        return Engine{
            .allocator = allocator,
            .pipeline = pipeline,
            .state = state,
        };
    }

    /// Deinitialize engine and release all resources.
    pub fn deinit(self: *Engine) void {
        self.state.deinit(self.allocator);
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
        self.pipeline.applyToScreen(&self.state);
    }

    /// Clear pending bridge events without applying to screen.
    pub fn clear(self: *Engine) void {
        self.pipeline.clear();
    }

    /// Reset parser and clear pending events.
    pub fn reset(self: *Engine) void {
        self.pipeline.reset();
    }

    /// Reset screen state without changing parser state.
    pub fn resetScreen(self: *Engine) void {
        self.state.reset();
    }

    /// Get const reference to current screen state.
    pub fn screen(self: *const Engine) *const screen_mod.ScreenState {
        return &self.state;
    }

    /// Get count of pending bridge events before apply.
    pub fn queuedEventCount(self: *const Engine) usize {
        return self.pipeline.len();
    }

    /// Get const cell value from history at given history row and column (M3+).
    pub fn historyRowAt(self: *const Engine, history_idx: u16, col: u16) u21 {
        return self.state.historyRowAt(history_idx, col);
    }

    /// Get count of rows currently in history buffer (M3+).
    pub fn historyCount(self: *const Engine) u16 {
        return self.state.historyCount();
    }

    /// Get max capacity of history buffer (M3+).
    pub fn historyCapacity(self: *const Engine) u16 {
        return self.state.historyCapacity();
    }
};
