//! Responsibility: hold screen cursor/cell/history state and apply semantics.
//! Ownership: screen state authority.
//! Reason: centralize deterministic screen mutations behind semantic events.

const std = @import("std");
const semantic_mod = @import("../event/semantic.zig");

/// Semantic event alias for screen application.
const SemanticEvent = semantic_mod.SemanticEvent;

/// Screen state container for cursor/cell/history behavior.
pub const ScreenState = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    wrap_pending: bool,
    cursor_visible: bool,
    auto_wrap: bool,
    row_origin: u16,
    cells: ?[]u21,
    history: ?[]u21,
    history_capacity: u16,
    history_count: u16,
    history_write_idx: u16,

    /// Initialize cursor-only screen state.
    pub fn init(rows: u16, cols: u16) ScreenState {
        return .{
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .auto_wrap = true,
            .row_origin = 0,
            .cells = null,
            .history = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
        };
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !ScreenState {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]u21 = if (size > 0) blk: {
            const buf = try allocator.alloc(u21, size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        return .{
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .auto_wrap = true,
            .row_origin = 0,
            .cells = cells,
            .history = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
        };
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !ScreenState {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]u21 = if (size > 0) blk: {
            const buf = try allocator.alloc(u21, size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const history: ?[]u21 = if (cells != null and history_capacity > 0) blk: {
            const hist_size = @as(usize, history_capacity) * @as(usize, cols);
            const buf = try allocator.alloc(u21, hist_size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        return .{
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .auto_wrap = true,
            .row_origin = 0,
            .cells = cells,
            .history = history,
            .history_capacity = if (cells != null) history_capacity else 0,
            .history_count = 0,
            .history_write_idx = 0,
        };
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *ScreenState, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
        if (self.history) |h| allocator.free(h);
        self.history = null;
    }

    /// Reset visible screen state to defaults.
    pub fn reset(self: *ScreenState) void {
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.wrap_pending = false;
        self.cursor_visible = true;
        self.auto_wrap = true;
        self.row_origin = 0;
        if (self.cells) |c| @memset(c, 0);
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const ScreenState, row: u16, col: u16) u21 {
        const c = self.cells orelse return 0;
        if (row >= self.rows or col >= self.cols) return 0;
        const start = self.rowStart(row);
        return c[start + @as(usize, col)];
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const ScreenState, history_idx: u16, col: u16) u21 {
        const h = self.history orelse return 0;
        if (history_idx >= self.history_count or col >= self.cols) return 0;
        const cap = @as(usize, self.history_capacity);
        const newest_slot = (@as(usize, self.history_write_idx) + cap - 1) % cap;
        const logical_slot = (newest_slot + cap - @as(usize, history_idx)) % cap;
        return h[logical_slot * @as(usize, self.cols) + @as(usize, col)];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const ScreenState) u16 {
        return self.history_count;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const ScreenState) u16 {
        return self.history_capacity;
    }

    /// Report whether selection endpoint should be invalidated.
    pub fn shouldInvalidateSelectionEndpoint(self: *const ScreenState, endpoint_row: i32) bool {
        if (self.history == null or self.history_count < self.history_capacity) {
            return false;
        }
        if (endpoint_row < -@as(i32, self.history_capacity)) {
            return true;
        }
        return false;
    }

    /// Apply one semantic event to screen state.
    pub fn apply(self: *ScreenState, event: SemanticEvent) void {
        switch (event) {
            .cursor_up => |n| {
                self.wrap_pending = false;
                self.cursor_row = self.cursor_row -| n;
            },
            .cursor_down => |n| {
                self.wrap_pending = false;
                self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1);
            },
            .cursor_forward => |n| {
                self.wrap_pending = false;
                self.cursor_col = @min(self.cursor_col +| n, self.cols -| 1);
            },
            .cursor_back => |n| {
                self.wrap_pending = false;
                self.cursor_col = self.cursor_col -| n;
            },
            .cursor_next_line => |n| {
                self.wrap_pending = false;
                self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1);
                self.cursor_col = 0;
            },
            .cursor_prev_line => |n| {
                self.wrap_pending = false;
                self.cursor_row = self.cursor_row -| n;
                self.cursor_col = 0;
            },
            .cursor_horizontal_absolute => |col| {
                self.wrap_pending = false;
                self.cursor_col = @min(col, self.cols -| 1);
            },
            .cursor_vertical_absolute => |row| {
                self.wrap_pending = false;
                self.cursor_row = @min(row, self.rows -| 1);
            },
            .cursor_position => |pos| {
                self.wrap_pending = false;
                self.cursor_row = @min(pos.row, self.rows -| 1);
                self.cursor_col = @min(pos.col, self.cols -| 1);
            },
            .write_text => |s| {
                for (s) |byte| {
                    self.writeCell(@intCast(byte));
                }
            },
            .write_codepoint => |cp| self.writeCell(cp),
            .line_feed => {
                self.wrap_pending = false;
                self.lineFeed();
            },
            .carriage_return => {
                self.wrap_pending = false;
                self.cursor_col = 0;
            },
            .backspace => {
                self.wrap_pending = false;
                self.cursor_col = self.cursor_col -| 1;
            },
            .horizontal_tab => {
                self.wrap_pending = false;
                self.horizontalTabForward(1);
            },
            .horizontal_tab_forward => |count| {
                self.wrap_pending = false;
                self.horizontalTabForward(count);
            },
            .horizontal_tab_back => |count| {
                self.wrap_pending = false;
                self.horizontalTabBack(count);
            },
            .cursor_visible => |visible| self.cursor_visible = visible,
            .auto_wrap => |enabled| {
                self.auto_wrap = enabled;
                if (!enabled) self.wrap_pending = false;
            },
            .reset_screen => self.reset(),
            .erase_display => |mode| {
                self.wrap_pending = false;
                self.eraseDisplay(mode);
            },
            .erase_line => |mode| {
                self.wrap_pending = false;
                self.eraseLine(mode);
            },
        }
    }

    fn eraseDisplay(self: *ScreenState, mode: u2) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => {
                self.clearRowRange(self.cursor_row, self.cursor_col, self.cols);
                var r = self.cursor_row + 1;
                while (r < self.rows) : (r += 1) {
                    const start = self.rowStart(r);
                    @memset(c[start .. start + @as(usize, self.cols)], 0);
                }
            },
            1 => {
                var r: u16 = 0;
                while (r < self.cursor_row) : (r += 1) {
                    const start = self.rowStart(r);
                    @memset(c[start .. start + @as(usize, self.cols)], 0);
                }
                self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1);
            },
            2 => @memset(c, 0),
            3 => {},
        }
    }

    fn eraseLine(self: *ScreenState, mode: u2) void {
        _ = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => self.clearRowRange(self.cursor_row, self.cursor_col, self.cols),
            1 => self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1),
            2 => self.clearRowRange(self.cursor_row, 0, self.cols),
            3 => {},
        }
    }

    fn writeCell(self: *ScreenState, cp: u21) void {
        if (self.cols == 0 or self.rows == 0) return;
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (self.cursor_col == self.cols - 1) {
                self.lineFeed();
                self.cursor_col = 0;
            }
        }
        if (self.cells) |c| {
            const start = self.rowStart(self.cursor_row);
            c[start + @as(usize, self.cursor_col)] = cp;
        }
        if (self.cursor_col < self.cols - 1) {
            self.cursor_col += 1;
        } else if (self.auto_wrap) {
            self.wrap_pending = true;
        }
    }

    fn horizontalTabForward(self: *ScreenState, count: u16) void {
        if (self.cols == 0) return;
        const stop = (@as(usize, self.cursor_col / 8) + @as(usize, count)) * 8;
        self.cursor_col = @intCast(@min(stop, @as(usize, self.cols - 1)));
    }

    fn horizontalTabBack(self: *ScreenState, count: u16) void {
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor_col == 0) break;
            const prev = self.cursor_col - 1;
            self.cursor_col = (prev / 8) * 8;
        }
    }

    fn lineFeed(self: *ScreenState) void {
        if (self.rows == 0) return;
        if (self.cursor_row < self.rows - 1) {
            self.cursor_row += 1;
            return;
        }
        self.scrollUp();
    }

    fn scrollUp(self: *ScreenState) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        const row_len = @as(usize, self.cols);
        const top_start = self.rowStart(0);
        const top_end = top_start + row_len;
        if (self.history) |h| {
            const hist_row_start = @as(usize, self.history_write_idx) * row_len;
            @memcpy(h[hist_row_start .. hist_row_start + row_len], c[top_start..top_end]);
            self.history_write_idx = (self.history_write_idx + 1) % self.history_capacity;
            if (self.history_count < self.history_capacity) {
                self.history_count += 1;
            }
        }
        self.row_origin = @intCast((@as(usize, self.row_origin) + 1) % @as(usize, self.rows));
        const bottom_start = self.rowStart(self.rows - 1);
        @memset(c[bottom_start .. bottom_start + row_len], 0);
    }

    fn rowStart(self: *const ScreenState, logical_row: u16) usize {
        const physical_row = (@as(usize, self.row_origin) + @as(usize, logical_row)) % @as(usize, self.rows);
        return physical_row * @as(usize, self.cols);
    }

    fn clearRowRange(self: *ScreenState, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const start = self.rowStart(row);
        @memset(c[start + @as(usize, start_col) .. start + @as(usize, end_col_exclusive)], 0);
    }
};

