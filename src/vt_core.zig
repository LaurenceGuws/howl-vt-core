//! Responsibility: provide host-neutral facade over parser/pipeline/screen.
//! Ownership: interface boundary.
//! Reason: compose feed/apply/state-access operations in one deterministic surface.

const std = @import("std");
const pipeline_mod = @import("event/pipeline.zig");
const screen_mod = @import("screen/state.zig");
const keymap = @import("input/keymap.zig");
const mouse = @import("input/mouse.zig");
const model_selection = @import("state/selection.zig");
const model_snapshot = @import("state/snapshot.zig");

/// Host-neutral terminal facade.
pub const VtCore = struct {
    /// Host control signals routed to transport/runtime owner.
    pub const ControlSignal = enum {
        hangup,
        interrupt,
        terminate,
        resize_notify,
    };

    /// Key type alias exported by vt-core facade.
    pub const Key = keymap.Key;
    /// Modifier type alias exported by vt-core facade.
    pub const Modifier = keymap.Modifier;

    /// No modifiers set.
    pub const mod_none: Modifier = keymap.VTERM_MOD_NONE;
    /// Shift modifier bit.
    pub const mod_shift: Modifier = keymap.VTERM_MOD_SHIFT;
    /// Alt modifier bit.
    pub const mod_alt: Modifier = keymap.VTERM_MOD_ALT;
    /// Control modifier bit.
    pub const mod_ctrl: Modifier = keymap.VTERM_MOD_CTRL;

    /// Enter key alias.
    pub const key_enter: Key = keymap.VTERM_KEY_ENTER;
    /// Tab key alias.
    pub const key_tab: Key = keymap.VTERM_KEY_TAB;
    /// Backspace key alias.
    pub const key_backspace: Key = keymap.VTERM_KEY_BACKSPACE;
    /// Escape key alias.
    pub const key_escape: Key = keymap.VTERM_KEY_ESCAPE;
    /// Arrow up key alias.
    pub const key_up: Key = keymap.VTERM_KEY_UP;
    /// Arrow down key alias.
    pub const key_down: Key = keymap.VTERM_KEY_DOWN;
    /// Arrow left key alias.
    pub const key_left: Key = keymap.VTERM_KEY_LEFT;
    /// Arrow right key alias.
    pub const key_right: Key = keymap.VTERM_KEY_RIGHT;
    /// Insert key alias.
    pub const key_insert: Key = keymap.VTERM_KEY_INS;
    /// Delete key alias.
    pub const key_delete: Key = keymap.VTERM_KEY_DEL;
    /// Home key alias.
    pub const key_home: Key = keymap.VTERM_KEY_HOME;
    /// End key alias.
    pub const key_end: Key = keymap.VTERM_KEY_END;
    /// Page-up key alias.
    pub const key_pageup: Key = keymap.VTERM_KEY_PAGEUP;
    /// Page-down key alias.
    pub const key_pagedown: Key = keymap.VTERM_KEY_PAGEDOWN;
    /// F1 key alias.
    pub const key_f1: Key = keymap.VTERM_KEY_F1;
    /// F2 key alias.
    pub const key_f2: Key = keymap.VTERM_KEY_F2;
    /// F3 key alias.
    pub const key_f3: Key = keymap.VTERM_KEY_F3;
    /// F4 key alias.
    pub const key_f4: Key = keymap.VTERM_KEY_F4;
    /// F5 key alias.
    pub const key_f5: Key = keymap.VTERM_KEY_F5;
    /// F6 key alias.
    pub const key_f6: Key = keymap.VTERM_KEY_F6;
    /// F7 key alias.
    pub const key_f7: Key = keymap.VTERM_KEY_F7;
    /// F8 key alias.
    pub const key_f8: Key = keymap.VTERM_KEY_F8;
    /// F9 key alias.
    pub const key_f9: Key = keymap.VTERM_KEY_F9;
    /// F10 key alias.
    pub const key_f10: Key = keymap.VTERM_KEY_F10;
    /// F11 key alias.
    pub const key_f11: Key = keymap.VTERM_KEY_F11;
    /// F12 key alias.
    pub const key_f12: Key = keymap.VTERM_KEY_F12;

    /// Read-only render-facing view of visible terminal state.
    pub const RenderView = struct {
        rows: u16,
        cols: u16,
        cursor_row: u16,
        cursor_col: u16,
        cursor_visible: bool,
        screen: *const screen_mod.ScreenState,

        pub fn cellAt(self: RenderView, row: u16, col: u16) u21 {
            return self.screen.cellAt(row, col);
        }
    };

    allocator: std.mem.Allocator,
    pipeline: pipeline_mod.Pipeline,
    state: screen_mod.ScreenState,
    selection: model_selection.SelectionState,
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
            .selection = model_selection.SelectionState.init(),
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
            .selection = model_selection.SelectionState.init(),
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
            .selection = model_selection.SelectionState.init(),
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

    /// Resize visible screen while preserving history ring contents.
    pub fn resize(self: *VtCore, rows: u16, cols: u16) !void {
        try self.state.resize(self.allocator, rows, cols);
        if (self.selection.selection.active) {
            if (self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.start.row) or
                self.state.shouldInvalidateSelectionEndpoint(self.selection.selection.end.row))
            {
                self.selection.clear();
            }
        }
    }

    /// Return read-only screen state reference.
    pub fn screen(self: *const VtCore) *const screen_mod.ScreenState {
        return &self.state;
    }

    /// Return a stable render-facing snapshot view of visible state.
    pub fn renderView(self: *const VtCore) RenderView {
        return .{
            .rows = self.state.rows,
            .cols = self.state.cols,
            .cursor_row = self.state.cursor_row,
            .cursor_col = self.state.cursor_col,
            .cursor_visible = self.state.cursor_visible,
            .screen = &self.state,
        };
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
    pub fn selectionState(self: *const VtCore) ?model_selection.TerminalSelection {
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
    pub fn encodeKey(self: *VtCore, key: keymap.Key, mod: keymap.Modifier) []const u8 {
        var len: usize = 0;

        const shift_active = (mod & keymap.VTERM_MOD_SHIFT) != 0;

        switch (key) {
            keymap.VTERM_KEY_ENTER => {
                self.encode_buf[0] = '\r';
                len = 1;
            },
            keymap.VTERM_KEY_TAB => {
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
            keymap.VTERM_KEY_BACKSPACE => {
                self.encode_buf[0] = '\x7f';
                len = 1;
            },
            keymap.VTERM_KEY_ESCAPE => {
                self.encode_buf[0] = '\x1b';
                len = 1;
            },
            keymap.VTERM_KEY_UP => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_DOWN => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_RIGHT => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_LEFT => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_HOME => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_END => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_INS => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_DEL => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '3';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_PAGEUP => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '5';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_PAGEDOWN => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '6';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[3] = ';';
                    self.encode_buf[4] = '0' + (1 + mod);
                    self.encode_buf[5] = '~';
                    len = 6;
                } else {
                    self.encode_buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_F1 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F2 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F3 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F4 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F5 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '5';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F6 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '7';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F7 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '8';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F8 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '1';
                self.encode_buf[3] = '9';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F9 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '0';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F10 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '1';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F11 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '3';
                if (mod != keymap.VTERM_MOD_NONE) {
                    self.encode_buf[4] = ';';
                    self.encode_buf[5] = '0' + (1 + mod);
                    self.encode_buf[6] = '~';
                    len = 7;
                } else {
                    self.encode_buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F12 => {
                self.encode_buf[0] = '\x1b';
                self.encode_buf[1] = '[';
                self.encode_buf[2] = '2';
                self.encode_buf[3] = '4';
                if (mod != keymap.VTERM_MOD_NONE) {
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
    pub fn encodeMouse(self: *VtCore, event: mouse.MouseEvent) []const u8 {
        _ = event;
        return self.encode_buf[0..0];
    }

    /// Parse host key token into vt-core key constant.
    pub fn parseKeyToken(name: []const u8) ?Key {
        if (std.mem.eql(u8, name, "KEYCODE_ENTER")) return key_enter;
        if (std.mem.eql(u8, name, "KEYCODE_TAB")) return key_tab;
        if (std.mem.eql(u8, name, "KEYCODE_DEL")) return key_backspace;
        if (std.mem.eql(u8, name, "KEYCODE_ESCAPE")) return key_escape;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_UP")) return key_up;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_DOWN")) return key_down;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_LEFT")) return key_left;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_RIGHT")) return key_right;
        if (std.mem.eql(u8, name, "KEYCODE_INSERT")) return key_insert;
        if (std.mem.eql(u8, name, "KEYCODE_FORWARD_DEL")) return key_delete;
        if (std.mem.eql(u8, name, "KEYCODE_MOVE_HOME")) return key_home;
        if (std.mem.eql(u8, name, "KEYCODE_MOVE_END")) return key_end;
        if (std.mem.eql(u8, name, "KEYCODE_PAGE_UP")) return key_pageup;
        if (std.mem.eql(u8, name, "KEYCODE_PAGE_DOWN")) return key_pagedown;
        if (std.mem.eql(u8, name, "KEYCODE_F1")) return key_f1;
        if (std.mem.eql(u8, name, "KEYCODE_F2")) return key_f2;
        if (std.mem.eql(u8, name, "KEYCODE_F3")) return key_f3;
        if (std.mem.eql(u8, name, "KEYCODE_F4")) return key_f4;
        if (std.mem.eql(u8, name, "KEYCODE_F5")) return key_f5;
        if (std.mem.eql(u8, name, "KEYCODE_F6")) return key_f6;
        if (std.mem.eql(u8, name, "KEYCODE_F7")) return key_f7;
        if (std.mem.eql(u8, name, "KEYCODE_F8")) return key_f8;
        if (std.mem.eql(u8, name, "KEYCODE_F9")) return key_f9;
        if (std.mem.eql(u8, name, "KEYCODE_F10")) return key_f10;
        if (std.mem.eql(u8, name, "KEYCODE_F11")) return key_f11;
        if (std.mem.eql(u8, name, "KEYCODE_F12")) return key_f12;
        return null;
    }

    /// Parse host modifier bitfield into vt-core modifier mask.
    pub fn parseModifierBits(mods: i32) Modifier {
        var out: Modifier = mod_none;
        if ((mods & 0x01) != 0) out |= mod_ctrl;
        if ((mods & 0x02) != 0) out |= mod_alt;
        if ((mods & 0x04) != 0) out |= mod_shift;
        return out;
    }

    /// Parse host control token into control signal.
    pub fn parseControlToken(name: []const u8) ?ControlSignal {
        if (std.mem.eql(u8, name, "interrupt")) return .interrupt;
        if (std.mem.eql(u8, name, "terminate")) return .terminate;
        return null;
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
    pub fn snapshot(self: *const VtCore) !model_snapshot.VtCoreSnapshot {
        return model_snapshot.VtCoreSnapshot.captureFromScreen(
            self.allocator,
            &self.state,
            self.selection.state(),
        );
    }
};

test "VtCore facade methods remain available" {
    try std.testing.expect(@hasDecl(VtCore, "init"));
    try std.testing.expect(@hasDecl(VtCore, "initWithCells"));
    try std.testing.expect(@hasDecl(VtCore, "deinit"));
    try std.testing.expect(@hasDecl(VtCore, "feedByte"));
    try std.testing.expect(@hasDecl(VtCore, "feedSlice"));
    try std.testing.expect(@hasDecl(VtCore, "apply"));
    try std.testing.expect(@hasDecl(VtCore, "clear"));
    try std.testing.expect(@hasDecl(VtCore, "reset"));
    try std.testing.expect(@hasDecl(VtCore, "resetScreen"));
    try std.testing.expect(@hasDecl(VtCore, "resize"));
    try std.testing.expect(@hasDecl(VtCore, "screen"));
    try std.testing.expect(@hasDecl(VtCore, "queuedEventCount"));
}

test "VtCore method signatures remain host-facing" {
    const Allocator = std.mem.Allocator;
    const ScreenState = screen_mod.ScreenState;
    const init_fn: fn (Allocator, u16, u16) anyerror!VtCore = VtCore.init;
    const init_cells_fn: fn (Allocator, u16, u16) anyerror!VtCore = VtCore.initWithCells;
    const deinit_fn: fn (*VtCore) void = VtCore.deinit;
    const feed_byte_fn: fn (*VtCore, u8) void = VtCore.feedByte;
    const feed_slice_fn: fn (*VtCore, []const u8) void = VtCore.feedSlice;
    const apply_fn: fn (*VtCore) void = VtCore.apply;
    const clear_fn: fn (*VtCore) void = VtCore.clear;
    const reset_fn: fn (*VtCore) void = VtCore.reset;
    const reset_screen_fn: fn (*VtCore) void = VtCore.resetScreen;
    const resize_fn: fn (*VtCore, u16, u16) anyerror!void = VtCore.resize;
    const screen_fn: fn (*const VtCore) *const ScreenState = VtCore.screen;
    const queue_fn: fn (*const VtCore) usize = VtCore.queuedEventCount;
    _ = .{ init_fn, init_cells_fn, deinit_fn, feed_byte_fn, feed_slice_fn, apply_fn, clear_fn, reset_fn, reset_screen_fn, resize_fn, screen_fn, queue_fn };
}

test "const-read history and selection accessors stay stable" {
    const history_row_fn: fn (*const VtCore, u16, u16) u21 = VtCore.historyRowAt;
    const history_count_fn: fn (*const VtCore) u16 = VtCore.historyCount;
    const history_capacity_fn: fn (*const VtCore) u16 = VtCore.historyCapacity;
    const selection_state_fn: fn (*const VtCore) ?model_selection.TerminalSelection = VtCore.selectionState;
    _ = .{ history_row_fn, history_count_fn, history_capacity_fn, selection_state_fn };
}

test "lifecycle extension methods stay stable" {
    const init_cells_history_fn: fn (std.mem.Allocator, u16, u16, u16) anyerror!VtCore = VtCore.initWithCellsAndHistory;
    const selection_start_fn: fn (*VtCore, i32, u16) void = VtCore.selectionStart;
    const selection_update_fn: fn (*VtCore, i32, u16) void = VtCore.selectionUpdate;
    const selection_finish_fn: fn (*VtCore) void = VtCore.selectionFinish;
    const selection_clear_fn: fn (*VtCore) void = VtCore.selectionClear;
    _ = .{ init_cells_history_fn, selection_start_fn, selection_update_fn, selection_finish_fn, selection_clear_fn };
}

test "snapshot surface remains deterministic" {
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("TEST");
    vt_core.apply();

    var snap1 = try vt_core.snapshot();
    defer snap1.deinit();

    var snap2 = try vt_core.snapshot();
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.rows, snap2.rows);
    try std.testing.expectEqual(snap1.cols, snap2.cols);
    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
}

test "resize keeps history enabled state" {
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCellsAndHistory(allocator, 1, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("111\n222\n333");
    vt_core.apply();
    const before = vt_core.historyCount();
    try vt_core.resize(3, 3);

    try std.testing.expectEqual(@as(u16, 8), vt_core.historyCapacity());
    try std.testing.expect(vt_core.historyCount() <= before);
}

test "encodeKey and encodeMouse methods are callable" {
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    const encode_key_fn: fn (*VtCore, keymap.Key, keymap.Modifier) []const u8 = VtCore.encodeKey;
    const encode_mouse_fn: fn (*VtCore, mouse.MouseEvent) []const u8 = VtCore.encodeMouse;
    _ = .{ encode_key_fn, encode_mouse_fn };

    vt_core.feedSlice("TEST");
    vt_core.apply();

    var snap_before = try vt_core.snapshot();
    defer snap_before.deinit();

    _ = vt_core.encodeKey('A', 0);
    _ = vt_core.encodeKey('B', 0);

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
}

test "encodeMouse returns empty output and does not mutate state" {
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("HELLO");
    vt_core.apply();

    var snap_before = try vt_core.snapshot();
    defer snap_before.deinit();

    const mouse_event = mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };

    const output = vt_core.encodeMouse(mouse_event);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    try std.testing.expectEqualSlices(u8, "", output);

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
}

test "VtCore exposes key and modifier constants" {
    _ = VtCore.mod_none;
    _ = VtCore.mod_shift;
    _ = VtCore.mod_alt;
    _ = VtCore.mod_ctrl;
    _ = VtCore.key_enter;
    _ = VtCore.key_tab;
    _ = VtCore.key_backspace;
    _ = VtCore.key_escape;
    _ = VtCore.key_up;
    _ = VtCore.key_down;
    _ = VtCore.key_left;
    _ = VtCore.key_right;
}
