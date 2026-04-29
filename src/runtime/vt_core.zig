//! Responsibility: provide host-neutral facade over parser/pipeline/screen.
//! Ownership: interface boundary.
//! Reason: compose feed/apply/state-access operations in one deterministic surface.

const std = @import("std");
const pipeline_mod = @import("../event/pipeline.zig");
const screen_mod = @import("../screen/state.zig");
const model_mod = @import("../model.zig");

/// Host-neutral terminal facade.
pub const VtCore = struct {
    allocator: std.mem.Allocator,
    pipeline: pipeline_mod.Pipeline,
    state: screen_mod.ScreenState,
    selection: model_mod.SelectionState,
    encode_buf: [64]u8 = undefined,
    encode_len: usize = 0,

    /// Initialize vt_core without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        const state = screen_mod.ScreenState.init(rows, cols);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .state = state,
            .selection = model_mod.SelectionState.init(),
        };
    }

    /// Initialize vt_core with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try screen_mod.ScreenState.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .state = state,
            .selection = model_mod.SelectionState.init(),
        };
    }

    /// Initialize vt_core with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !VtCore {
        var pipeline = try pipeline_mod.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try screen_mod.ScreenState.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .state = state,
            .selection = model_mod.SelectionState.init(),
        };
    }

    /// Release vt_core-owned resources.
    pub fn deinit(self: *VtCore) void {
        self.state.deinit(self.allocator);
        self.pipeline.deinit();
    }

    /// Feed one input byte into parser state.
    pub fn feedByte(self: *VtCore, byte: u8) void {
        self.pipeline.feedByte(byte);
    }

    /// Feed a byte slice into parser state.
    pub fn feedSlice(self: *VtCore, bytes: []const u8) void {
        self.pipeline.feedSlice(bytes);
    }

    /// Apply queued events to screen state.
    pub fn apply(self: *VtCore) void {
        self.pipeline.applyToScreen(&self.state);
        if (self.selection.selection.active) {
            if (self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.start.row) or
                self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.end.row))
            {
                self.selection.clear();
            }
        }
    }

    /// Clear queued events without applying.
    pub fn clear(self: *VtCore) void {
        self.pipeline.clear();
    }

    /// Reset parser state and clear queue.
    pub fn reset(self: *VtCore) void {
        self.pipeline.reset();
    }

    /// Reset visible screen state only.
    pub fn resetScreen(self: *VtCore) void {
        self.state.reset();
    }

    /// Return read-only screen state reference.
    pub fn screen(self: *const VtCore) *const screen_mod.ScreenState {
        return &self.state;
    }

    /// Return queued event count.
    pub fn queuedEventCount(self: *const VtCore) usize {
        return self.pipeline.len();
    }

    /// Return history cell by recency index and column.
    pub fn historyRowAt(self: *const VtCore, history_idx: u16, col: u16) u21 {
        return self.state.historyRowAt(history_idx, col);
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const VtCore) u16 {
        return self.state.historyCount();
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const VtCore) u16 {
        return self.state.historyCapacity();
    }

    /// Return active selection snapshot or null.
    pub fn selectionState(self: *const VtCore) ?model_mod.TerminalSelection {
        return self.selection.state();
    }

    /// Start selection at row/column coordinates.
    pub fn selectionStart(self: *VtCore, row: i32, col: u16) void {
        self.selection.start(row, col);
    }

    /// Update selection end coordinates.
    pub fn selectionUpdate(self: *VtCore, row: i32, col: u16) void {
        self.selection.update(row, col);
    }

    /// Finish current active selection.
    pub fn selectionFinish(self: *VtCore) void {
        self.selection.finish();
    }

    /// Clear current selection state.
    pub fn selectionClear(self: *VtCore) void {
        self.selection.clear();
    }

    /// Encode logical key and modifiers.
    pub fn encodeKey(self: *VtCore, key: model_mod.Key, mod: model_mod.Modifier) []const u8 {
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

    /// Encode mouse event payload (placeholder surface).
    pub fn encodeMouse(self: *VtCore, event: model_mod.MouseEvent) []const u8 {
        _ = event;
        return self.encode_buf[0..0];
    }

    /// Capture deterministic snapshot of vt_core observable state (SNAPSHOT_REPLAY api).
    ///
    /// Returns an VtCoreSnapshot containing visible cells, cursor, modes, history,
    /// and selection state at the time of the call. Snapshots are host-neutral and
    /// do not capture parser state, queued events, or internal encode buffers.
    ///
    /// Determinism: identical observable vt_core state produces identical snapshots.
    /// Identical byte sequences fed via feedByte/feedSlice, followed by apply(),
    /// produce identical snapshots regardless of how bytes are chunked.
    ///
    /// Memory: allocates owned copies of cell and history buffers. Caller must
    /// call snapshot.deinit() to release them when done.
    ///
    /// Error: returns allocation error if owned buffer allocation fails.
    pub fn snapshot(self: *const VtCore) !model_mod.VtCoreSnapshot {
        return model_mod.snapshot.VtCoreSnapshot.captureFromScreen(
            self.allocator,
            &self.state,
            self.selection.state(),
        );
    }
};
