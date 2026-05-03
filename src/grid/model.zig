//! Responsibility: hold grid cursor/cell/history state and apply semantics.
//! Ownership: terminal grid model authority.
//! Reason: centralize deterministic grid mutations behind semantic operations.

const std = @import("std");
const interpret_owner = @import("../interpret.zig");

/// Semantic event alias for grid application.
const SemanticEvent = interpret_owner.Interpret.SemanticEvent;

const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(u21) = .empty,
    cursor_offset: ?usize = null,
};

const RewrappedRow = struct {
    start: usize,
    len: usize,
    wrapped: bool,
};

/// Terminal grid model for cursor/cell/history behavior.
pub const GridModel = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    wrap_pending: bool,
    cursor_visible: bool,
    auto_wrap: bool,
    row_origin: u16,
    cells: ?[]u21,
    row_wraps: ?[]bool,
    history: ?[]u21,
    history_wraps: ?[]bool,
    history_capacity: u16,
    history_count: u16,
    history_write_idx: u16,

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) GridModel {
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
            .row_wraps = null,
            .history = null,
            .history_wraps = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
        };
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !GridModel {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]u21 = if (size > 0) blk: {
            const buf = try allocator.alloc(u21, size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
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
            .row_wraps = row_wraps,
            .history = null,
            .history_wraps = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
        };
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !GridModel {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]u21 = if (size > 0) blk: {
            const buf = try allocator.alloc(u21, size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            break :blk buf;
        } else null;
        errdefer if (row_wraps) |buf| allocator.free(buf);
        const history: ?[]u21 = if (cells != null and history_capacity > 0 and cols > 0) blk: {
            const hist_size = @as(usize, history_capacity) * @as(usize, cols);
            const buf = try allocator.alloc(u21, hist_size);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        errdefer if (history) |buf| allocator.free(buf);
        const history_wraps: ?[]bool = if (cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(bool, history_capacity);
            @memset(buf, false);
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
            .row_wraps = row_wraps,
            .history = history,
            .history_wraps = history_wraps,
            .history_capacity = if (cells != null) history_capacity else 0,
            .history_count = 0,
            .history_write_idx = 0,
        };
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *GridModel, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
        if (self.row_wraps) |buf| allocator.free(buf);
        self.row_wraps = null;
        if (self.history) |h| allocator.free(h);
        self.history = null;
        if (self.history_wraps) |buf| allocator.free(buf);
        self.history_wraps = null;
    }

    /// Resize visible grid while preserving retained history rows.
    pub fn resize(self: *GridModel, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        if (cols != self.cols) {
            try self.resizeWithReflow(allocator, rows, cols);
            return;
        }

        const old_cells = self.cells;
        const old_row_wraps = self.row_wraps;
        const old_history = self.history;
        const old_history_wraps = self.history_wraps;
        const old_rows = self.rows;
        const old_history_count = self.history_count;
        const old_history_capacity = self.history_capacity;

        const cell_count = @as(usize, rows) * @as(usize, cols);
        var new_cells: ?[]u21 = null;
        if (cell_count > 0) {
            const buf = try allocator.alloc(u21, cell_count);
            @memset(buf, 0);
            new_cells = buf;
        }
        errdefer if (new_cells) |buf| allocator.free(buf);

        var new_row_wraps: ?[]bool = null;
        if (rows > 0) {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            new_row_wraps = buf;
        }
        errdefer if (new_row_wraps) |buf| allocator.free(buf);

        var new_history: ?[]u21 = null;
        if (old_history != null and old_history_capacity > 0 and cols > 0) {
            const hist_size = @as(usize, old_history_capacity) * @as(usize, cols);
            const buf = try allocator.alloc(u21, hist_size);
            @memset(buf, 0);
            new_history = buf;
        }
        errdefer if (new_history) |buf| allocator.free(buf);

        var new_history_wraps: ?[]bool = null;
        if (old_history_wraps != null and old_history_capacity > 0) {
            const buf = try allocator.alloc(bool, old_history_capacity);
            @memset(buf, false);
            new_history_wraps = buf;
        }
        errdefer if (new_history_wraps) |buf| allocator.free(buf);

        var next_history_count: u16 = 0;
        var next_history_write_idx: u16 = 0;
        if (new_history) |dst| {
            const dst_wraps = new_history_wraps.?;
            const grow_pull: u16 = if (rows > old_rows) @min(rows - old_rows, old_history_count) else 0;
            var recency_plus_one = old_history_count;
            while (recency_plus_one > grow_pull) : (recency_plus_one -= 1) {
                const recency = recency_plus_one - 1;
                const dst_start = @as(usize, next_history_write_idx) * @as(usize, cols);
                var col: u16 = 0;
                while (col < cols) : (col += 1) {
                    dst[dst_start + @as(usize, col)] = self.historyRowAt(recency, col);
                }
                dst_wraps[next_history_write_idx] = self.historyRowWrapped(recency);
                nextHistoryWrite(old_history_capacity, &next_history_count, &next_history_write_idx);
            }

            if (rows < old_rows) {
                const retired_rows = old_rows - rows;
                var retired_row: u16 = 0;
                while (retired_row < retired_rows) : (retired_row += 1) {
                    const dst_start = @as(usize, next_history_write_idx) * @as(usize, cols);
                    var col: u16 = 0;
                    while (col < cols) : (col += 1) {
                        dst[dst_start + @as(usize, col)] = self.cellAt(retired_row, col);
                    }
                    dst_wraps[next_history_write_idx] = self.rowWrapped(retired_row);
                    nextHistoryWrite(old_history_capacity, &next_history_count, &next_history_write_idx);
                }
            }
        }

        if (new_cells) |dst| {
            const dst_wraps = new_row_wraps.?;
            if (rows < old_rows) {
                const src_start_row = old_rows - rows;
                var row: u16 = 0;
                while (row < rows) : (row += 1) {
                    const dst_start = @as(usize, row) * @as(usize, cols);
                    var col: u16 = 0;
                    while (col < cols) : (col += 1) {
                        dst[dst_start + @as(usize, col)] = self.cellAt(src_start_row + row, col);
                    }
                    dst_wraps[row] = self.rowWrapped(src_start_row + row);
                }
            } else if (rows > old_rows) {
                const pulled_history = @min(rows - old_rows, old_history_count);
                const top_blank_rows = rows - old_rows - pulled_history;

                var row: u16 = 0;
                while (row < pulled_history) : (row += 1) {
                    const dst_row = top_blank_rows + row;
                    const dst_start = @as(usize, dst_row) * @as(usize, cols);
                    const recency = pulled_history - 1 - row;
                    var col: u16 = 0;
                    while (col < cols) : (col += 1) {
                        dst[dst_start + @as(usize, col)] = self.historyRowAt(recency, col);
                    }
                    dst_wraps[dst_row] = self.historyRowWrapped(recency);
                }

                row = 0;
                while (row < old_rows) : (row += 1) {
                    const dst_row = top_blank_rows + pulled_history + row;
                    const dst_start = @as(usize, dst_row) * @as(usize, cols);
                    var col: u16 = 0;
                    while (col < cols) : (col += 1) {
                        dst[dst_start + @as(usize, col)] = self.cellAt(row, col);
                    }
                    dst_wraps[dst_row] = self.rowWrapped(row);
                }
            } else {
                var row: u16 = 0;
                while (row < rows) : (row += 1) {
                    const dst_start = @as(usize, row) * @as(usize, cols);
                    var col: u16 = 0;
                    while (col < cols) : (col += 1) {
                        dst[dst_start + @as(usize, col)] = self.cellAt(row, col);
                    }
                    dst_wraps[row] = self.rowWrapped(row);
                }
            }
        }

        self.rows = rows;
        self.cols = cols;
        self.cells = new_cells;
        self.row_wraps = new_row_wraps;
        self.history = new_history;
        self.history_wraps = new_history_wraps;
        self.history_capacity = if (new_history != null) old_history_capacity else 0;
        self.history_count = next_history_count;
        self.history_write_idx = next_history_write_idx;
        self.row_origin = 0;
        self.wrap_pending = false;
        if (rows == 0 or cols == 0) {
            self.cursor_row = 0;
            self.cursor_col = 0;
        } else {
            if (rows < old_rows) {
                const retired_rows = old_rows - rows;
                self.cursor_row = self.cursor_row -| retired_rows;
            } else if (rows > old_rows) {
                const pulled_history = @min(rows - old_rows, old_history_count);
                const top_blank_rows = rows - old_rows - pulled_history;
                self.cursor_row = @min(self.cursor_row + top_blank_rows + pulled_history, rows - 1);
            } else {
                self.cursor_row = @min(self.cursor_row, rows - 1);
            }
            self.cursor_col = @min(self.cursor_col, cols - 1);
        }

        if (old_cells) |buf| allocator.free(buf);
        if (old_row_wraps) |buf| allocator.free(buf);
        if (old_history) |buf| allocator.free(buf);
        if (old_history_wraps) |buf| allocator.free(buf);
    }

    fn resizeWithReflow(self: *GridModel, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        const old_cells = self.cells;
        const old_row_wraps = self.row_wraps;
        const old_history = self.history;
        const old_history_wraps = self.history_wraps;
        const old_rows = self.rows;
        const old_cols = self.cols;
        const old_history_capacity = self.history_capacity;

        var logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty;
        defer {
            for (logical_lines.items) |*line| line.cells.deinit(allocator);
            logical_lines.deinit(allocator);
        }

        var current_line = LogicalLine{};
        defer current_line.cells.deinit(allocator);

        var cursor_line_index: usize = 0;
        var cursor_offset: usize = 0;
        var cursor_found = false;

        var history_idx: usize = 0;
        while (history_idx < self.history_count) : (history_idx += 1) {
            const recency: u16 = @intCast(self.history_count - 1 - @as(u16, @intCast(history_idx)));
            try self.appendSourceRowToLogicalLines(
                allocator,
                &logical_lines,
                &current_line,
                recency,
                true,
                old_cols,
                &cursor_found,
                &cursor_line_index,
                &cursor_offset,
            );
        }

        var row: u16 = 0;
        while (row < old_rows) : (row += 1) {
            try self.appendSourceRowToLogicalLines(
                allocator,
                &logical_lines,
                &current_line,
                row,
                false,
                old_cols,
                &cursor_found,
                &cursor_line_index,
                &cursor_offset,
            );
        }

        if (current_line.cells.items.len > 0 or current_line.cursor_offset != null or logical_lines.items.len == 0) {
            if (current_line.cursor_offset) |offset| {
                cursor_found = true;
                cursor_line_index = logical_lines.items.len;
                cursor_offset = offset;
            }
            try logical_lines.append(allocator, current_line);
            current_line = .{};
        }

        var flat_rows: std.ArrayListUnmanaged(u21) = .empty;
        defer flat_rows.deinit(allocator);
        var rewrapped: std.ArrayListUnmanaged(RewrappedRow) = .empty;
        defer rewrapped.deinit(allocator);

        var global_cursor_row: usize = 0;
        var global_cursor_col: usize = 0;
        var next_wrap_pending = false;
        var row_cursor_base: usize = 0;

        for (logical_lines.items, 0..) |line, line_idx| {
            const has_cursor = cursor_found and cursor_line_index == line_idx;
            const line_cursor_offset = if (has_cursor) cursor_offset else 0;
            const effective_len = if (has_cursor) @max(line.cells.items.len, line_cursor_offset) else line.cells.items.len;
            const row_count: usize = if (cols == 0) 0 else @max(1, std.math.divCeil(usize, effective_len, cols) catch unreachable);

            if (has_cursor) {
                if (cols == 0) {
                    global_cursor_row = 0;
                    global_cursor_col = 0;
                    next_wrap_pending = false;
                } else if (line_cursor_offset > 0 and line_cursor_offset % cols == 0) {
                    global_cursor_row = row_cursor_base + (line_cursor_offset / cols) - 1;
                    global_cursor_col = cols - 1;
                    next_wrap_pending = true;
                } else {
                    global_cursor_row = row_cursor_base + (line_cursor_offset / cols);
                    global_cursor_col = line_cursor_offset % cols;
                    next_wrap_pending = false;
                }
            }

            if (cols == 0) continue;

            if (row_count == 0) unreachable;
            var row_idx: usize = 0;
            while (row_idx < row_count) : (row_idx += 1) {
                const start = row_idx * @as(usize, cols);
                const end = @min(effective_len, start + @as(usize, cols));
                try rewrapped.append(allocator, .{
                    .start = flat_rows.items.len,
                    .len = end - start,
                    .wrapped = row_idx + 1 < row_count,
                });

                var col_idx: usize = 0;
                while (col_idx < @as(usize, cols)) : (col_idx += 1) {
                    const src_idx = start + col_idx;
                    if (src_idx < line.cells.items.len) {
                        try flat_rows.append(allocator, line.cells.items[src_idx]);
                    } else {
                        try flat_rows.append(allocator, 0);
                    }
                }
            }

            row_cursor_base += row_count;
        }

        const total_rows = rewrapped.items.len;
        const kept_total = if (rows == 0) @min(total_rows, @as(usize, old_history_capacity)) else @min(total_rows, @as(usize, rows) + @as(usize, old_history_capacity));
        const drop_rows = total_rows - kept_total;
        const visible_rows_kept: usize = @min(@as(usize, rows), kept_total);
        const history_rows_kept: usize = kept_total - visible_rows_kept;
        const visible_start = drop_rows + history_rows_kept;
        const top_blank_rows: usize = @as(usize, rows) - visible_rows_kept;

        const cell_count = @as(usize, rows) * @as(usize, cols);
        var new_cells: ?[]u21 = null;
        if (cell_count > 0) {
            const buf = try allocator.alloc(u21, cell_count);
            @memset(buf, 0);
            new_cells = buf;
        }
        errdefer if (new_cells) |buf| allocator.free(buf);

        var new_row_wraps: ?[]bool = null;
        if (rows > 0) {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            new_row_wraps = buf;
        }
        errdefer if (new_row_wraps) |buf| allocator.free(buf);

        var new_history: ?[]u21 = null;
        if (old_history_capacity > 0 and cols > 0) {
            const hist_size = @as(usize, old_history_capacity) * @as(usize, cols);
            const buf = try allocator.alloc(u21, hist_size);
            @memset(buf, 0);
            new_history = buf;
        }
        errdefer if (new_history) |buf| allocator.free(buf);

        var new_history_wraps: ?[]bool = null;
        if (old_history_capacity > 0) {
            const buf = try allocator.alloc(bool, old_history_capacity);
            @memset(buf, false);
            new_history_wraps = buf;
        }
        errdefer if (new_history_wraps) |buf| allocator.free(buf);

        if (new_history) |dst| {
            const dst_wraps = new_history_wraps.?;
            var src_row: usize = drop_rows;
            var dst_row: usize = 0;
            while (dst_row < history_rows_kept) : ({
                dst_row += 1;
                src_row += 1;
            }) {
                const src = rewrapped.items[src_row];
                const dst_start = dst_row * @as(usize, cols);
                @memcpy(dst[dst_start .. dst_start + @as(usize, cols)], flat_rows.items[src.start .. src.start + @as(usize, cols)]);
                dst_wraps[dst_row] = src.wrapped;
            }
        }

        if (new_cells) |dst| {
            const dst_wraps = new_row_wraps.?;
            var src_row: usize = visible_start;
            var view_row: usize = 0;
            while (view_row < visible_rows_kept) : ({
                view_row += 1;
                src_row += 1;
            }) {
                const src = rewrapped.items[src_row];
                const dst_row = top_blank_rows + view_row;
                const dst_start = dst_row * @as(usize, cols);
                @memcpy(dst[dst_start .. dst_start + @as(usize, cols)], flat_rows.items[src.start .. src.start + @as(usize, cols)]);
                dst_wraps[dst_row] = src.wrapped;
            }
        }

        self.rows = rows;
        self.cols = cols;
        self.cells = new_cells;
        self.row_wraps = new_row_wraps;
        self.history = new_history;
        self.history_wraps = new_history_wraps;
        self.history_capacity = if (new_history != null) old_history_capacity else 0;
        self.history_count = @intCast(history_rows_kept);
        self.history_write_idx = if (old_history_capacity == 0) 0 else @intCast(history_rows_kept % @as(usize, old_history_capacity));
        self.row_origin = 0;

        if (rows == 0 or cols == 0 or total_rows == 0) {
            self.cursor_row = 0;
            self.cursor_col = 0;
            self.wrap_pending = false;
        } else {
            const clamped_cursor_row = std.math.clamp(global_cursor_row, visible_start, visible_start + visible_rows_kept - 1);
            self.cursor_row = @intCast(top_blank_rows + (clamped_cursor_row - visible_start));
            self.cursor_col = @intCast(@min(global_cursor_col, @as(usize, cols - 1)));
            self.wrap_pending = next_wrap_pending and self.cursor_row < rows and self.cursor_col == cols - 1;
        }

        if (old_cells) |buf| allocator.free(buf);
        if (old_row_wraps) |buf| allocator.free(buf);
        if (old_history) |buf| allocator.free(buf);
        if (old_history_wraps) |buf| allocator.free(buf);
    }

    fn appendSourceRowToLogicalLines(
        self: *const GridModel,
        allocator: std.mem.Allocator,
        logical_lines: *std.ArrayListUnmanaged(LogicalLine),
        current_line: *LogicalLine,
        row_index: u16,
        is_history: bool,
        old_cols: u16,
        cursor_found: *bool,
        cursor_line_index: *usize,
        cursor_offset: *usize,
    ) !void {
        const wrapped = if (is_history) self.historyRowWrapped(row_index) else self.rowWrapped(row_index);
        const is_cursor_row = !is_history and row_index == self.cursor_row;
        const content_len = self.sourceRowContentLen(row_index, is_history, old_cols, is_cursor_row);

        if (is_cursor_row) {
            const row_cursor_offset = self.cursorOffsetInRow(old_cols);
            current_line.cursor_offset = current_line.cells.items.len + row_cursor_offset;
        }

        var col: u16 = 0;
        while (col < content_len) : (col += 1) {
            try current_line.cells.append(allocator, if (is_history) self.historyRowAt(row_index, col) else self.cellAt(row_index, col));
        }

        if (!wrapped) {
            if (current_line.cursor_offset) |offset| {
                cursor_found.* = true;
                cursor_line_index.* = logical_lines.items.len;
                cursor_offset.* = offset;
            }
            try logical_lines.append(allocator, current_line.*);
            current_line.* = .{};
        }
    }

    fn sourceRowContentLen(self: *const GridModel, row_index: u16, is_history: bool, cols: u16, include_cursor: bool) u16 {
        var last_non_zero: u16 = 0;
        var has_content = false;
        var col: u16 = 0;
        while (col < cols) : (col += 1) {
            const value = if (is_history) self.historyRowAt(row_index, col) else self.cellAt(row_index, col);
            if (value != 0) {
                has_content = true;
                last_non_zero = col + 1;
            }
        }

        var len: u16 = if (has_content) last_non_zero else 0;
        if (include_cursor) {
            len = @max(len, @as(u16, @intCast(self.cursorOffsetInRow(cols))));
        }
        if ((if (is_history) self.historyRowWrapped(row_index) else self.rowWrapped(row_index)) and cols > 0) {
            len = @max(len, cols);
        }
        return len;
    }

    fn cursorOffsetInRow(self: *const GridModel, cols: u16) usize {
        if (cols == 0) return 0;
        if (self.wrap_pending and self.cursor_col == cols - 1) {
            return cols;
        }
        return self.cursor_col;
    }

    fn nextHistoryWrite(capacity: u16, count: *u16, write_idx: *u16) void {
        if (capacity == 0) return;
        write_idx.* = (write_idx.* + 1) % capacity;
        if (count.* < capacity) count.* += 1;
    }

    /// Reset visible grid state to defaults.
    pub fn reset(self: *GridModel) void {
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.wrap_pending = false;
        self.cursor_visible = true;
        self.auto_wrap = true;
        self.row_origin = 0;
        if (self.cells) |c| @memset(c, 0);
        if (self.row_wraps) |buf| @memset(buf, false);
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const GridModel, row: u16, col: u16) u21 {
        const c = self.cells orelse return 0;
        if (row >= self.rows or col >= self.cols) return 0;
        const start = self.rowStart(row);
        return c[start + @as(usize, col)];
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const GridModel, history_idx: u16, col: u16) u21 {
        const h = self.history orelse return 0;
        if (history_idx >= self.history_count or col >= self.cols) return 0;
        const slot = self.historySlotForRecency(history_idx) orelse return 0;
        return h[slot * @as(usize, self.cols) + @as(usize, col)];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const GridModel) u16 {
        return self.history_count;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const GridModel) u16 {
        return self.history_capacity;
    }

    /// Report whether selection endpoint should be invalidated.
    pub fn shouldInvalidateSelectionEndpoint(self: *const GridModel, endpoint_row: i32) bool {
        if (self.history == null or self.history_count < self.history_capacity) {
            return false;
        }
        if (endpoint_row < -@as(i32, self.history_capacity)) {
            return true;
        }
        return false;
    }

    /// Apply one semantic event to grid state.
    pub fn apply(self: *GridModel, event: SemanticEvent) void {
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
                self.setRowWrapped(self.cursor_row, false);
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

    fn eraseDisplay(self: *GridModel, mode: u2) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => {
                self.clearRowRange(self.cursor_row, self.cursor_col, self.cols);
                var r = self.cursor_row + 1;
                while (r < self.rows) : (r += 1) {
                    const start = self.rowStart(r);
                    @memset(c[start .. start + @as(usize, self.cols)], 0);
                    self.setRowWrapped(r, false);
                }
            },
            1 => {
                var r: u16 = 0;
                while (r < self.cursor_row) : (r += 1) {
                    const start = self.rowStart(r);
                    @memset(c[start .. start + @as(usize, self.cols)], 0);
                    self.setRowWrapped(r, false);
                }
                self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1);
            },
            2 => {
                @memset(c, 0);
                if (self.row_wraps) |buf| @memset(buf, false);
            },
            3 => {},
        }
    }

    fn eraseLine(self: *GridModel, mode: u2) void {
        _ = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => self.clearRowRange(self.cursor_row, self.cursor_col, self.cols),
            1 => self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1),
            2 => {
                self.clearRowRange(self.cursor_row, 0, self.cols);
                self.setRowWrapped(self.cursor_row, false);
            },
            3 => {},
        }
    }

    fn writeCell(self: *GridModel, cp: u21) void {
        if (self.cols == 0 or self.rows == 0) return;
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (self.cursor_col == self.cols - 1) {
                self.setRowWrapped(self.cursor_row, true);
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

    fn horizontalTabForward(self: *GridModel, count: u16) void {
        if (self.cols == 0) return;
        const stop = (@as(usize, self.cursor_col / 8) + @as(usize, count)) * 8;
        self.cursor_col = @intCast(@min(stop, @as(usize, self.cols - 1)));
    }

    fn horizontalTabBack(self: *GridModel, count: u16) void {
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor_col == 0) break;
            const prev = self.cursor_col - 1;
            self.cursor_col = (prev / 8) * 8;
        }
    }

    fn lineFeed(self: *GridModel) void {
        if (self.rows == 0) return;
        if (self.cursor_row < self.rows - 1) {
            self.cursor_row += 1;
            return;
        }
        self.scrollUp();
    }

    fn scrollUp(self: *GridModel) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        const row_len = @as(usize, self.cols);
        const top_start = self.rowStart(0);
        const top_end = top_start + row_len;
        if (self.history) |h| {
            const hist_row_start = @as(usize, self.history_write_idx) * row_len;
            @memcpy(h[hist_row_start .. hist_row_start + row_len], c[top_start..top_end]);
            if (self.history_wraps) |wraps| {
                wraps[self.history_write_idx] = self.rowWrapped(0);
            }
            self.history_write_idx = (self.history_write_idx + 1) % self.history_capacity;
            if (self.history_count < self.history_capacity) {
                self.history_count += 1;
            }
        }
        self.row_origin = @intCast((@as(usize, self.row_origin) + 1) % @as(usize, self.rows));
        const bottom_start = self.rowStart(self.rows - 1);
        @memset(c[bottom_start .. bottom_start + row_len], 0);
        self.setRowWrapped(self.rows - 1, false);
    }

    fn rowStart(self: *const GridModel, logical_row: u16) usize {
        const physical_row = (@as(usize, self.row_origin) + @as(usize, logical_row)) % @as(usize, self.rows);
        return physical_row * @as(usize, self.cols);
    }

    fn rowWrapIndex(self: *const GridModel, logical_row: u16) ?usize {
        _ = self.row_wraps orelse return null;
        if (self.rows == 0 or logical_row >= self.rows) return null;
        return (@as(usize, self.row_origin) + @as(usize, logical_row)) % @as(usize, self.rows);
    }

    fn rowWrapped(self: *const GridModel, logical_row: u16) bool {
        const wraps = self.row_wraps orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        return wraps[idx];
    }

    fn setRowWrapped(self: *GridModel, logical_row: u16, wrapped: bool) void {
        const wraps = self.row_wraps orelse return;
        const idx = self.rowWrapIndex(logical_row) orelse return;
        wraps[idx] = wrapped;
    }

    fn historySlotForRecency(self: *const GridModel, history_idx: u16) ?usize {
        if (history_idx >= self.history_count or self.history_capacity == 0) return null;
        const cap = @as(usize, self.history_capacity);
        const newest_slot = (@as(usize, self.history_write_idx) + cap - 1) % cap;
        return (newest_slot + cap - @as(usize, history_idx)) % cap;
    }

    fn historyRowWrapped(self: *const GridModel, history_idx: u16) bool {
        const wraps = self.history_wraps orelse return false;
        const slot = self.historySlotForRecency(history_idx) orelse return false;
        return wraps[slot];
    }

    fn clearRowRange(self: *GridModel, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const start = self.rowStart(row);
        @memset(c[start + @as(usize, start_col) .. start + @as(usize, end_col_exclusive)], 0);
    }
};
