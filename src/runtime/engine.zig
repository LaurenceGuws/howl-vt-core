//! Host-neutral terminal engine facade.
//! Composes parser, pipeline, and screen into a single runtime interface.
//! No behavioral changes to underlying components; this is a convenience surface.

const std = @import("std");
const pipeline_mod = @import("../event/pipeline.zig");
const screen_mod = @import("../screen/state.zig");
const model_mod = @import("../model.zig");

/// Host-neutral runtime facade that composes pipeline, screen state, and selection.
pub const Engine = struct {
    allocator: std.mem.Allocator,
    pipeline: pipeline_mod.Pipeline,
    state: screen_mod.ScreenState,
    selection: model_mod.SelectionState,
    encode_buf: [64]u8 = undefined,
    encode_len: usize = 0,

    /// Initialize engine without cell buffer (screen cursor-only).
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Engine {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        const state = screen_mod.ScreenState.init(rows, cols);
        return Engine{
            .allocator = allocator,
            .pipeline = pipeline,
            .state = state,
            .selection = model_mod.SelectionState.init(),
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
            .selection = model_mod.SelectionState.init(),
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
            .selection = model_mod.SelectionState.init(),
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
    /// Invalidates selection if a history row it references was evicted (M3+).
    pub fn apply(self: *Engine) void {
        self.pipeline.applyToScreen(&self.state);
        if (self.selection.selection.active) {
            if (self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.start.row) or
                self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.end.row)) {
                self.selection.clear();
            }
        }
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

    /// Get current selection state when active; null if inactive (M3+).
    pub fn selectionState(self: *const Engine) ?model_mod.TerminalSelection {
        return self.selection.state();
    }

    /// Begin new selection at (row, col) (M3+).
    pub fn selectionStart(self: *Engine, row: i32, col: u16) void {
        self.selection.start(row, col);
    }

    /// Update selection end position while active (M3+).
    pub fn selectionUpdate(self: *Engine, row: i32, col: u16) void {
        self.selection.update(row, col);
    }

    /// Mark active selection as finished (M3+).
    pub fn selectionFinish(self: *Engine) void {
        self.selection.finish();
    }

    /// Clear current selection and mark inactive (M3+).
    pub fn selectionClear(self: *Engine) void {
        self.selection.clear();
    }

    /// Encode logical key + modifier to control byte sequence (M4+).
    /// Returns slice of encoded bytes; valid only until next encode call.
    pub fn encodeKey(self: *Engine, key: model_mod.Key, mod: model_mod.Modifier) []const u8 {
        var len: usize = 0;

        const shift_active = (mod & model_mod.VTERM_MOD_SHIFT) != 0;

        switch (key) {
            model_mod.VTERM_KEY_ENTER => {
                self.encode_buf[0] = '\r';
                len = 1;
            },
            model_mod.VTERM_KEY_TAB => {
                if (shift_active) {
                    self.encode_buf[0] = '\x1b';
                    self.encode_buf[1] = '[';
                    self.encode_buf[2] = 'Z';
                    len = 3;
                } else {
                    self.encode_buf[0] = '\t';
                    len = 1;
                }
            },
            model_mod.VTERM_KEY_BACKSPACE => {
                self.encode_buf[0] = '\x7f';
                len = 1;
            },
            model_mod.VTERM_KEY_ESCAPE => {
                self.encode_buf[0] = '\x1b';
                len = 1;
            },
            model_mod.VTERM_KEY_UP => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'A';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'A';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_DOWN => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'B';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'B';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_RIGHT => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'C';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'C';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_LEFT => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'D';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'D';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_HOME => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'H';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'H';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_END => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'F';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'F';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_INS => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            model_mod.VTERM_KEY_DEL => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '3';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            model_mod.VTERM_KEY_PAGEUP => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '5';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            model_mod.VTERM_KEY_PAGEDOWN => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '6';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            model_mod.VTERM_KEY_F1 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'P';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'P';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_F2 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'Q';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'Q';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_F3 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'R';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'R';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_F4 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[2] = '1';
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = 'S';
                    len = 6;
                } else {
                    self.encode_buf[2] = 'S';
                    len = 3;
                }
            },
            model_mod.VTERM_KEY_F5 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '5';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            model_mod.VTERM_KEY_F6 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '7';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            model_mod.VTERM_KEY_F7 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '8';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            model_mod.VTERM_KEY_F8 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '9';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            model_mod.VTERM_KEY_F9 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '0';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            model_mod.VTERM_KEY_F10 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '1';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            model_mod.VTERM_KEY_F11 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '3';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            model_mod.VTERM_KEY_F12 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '4';
                if (mod != model_mod.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            else => {
                if (key > 31 and key < 127) {
                    self.encode_buf[0] = @intCast(key);
                    len = 1;
                } else if (key > 127) {
                    len = std.unicode.utf8Encode(@intCast(key), self.encode_buf[0..]) catch 0;
                }
            },
        }

        self.encode_len = len;
        return self.encode_buf[0..len];
    }

    /// Encode mouse event to control byte sequence (M4+).
    /// Returns slice of encoded bytes; valid only until next encode call.
    /// Returns empty slice if mouse reporting is not active.
    pub fn encodeMouse(self: *Engine, event: model_mod.MouseEvent) []const u8 {
        _ = event;
        return self.encode_buf[0..0];
    }
};
