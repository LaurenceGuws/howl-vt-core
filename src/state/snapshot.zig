//! Responsibility: capture and represent vt_core observable state snapshots.
//! Ownership: snapshot api authority.
//! Reason: provide host-neutral read-only snapshots for replay and diagnostic access.
//!
//! VtCoreSnapshot is a deterministic, read-only capture of vt_core observable state
//! at a point in time, aligned to SNAPSHOT_REPLAY api requirements.
//! Snapshots are host-neutral data structures without persistence format or
//! cross-version guarantees.

const std = @import("std");
const selection_mod = @import("selection.zig");
const screen_mod = @import("../screen/state.zig");
const vt_mod = @import("../vt_core.zig");

/// Deterministic snapshot of vt_core observable state (SNAPSHOT_REPLAY api).
///
/// Captures visible screen cells, cursor position, modes, history buffer, and
/// selection state. Does NOT capture parser state, queued events, or encode buffers.
///
/// Snapshots are deterministic: identical observable vt_core state produces
/// identical snapshots. Split-feed input chunking is transparent (same bytes fed
/// as chunks vs atomically produce identical final snapshot).
///
/// Snapshots own allocated buffers (cells, history); caller must call deinit()
/// to release them.
pub const VtCoreSnapshot = struct {
    /// Allocator used for cell and history buffer allocation.
    allocator: std.mem.Allocator,

    /// Screen dimensions: rows.
    rows: u16,

    /// Screen dimensions: columns.
    cols: u16,

    /// Cursor row in viewport coordinates (0 to rows-1).
    cursor_row: u16,

    /// Cursor column in viewport coordinates (0 to cols-1).
    cursor_col: u16,

    /// Cursor visibility mode state.
    cursor_visible: bool,

    /// Auto-wrap mode state.
    auto_wrap: bool,

    /// Owned copy of visible screen cell buffer (null if no cells configured).
    cells: ?[]u21,

    /// Owned copy of history buffer (null if no history configured).
    history: ?[]u21,

    /// Current number of rows in history buffer.
    history_count: u16,

    /// Configured history buffer capacity.
    history_capacity: u16,

    /// History write index for circular buffer wraparound calculation.
    history_write_idx: u16,

    /// Active selection state snapshot (null if inactive).
    selection: ?selection_mod.TerminalSelection,

    /// Capture snapshot from vt_core observable state; allocates owned buffers (SNAPSHOT_REPLAY api).
    ///
    /// This method extracts the observable state from a ScreenState and optional
    /// selection state, allocating owned copies of cell and history buffers.
    ///
    /// Determinism: identical screen and selection state produce identical snapshots.
    /// The snapshot captures only observable state; parser state, queued events,
    /// and encode buffers are not included.
    ///
    /// Memory: allocated cells and history buffers are owned by the returned snapshot.
    /// Caller must call snapshot.deinit() to release them. If allocation fails,
    /// the error is returned and no partial allocation is left outstanding.
    pub fn captureFromScreen(allocator: std.mem.Allocator, screen: *const screen_mod.ScreenState, selection: ?selection_mod.TerminalSelection) !VtCoreSnapshot {
        var snapshot = VtCoreSnapshot{
            .allocator = allocator,
            .rows = screen.rows,
            .cols = screen.cols,
            .cursor_row = screen.cursor_row,
            .cursor_col = screen.cursor_col,
            .cursor_visible = screen.cursor_visible,
            .auto_wrap = screen.auto_wrap,
            .cells = null,
            .history = null,
            .history_count = screen.history_count,
            .history_capacity = screen.history_capacity,
            .history_write_idx = screen.history_write_idx,
            .selection = selection,
        };
        errdefer {
            if (snapshot.cells) |c| allocator.free(c);
            if (snapshot.history) |h| allocator.free(h);
        }

        // Copy visible screen cells if present.
        if (screen.cells != null) {
            const size = @as(usize, screen.rows) * @as(usize, screen.cols);
            const owned_cells = try allocator.alloc(u21, size);
            var row: u16 = 0;
            while (row < screen.rows) : (row += 1) {
                var col: u16 = 0;
                while (col < screen.cols) : (col += 1) {
                    owned_cells[@as(usize, row) * @as(usize, screen.cols) + @as(usize, col)] = screen.cellAt(row, col);
                }
            }
            snapshot.cells = owned_cells;
        }

        // Copy history buffer if present.
        if (screen.history) |history| {
            const size = @as(usize, screen.history_capacity) * @as(usize, screen.cols);
            const owned_history = try allocator.alloc(u21, size);
            @memcpy(owned_history, history);
            snapshot.history = owned_history;
        }

        return snapshot;
    }

    /// Release owned cell and history buffers.
    ///
    /// Frees allocated buffers and clears their references. Safe to call multiple
    /// times; subsequent calls are no-ops. Must be called exactly once when snapshot
    /// is no longer needed.
    pub fn deinit(self: *VtCoreSnapshot) void {
        if (self.cells) |c| self.allocator.free(c);
        self.cells = null;
        if (self.history) |h| self.allocator.free(h);
        self.history = null;
    }

    /// Return visible cell codepoint by row and column (read-only).
    ///
    /// Returns the codepoint value at the given viewport coordinates.
    /// Returns 0 (null/empty) if row >= rows, col >= cols, or cells not configured.
    /// Reads are deterministic and never mutate snapshot state.
    pub fn cellAt(self: *const VtCoreSnapshot, row: u16, col: u16) u21 {
        const c = self.cells orelse return 0;
        if (row >= self.rows or col >= self.cols) return 0;
        return c[@as(usize, row) * self.cols + col];
    }

    /// Return history cell codepoint by recency index and column (read-only).
    ///
    /// Reads history in recency order: history_idx=0 is most recent row (-1 in
    /// History Selection coordinate model), history_idx=1 is next older, etc.
    ///
    /// Respects circular buffer wraparound via history_write_idx, matching
    /// ScreenState semantics exactly. Returns 0 if history_idx >= history_count,
    /// col >= cols, or history not configured.
    ///
    /// Determinism: identical history buffer and indices produce identical results.
    /// Reads are const and never mutate snapshot state.
    pub fn historyRowAt(self: *const VtCoreSnapshot, history_idx: u16, col: u16) u21 {
        const h = self.history orelse return 0;
        if (history_idx >= self.history_count or col >= self.cols) return 0;
        const cap = @as(usize, self.history_capacity);
        const newest_slot = (@as(usize, self.history_write_idx) + cap - 1) % cap;
        const logical_slot = (newest_slot + cap - @as(usize, history_idx)) % cap;
        return h[logical_slot * @as(usize, self.cols) + @as(usize, col)];
    }
};

test "snapshot: capture from simple text" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("HELLO");
    vt_core.apply();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 5), snap.rows);
    try std.testing.expectEqual(@as(u16, 10), snap.cols);
    try std.testing.expectEqual(@as(u16, 0), snap.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), snap.cursor_col);
    try std.testing.expectEqual(true, snap.cursor_visible);
    try std.testing.expectEqual(true, snap.auto_wrap);
    try std.testing.expectEqual(@as(u21, 'H'), snap.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), snap.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'L'), snap.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'L'), snap.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'O'), snap.cellAt(0, 4));
}

test "snapshot: determinism across identical state" {
    const gpa = std.testing.allocator;

    var vt_core1 = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core1.deinit();
    vt_core1.feedSlice("TEST");
    vt_core1.apply();
    var snap1 = try vt_core1.snapshot();
    defer snap1.deinit();

    var vt_core2 = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core2.deinit();
    vt_core2.feedSlice("TEST");
    vt_core2.apply();
    var snap2 = try vt_core2.snapshot();
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
    try std.testing.expectEqual(snap1.cursor_visible, snap2.cursor_visible);
    try std.testing.expectEqual(snap1.auto_wrap, snap2.auto_wrap);

    if (snap1.cells != null and snap2.cells != null) {
        const size = @as(usize, snap1.rows) * @as(usize, snap1.cols);
        try std.testing.expectEqualSlices(u21, snap1.cells.?[0..size], snap2.cells.?[0..size]);
    }
}

test "snapshot: split-feed replay equivalence" {
    const gpa = std.testing.allocator;

    var vt_core_atomic = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core_atomic.deinit();
    vt_core_atomic.feedSlice("ABCDEFGHIJ");
    vt_core_atomic.apply();
    var snap_atomic = try vt_core_atomic.snapshot();
    defer snap_atomic.deinit();

    var vt_core_chunked = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core_chunked.deinit();
    vt_core_chunked.feedByte('A');
    vt_core_chunked.feedByte('B');
    vt_core_chunked.feedSlice("CD");
    vt_core_chunked.feedSlice("EFGHIJ");
    vt_core_chunked.apply();
    var snap_chunked = try vt_core_chunked.snapshot();
    defer snap_chunked.deinit();

    try std.testing.expectEqual(snap_atomic.cursor_col, snap_chunked.cursor_col);
    try std.testing.expectEqual(snap_atomic.cursor_row, snap_chunked.cursor_row);

    if (snap_atomic.cells != null and snap_chunked.cells != null) {
        const size = @as(usize, snap_atomic.rows) * @as(usize, snap_atomic.cols);
        try std.testing.expectEqualSlices(u21, snap_atomic.cells.?[0..size], snap_chunked.cells.?[0..size]);
    }
}

test "snapshot: history capture when history is enabled" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCellsAndHistory(gpa, 3, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("AAA\nBBB\nCCC\nDDD");
    vt_core.apply();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 3), snap.rows);
    try std.testing.expectEqual(@as(u16, 5), snap.cols);
    try std.testing.expectEqual(@as(u16, 10), snap.history_capacity);
    try std.testing.expectEqual(snap.history_count, vt_core.historyCount());

    if (snap.history != null) {
        try std.testing.expect(snap.history.?.len > 0);
    }
}

test "snapshot: historyRowAt matches vt_core after wraparound" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCellsAndHistory(gpa, 2, 3, 2);
    defer vt_core.deinit();

    // Force history ring-buffer wraparound (capacity 2, scroll more than 2 rows).
    vt_core.feedSlice("111\n222\n333\n444\n555");
    vt_core.apply();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(vt_core.historyCount(), snap.history_count);
    try std.testing.expectEqual(vt_core.historyCapacity(), snap.history_capacity);

    var idx: u16 = 0;
    while (idx < vt_core.historyCount()) : (idx += 1) {
        var col: u16 = 0;
        while (col < vt_core.screen().cols) : (col += 1) {
            try std.testing.expectEqual(vt_core.historyRowAt(idx, col), snap.historyRowAt(idx, col));
        }
    }
}

test "snapshot: selection state is included" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("HELLO");
    vt_core.apply();

    vt_core.selectionStart(0, 0);
    vt_core.selectionUpdate(0, 4);
    vt_core.selectionFinish();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(true, snap.selection != null);
    if (snap.selection) |sel| {
        try std.testing.expectEqual(@as(i32, 0), sel.start.row);
        try std.testing.expectEqual(@as(u16, 0), sel.start.col);
        try std.testing.expectEqual(@as(i32, 0), sel.end.row);
        try std.testing.expectEqual(@as(u16, 4), sel.end.col);
        try std.testing.expectEqual(true, sel.active);
    }
}

test "snapshot: parity with direct screen state" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("TEST");
    vt_core.apply();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    const screen = vt_core.screen();
    try std.testing.expectEqual(screen.rows, snap.rows);
    try std.testing.expectEqual(screen.cols, snap.cols);
    try std.testing.expectEqual(screen.cursor_row, snap.cursor_row);
    try std.testing.expectEqual(screen.cursor_col, snap.cursor_col);
    try std.testing.expectEqual(screen.cursor_visible, snap.cursor_visible);
    try std.testing.expectEqual(screen.auto_wrap, snap.auto_wrap);
}

