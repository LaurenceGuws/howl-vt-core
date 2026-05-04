//! Responsibility: provide the vt-core package entry owner.
//! Ownership: primary embeddable terminal boundary.
//! Reason: expose one host-neutral terminal object while keeping domain internals behind sibling owners.

const std = @import("std");
const grid_owner = @import("grid.zig");
const grid_model = @import("grid/model.zig");
const input_mod = @import("input.zig");
const interpret_owner = @import("interpret.zig");
const selection_owner = @import("selection.zig");
const snapshot_owner = @import("snapshot.zig");

const GridNs = grid_owner.Grid;
const Input = input_mod.Input;
const Interpret = interpret_owner.Interpret;
const Selection = selection_owner.Selection;
const Snapshot = snapshot_owner.Snapshot;

/// Host-neutral terminal facade.
pub const VtCore = struct {
    pub const DirtyRows = grid_model.DirtyRows;
    /// Host control signals routed to transport/runtime owner.
    pub const ControlSignal = enum {
        hangup,
        interrupt,
        terminate,
        resize_notify,
    };

    /// Key type alias exported by vt-core facade.
    pub const Key = Input.Key;
    /// Modifier type alias exported by vt-core facade.
    pub const Modifier = Input.Modifier;

    /// No modifiers set.
    pub const mod_none: Modifier = Input.mod_none;
    /// Shift modifier bit.
    pub const mod_shift: Modifier = Input.mod_shift;
    /// Alt modifier bit.
    pub const mod_alt: Modifier = Input.mod_alt;
    /// Control modifier bit.
    pub const mod_ctrl: Modifier = Input.mod_ctrl;

    /// Enter key alias.
    pub const key_enter: Key = Input.key_enter;
    /// Tab key alias.
    pub const key_tab: Key = Input.key_tab;
    /// Backspace key alias.
    pub const key_backspace: Key = Input.key_backspace;
    /// Escape key alias.
    pub const key_escape: Key = Input.key_escape;
    /// Arrow up key alias.
    pub const key_up: Key = Input.key_up;
    /// Arrow down key alias.
    pub const key_down: Key = Input.key_down;
    /// Arrow left key alias.
    pub const key_left: Key = Input.key_left;
    /// Arrow right key alias.
    pub const key_right: Key = Input.key_right;
    /// Insert key alias.
    pub const key_insert: Key = Input.key_insert;
    /// Delete key alias.
    pub const key_delete: Key = Input.key_delete;
    /// Home key alias.
    pub const key_home: Key = Input.key_home;
    /// End key alias.
    pub const key_end: Key = Input.key_end;
    /// Page-up key alias.
    pub const key_pageup: Key = Input.key_pageup;
    /// Page-down key alias.
    pub const key_pagedown: Key = Input.key_pagedown;
    /// F1 key alias.
    pub const key_f1: Key = Input.key_f1;
    /// F2 key alias.
    pub const key_f2: Key = Input.key_f2;
    /// F3 key alias.
    pub const key_f3: Key = Input.key_f3;
    /// F4 key alias.
    pub const key_f4: Key = Input.key_f4;
    /// F5 key alias.
    pub const key_f5: Key = Input.key_f5;
    /// F6 key alias.
    pub const key_f6: Key = Input.key_f6;
    /// F7 key alias.
    pub const key_f7: Key = Input.key_f7;
    /// F8 key alias.
    pub const key_f8: Key = Input.key_f8;
    /// F9 key alias.
    pub const key_f9: Key = Input.key_f9;
    /// F10 key alias.
    pub const key_f10: Key = Input.key_f10;
    /// F11 key alias.
    pub const key_f11: Key = Input.key_f11;
    /// F12 key alias.
    pub const key_f12: Key = Input.key_f12;

    /// Read-only render-facing view of visible terminal state.
    pub const RenderView = struct {
        rows: u16,
        cols: u16,
        cursor_row: u16,
        cursor_col: u16,
        cursor_visible: bool,
        cursor_shape: GridNs.CursorShape,
        is_alternate_screen: bool,
        screen: *const GridNs.GridModel,

        pub fn cellAt(self: RenderView, row: u16, col: u16) u21 {
            return self.screen.cellAt(row, col);
        }

        pub fn cellInfoAt(self: RenderView, row: u16, col: u16) GridNs.Cell {
            return self.screen.cellInfoAt(row, col);
        }
    };

    allocator: std.mem.Allocator,
    pipeline: Interpret.Pipeline,
    primary_state: GridNs.GridModel,
    alt_state: GridNs.GridModel,
    alt_active: bool,
    saved_primary_cursor: ?struct {
        row: u16,
        col: u16,
        wrap_pending: bool,
        cursor_visible: bool,
    } = null,
    selection: Selection.SelectionState,
    encode_buf: [64]u8 = undefined,
    encode_len: usize = 0,

    /// Initialize vt_core without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var pipeline = try Interpret.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        const state = Grid.GridModel.init(rows, cols);
        const alt_state = Grid.GridModel.init(rows, cols);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .primary_state = state,
            .alt_state = alt_state,
            .alt_active = false,
            .selection = Selection.SelectionState.init(),
        };
    }

    /// Initialize vt_core with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var pipeline = try Interpret.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try Grid.GridModel.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try Grid.GridModel.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .primary_state = state,
            .alt_state = alt_state,
            .alt_active = false,
            .selection = Selection.SelectionState.init(),
        };
    }

    /// Initialize vt_core with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !VtCore {
        var pipeline = try Interpret.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try Grid.GridModel.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try Grid.GridModel.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .primary_state = state,
            .alt_state = alt_state,
            .alt_active = false,
            .selection = Selection.SelectionState.init(),
        };
    }

    /// Release vt_core-owned resources.
    pub fn deinit(self: *VtCore) void {
        self.primary_state.deinit(self.allocator);
        self.alt_state.deinit(self.allocator);
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

    /// Apply queued events to the grid model.
    pub fn apply(self: *VtCore) void {
        for (self.pipeline.events()) |ev| {
            if (Interpret.process(ev)) |sem_ev| {
                self.applySemantic(sem_ev);
            }
        }
        self.pipeline.clear();
        self.selection.clearIfInvalidatedByGrid(self.activeState());
    }

    /// Clear queued events without applying.
    pub fn clear(self: *VtCore) void {
        self.pipeline.clear();
    }

    /// Reset parser state and clear queue.
    pub fn reset(self: *VtCore) void {
        self.pipeline.reset();
    }

    /// Reset visible grid state only.
    pub fn resetScreen(self: *VtCore) void {
        self.activeStateMut().reset();
    }

    /// Resize visible screen while preserving history ring contents.
    pub fn resize(self: *VtCore, rows: u16, cols: u16) !void {
        try self.primary_state.resize(self.allocator, rows, cols);
        try self.alt_state.resize(self.allocator, rows, cols);
        self.selection.clearIfInvalidatedByGrid(self.activeState());
    }

    /// Return read-only grid model reference.
    pub fn screen(self: *const VtCore) *const GridNs.GridModel {
        return self.activeState();
    }

    /// Return a stable render-facing snapshot view of visible state.
    pub fn renderView(self: *const VtCore) RenderView {
        return .{
            .rows = self.activeState().rows,
            .cols = self.activeState().cols,
            .cursor_row = self.activeState().cursor_row,
            .cursor_col = self.activeState().cursor_col,
            .cursor_visible = self.activeState().cursor_visible,
            .cursor_shape = self.activeState().cursor_style.shape,
            .is_alternate_screen = self.alt_active,
            .screen = self.activeState(),
        };
    }

    pub fn peekDirtyRows(self: *const VtCore) ?DirtyRows {
        return self.activeState().peekDirtyRows();
    }

    pub fn clearDirtyRows(self: *VtCore) void {
        self.activeStateMut().clearDirtyRows();
    }

    /// Return queued event count.
    pub fn queuedEventCount(self: *const VtCore) usize {
        return self.pipeline.len();
    }

    /// Return the most recent queued title-set event before apply clears the queue.
    pub fn latestTitleSet(self: *const VtCore) ?[]const u8 {
        var i = self.pipeline.events().len;
        while (i > 0) {
            i -= 1;
            const ev = self.pipeline.events()[i];
            switch (ev) {
                .title_set => |title| return title,
                else => {},
            }
        }
        return null;
    }

    /// Return history cell by recency index and column.
    pub fn historyRowAt(self: *const VtCore, history_idx: usize, col: u16) u21 {
        if (self.alt_active) return 0;
        return self.primary_state.historyRowAt(history_idx, col);
    }

    pub fn historyCellAt(self: *const VtCore, history_idx: usize, col: u16) GridNs.Cell {
        if (self.alt_active) return GridNs.default_cell;
        return self.primary_state.historyCellAt(history_idx, col);
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const VtCore) usize {
        if (self.alt_active) return 0;
        return self.primary_state.historyCount();
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const VtCore) u16 {
        return self.primary_state.historyCapacity();
    }

    pub fn isAlternateScreen(self: *const VtCore) bool {
        return self.alt_active;
    }

    /// Return active selection snapshot or null.
    pub fn selectionState(self: *const VtCore) ?Selection.TerminalSelection {
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
    pub fn encodeKey(self: *VtCore, key: Input.Key, mod: Input.Modifier) []const u8 {
        const encoded = Input.Codec.encodeKey(self.encode_buf[0..], key, mod);
        self.encode_len = encoded.len;
        return encoded;
    }

    /// Encode mouse event payload (placeholder surface).
    pub fn encodeMouse(self: *VtCore, event: Input.MouseEvent) []const u8 {
        const encoded = Input.Codec.encodeMouse(self.encode_buf[0..], event);
        self.encode_len = encoded.len;
        return encoded;
    }

    /// Parse host key token into vt-core key constant.
    pub fn parseKeyToken(name: []const u8) ?Key {
        return Input.Codec.parseKeyToken(name);
    }

    /// Parse host modifier bitfield into vt-core modifier mask.
    pub fn parseModifierBits(mods: i32) Modifier {
        return Input.Codec.parseModifierBits(mods);
    }

    /// Parse host control token into control signal.
    pub fn parseControlToken(name: []const u8) ?ControlSignal {
        if (std.mem.eql(u8, name, "interrupt")) return .interrupt;
        if (std.mem.eql(u8, name, "terminate")) return .terminate;
        return null;
    }

    /// Capture deterministic snapshot of vt_core observable state.
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
    pub fn snapshot(self: *const VtCore) !Snapshot.VtCoreSnapshot {
        return Snapshot.VtCoreSnapshot.captureFromScreen(
            self.allocator,
            self.activeState(),
            self.selection.state(),
        );
    }

    fn activeState(self: *const VtCore) *const GridNs.GridModel {
        return if (self.alt_active) &self.alt_state else &self.primary_state;
    }

    fn activeStateMut(self: *VtCore) *GridNs.GridModel {
        return if (self.alt_active) &self.alt_state else &self.primary_state;
    }

    fn applySemantic(self: *VtCore, sem_ev: Interpret.SemanticEvent) void {
        switch (sem_ev) {
            .enter_alt_screen => |opts| self.enterAltScreen(opts.clear, opts.save_cursor),
            .exit_alt_screen => |opts| self.exitAltScreen(opts.restore_cursor),
            else => self.activeStateMut().apply(sem_ev),
        }
    }

    fn enterAltScreen(self: *VtCore, clear_alt: bool, save_cursor: bool) void {
        if (save_cursor) {
            self.saved_primary_cursor = .{
                .row = self.primary_state.cursor_row,
                .col = self.primary_state.cursor_col,
                .wrap_pending = self.primary_state.wrap_pending,
                .cursor_visible = self.primary_state.cursor_visible,
            };
        }
        if (clear_alt) self.alt_state.reset();
        self.alt_active = true;
        self.selection.clear();
    }

    fn exitAltScreen(self: *VtCore, restore_cursor: bool) void {
        self.alt_active = false;
        if (restore_cursor) {
            if (self.saved_primary_cursor) |saved| {
                self.primary_state.cursor_row = @min(saved.row, self.primary_state.rows -| 1);
                self.primary_state.cursor_col = @min(saved.col, self.primary_state.cols -| 1);
                self.primary_state.wrap_pending = saved.wrap_pending;
                self.primary_state.cursor_visible = saved.cursor_visible;
            }
            self.saved_primary_cursor = null;
        }
        self.selection.clear();
    }
};

pub const Grid = grid_owner.Grid;

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
    const GridModel = GridNs.GridModel;
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
    const screen_fn: fn (*const VtCore) *const GridModel = VtCore.screen;
    const queue_fn: fn (*const VtCore) usize = VtCore.queuedEventCount;
    _ = .{ init_fn, init_cells_fn, deinit_fn, feed_byte_fn, feed_slice_fn, apply_fn, clear_fn, reset_fn, reset_screen_fn, resize_fn, screen_fn, queue_fn };
}

test "const-read history and selection accessors stay stable" {
    const history_row_fn: fn (*const VtCore, usize, u16) u21 = VtCore.historyRowAt;
    const history_count_fn: fn (*const VtCore) usize = VtCore.historyCount;
    const history_capacity_fn: fn (*const VtCore) u16 = VtCore.historyCapacity;
    const selection_state_fn: fn (*const VtCore) ?Selection.TerminalSelection = VtCore.selectionState;
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

test "alternate screen exit preserves primary scrollback" {
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCellsAndHistory(allocator, 2, 4, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("AAAA\nBBBB\nCCCC\nDDDD");
    vt_core.apply();
    var before = try vt_core.snapshot();
    defer before.deinit();
    const history_before = vt_core.historyCount();
    try std.testing.expect(history_before > 0);

    vt_core.feedSlice("\x1b[?1049hALT!");
    vt_core.apply();
    try std.testing.expect(vt_core.isAlternateScreen());
    try std.testing.expectEqual(@as(usize, 0), vt_core.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), vt_core.screen().cellAt(0, 0));

    vt_core.feedSlice("\x1b[?1049l");
    vt_core.apply();
    var after = try vt_core.snapshot();
    defer after.deinit();
    try std.testing.expect(!vt_core.isAlternateScreen());
    try std.testing.expectEqual(history_before, vt_core.historyCount());
    try std.testing.expectEqual(before.cursor_row, after.cursor_row);
    try std.testing.expectEqual(before.cursor_col, after.cursor_col);
    var row: u16 = 0;
    while (row < before.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < before.cols) : (col += 1) {
            try std.testing.expectEqual(before.cellAt(row, col), after.cellAt(row, col));
        }
    }
}

test "alternate screen 1049 restores primary cursor" {
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[3;4H\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    vt_core.apply();
    try std.testing.expectEqual(@as(u16, 2), vt_core.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 3), vt_core.screen().cursor_col);
}

test "encodeKey and encodeMouse methods are callable" {
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    const encode_key_fn: fn (*VtCore, Input.Key, Input.Modifier) []const u8 = VtCore.encodeKey;
    const encode_mouse_fn: fn (*VtCore, Input.MouseEvent) []const u8 = VtCore.encodeMouse;
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

    const mouse_event = Input.MouseEvent{
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

test {
    _ = @import("test/pipeline_regression.zig");
    _ = @import("test/scrollback_regression.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/semantic_mapping.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/system_flows.zig");
}
