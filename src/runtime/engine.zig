//! Runtime Interface — host-neutral terminal engine facade.
//! Responsibility: compose parser, pipeline, and screen behind a small facade for host embedding.
//! Ownership: portable terminal runtime surface for M1-M4 behavior (parser→screen pipeline, history, selection, input encoding).
//! Authority: RUNTIME_API.md contract defines all stable method behavior, lifecycle invariants, and mutation boundaries.

const std = @import("std");
const pipeline_mod = @import("../event/pipeline.zig");
const screen_mod = @import("../screen/state.zig");
const model_mod = @import("../model.zig");

/// Host-neutral terminal engine: composes parser, pipeline, screen, history, selection, and input encoding.
/// Provides deterministic M1-M4 runtime behavior without platform policy or host lifecycle ownership.
/// See RUNTIME_API.md for detailed method behavior, lifecycle matrix, and mutation boundaries.
pub const Engine = struct {
    allocator: std.mem.Allocator,
    pipeline: pipeline_mod.Pipeline,
    state: screen_mod.ScreenState,
    selection: model_mod.SelectionState,
    encode_buf: [64]u8 = undefined,
    encode_len: usize = 0,

    /// Initialize engine with cursor-only screen state (no cell storage).
    /// Allocator ownership: caller owns allocator lifetime; engine calls deinit(allocator) for cleanup.
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

    /// Initialize engine with cell buffer (full screen state storage).
    /// Engine owns cell buffer; caller must call deinit(allocator) to release.
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

    /// Initialize engine with cell buffer and bounded history buffer (M3+).
    /// history_capacity: max rows retained in scrollback (0 = no history).
    /// Engine owns cell and history buffers; caller must call deinit(allocator) to release.
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

    /// Feed a single byte to parser; queues events without applying to screen.
    /// Mutates: parser state, pipeline queue. Reads: input byte.
    pub fn feedByte(self: *Engine, byte: u8) void {
        self.pipeline.feedByte(byte);
    }

    /// Feed multiple bytes to parser; queues events without applying to screen.
    /// Split-feed chunking does not change final behavior vs. feeding same bytes as one slice.
    /// Mutates: parser state, pipeline queue. Reads: input bytes.
    pub fn feedSlice(self: *Engine, bytes: []const u8) void {
        self.pipeline.feedSlice(bytes);
    }

    /// Apply queued events to screen; drains queue and updates screen accordingly.
    /// Invalidates selection if a history row it references was evicted (M3+).
    /// Idempotent: multiple apply() calls without intervening feed are no-ops.
    /// Mutates: screen state, pipeline queue. Reads: queued events.
    pub fn apply(self: *Engine) void {
        self.pipeline.applyToScreen(&self.state);
        if (self.selection.selection.active) {
            if (self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.start.row) or
                self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.end.row)) {
                self.selection.clear();
            }
        }
    }

    /// Clear queued events without applying to screen; parser and screen unchanged.
    /// Mutates: pipeline queue (empties). Reads: none.
    pub fn clear(self: *Engine) void {
        self.pipeline.clear();
    }

    /// Reset parser to initial state and clear queued events; screen modes preserved.
    /// Preserves: cursor_visible and auto_wrap modes from current screen state.
    /// Mutates: parser state, pipeline queue. Reads: screen mode state.
    pub fn reset(self: *Engine) void {
        self.pipeline.reset();
    }

    /// Clear screen state (cells, cursor) without changing parser or queue.
    /// Restores: cursor to origin, cells to blank, cursor_visible to true, auto_wrap to true.
    /// Does not truncate history; only affects visible screen buffer.
    /// Mutates: screen cells, cursor, wrap state. Reads: screen dimensions, history storage.
    pub fn resetScreen(self: *Engine) void {
        self.state.reset();
    }

    /// Get const reference to current screen state for safe inspection.
    /// Returns: read-only snapshot of visible screen state (cursor, mode state, dimensions).
    /// Mutates: none. Reads: screen state.
    pub fn screen(self: *const Engine) *const screen_mod.ScreenState {
        return &self.state;
    }

    /// Get count of pending bridge events in queue before apply.
    /// Useful for detecting whether apply() will mutate screen state.
    /// Mutates: none. Reads: pipeline queue.
    pub fn queuedEventCount(self: *const Engine) usize {
        return self.pipeline.len();
    }

    /// Get const cell codepoint from history buffer at recency index and column (M3+).
    /// history_idx: 0=most recent history row; higher indices are older rows.
    /// Returns: codepoint U+0000 if index out of bounds; otherwise cell codepoint.
    /// Mutates: none. Reads: history buffer.
    pub fn historyRowAt(self: *const Engine, history_idx: u16, col: u16) u21 {
        return self.state.historyRowAt(history_idx, col);
    }

    /// Get current number of rows in history buffer (M3+).
    /// Returns: count from 0 (empty) to historyCapacity.
    /// Mutates: none. Reads: history metadata.
    pub fn historyCount(self: *const Engine) u16 {
        return self.state.historyCount();
    }

    /// Get maximum capacity of history buffer (M3+).
    /// Returns: configured history capacity; 0 if no history initialized.
    /// Mutates: none. Reads: history metadata.
    pub fn historyCapacity(self: *const Engine) u16 {
        return self.state.historyCapacity();
    }

    /// Get current selection state when active; null if inactive or cleared (M3+).
    /// Returns: snapshot of active selection (start, end, active status) or null.
    /// Mutates: none. Reads: selection state.
    pub fn selectionState(self: *const Engine) ?model_mod.TerminalSelection {
        return self.selection.state();
    }

    /// Begin new selection at (row, col); row supports history coordinates (M3+).
    /// row: i32 (non-negative=viewport, negative=history via M3 signed coordinate model).
    /// Marks selection active until cleared or invalidated by history eviction.
    /// Mutates: selection state (active, start, end). Reads: input coordinates.
    pub fn selectionStart(self: *Engine, row: i32, col: u16) void {
        self.selection.start(row, col);
    }

    /// Update selection end position while active; no-op if inactive (M3+).
    /// Allows selection to extend across viewport and history coordinates.
    /// Mutates: selection end position (if active). Reads: input coordinates.
    pub fn selectionUpdate(self: *Engine, row: i32, col: u16) void {
        self.selection.update(row, col);
    }

    /// Mark active selection as finished; selection remains accessible until clear (M3+).
    /// Allows host to query final selection state after user interaction ends.
    /// Mutates: selection state. Reads: none.
    pub fn selectionFinish(self: *Engine) void {
        self.selection.finish();
    }

    /// Clear current selection and mark inactive (M3+).
    /// Selection state becomes null until next selectionStart.
    /// Mutates: selection state. Reads: none.
    pub fn selectionClear(self: *Engine) void {
        self.selection.clear();
    }

    /// Encode logical key + modifier combination to control byte sequence (M4+).
    /// Returns: byte slice containing control bytes for this key+modifier; valid only until next encode call.
    /// Deterministic: same key+modifier always produces same output, independent of screen/parser state.
    /// Mutates: internal encode buffer only. Reads: input key and modifier flags.
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
    /// Current behavior: placeholder surface that returns empty slice (no mouse reporting implemented in M4).
    /// Does NOT mutate event, screen, parser, history, or selection state.
    /// Deterministic: identical input always returns same output (currently always empty).
    /// Mutates: internal encode buffer only. Reads: input event.
    pub fn encodeMouse(self: *Engine, event: model_mod.MouseEvent) []const u8 {
        _ = event;
        return self.encode_buf[0..0];
    }
};
