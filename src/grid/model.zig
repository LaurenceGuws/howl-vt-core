//! Responsibility: hold grid cursor/cell/history state and apply semantics.
//! Ownership: terminal grid model authority.
//! Reason: centralize deterministic grid mutations behind semantic operations.

const std = @import("std");
const interpret_owner = @import("../interpret.zig");
const types = @import("types.zig");

/// Semantic event alias for grid application.
const SemanticEvent = interpret_owner.Interpret.SemanticEvent;
const Cell = types.Cell;
const Color = types.Color;
const CellAttrs = types.CellAttrs;
const CursorStyle = types.CursorStyle;
const default_cell = types.default_cell;
const default_cell_attrs = types.default_cell_attrs;
const default_underline_color = types.default_underline_color;

const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,
    cursor_offset: ?usize = null,
};

const HistoryLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,

    fn deinit(self: *HistoryLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

const RewrappedRow = struct {
    start: usize,
    len: usize,
    wrapped: bool,
};

pub const DirtyRows = struct {
    start_row: u16,
    end_row: u16,
};

/// Terminal grid model for cursor/cell/history behavior.
pub const GridModel = struct {
    allocator: ?std.mem.Allocator,
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    wrap_pending: bool,
    cursor_visible: bool,
    cursor_style: CursorStyle,
    auto_wrap: bool,
    view_padding_rows: u16,
    row_origin: u16,
    cells: ?[]Cell,
    row_wraps: ?[]bool,
    history: ?[]Cell,
    history_wraps: ?[]bool,
    history_capacity: u16,
    history_count: usize,
    history_write_idx: usize,
    history_lines: std.ArrayListUnmanaged(HistoryLine),
    open_history_line: ?HistoryLine,
    current_attrs: CellAttrs,
    dirty_rows: ?DirtyRows,

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) GridModel {
        return .{
            .allocator = null,
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .cursor_style = types.default_cursor_style,
            .auto_wrap = true,
            .view_padding_rows = 0,
            .row_origin = 0,
            .cells = null,
            .row_wraps = null,
            .history = null,
            .history_wraps = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
            .history_lines = .empty,
            .open_history_line = null,
            .current_attrs = default_cell_attrs,
            .dirty_rows = null,
        };
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !GridModel {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]Cell = if (size > 0) blk: {
            const buf = try allocator.alloc(Cell, size);
            @memset(buf, default_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            break :blk buf;
        } else null;
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .cursor_style = types.default_cursor_style,
            .auto_wrap = true,
            .view_padding_rows = 0,
            .row_origin = 0,
            .cells = cells,
            .row_wraps = row_wraps,
            .history = null,
            .history_wraps = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
            .history_lines = .empty,
            .open_history_line = null,
            .current_attrs = default_cell_attrs,
            .dirty_rows = if (rows > 0) .{ .start_row = 0, .end_row = rows -| 1 } else null,
        };
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !GridModel {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]Cell = if (size > 0) blk: {
            const buf = try allocator.alloc(Cell, size);
            @memset(buf, default_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            break :blk buf;
        } else null;
        errdefer if (row_wraps) |buf| allocator.free(buf);
        const history: ?[]Cell = if (cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(Cell, 0);
            break :blk buf;
        } else null;
        errdefer if (history) |buf| allocator.free(buf);
        const history_wraps: ?[]bool = if (cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(bool, 0);
            break :blk buf;
        } else null;
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .cursor_style = types.default_cursor_style,
            .auto_wrap = true,
            .view_padding_rows = 0,
            .row_origin = 0,
            .cells = cells,
            .row_wraps = row_wraps,
            .history = history,
            .history_wraps = history_wraps,
            .history_capacity = if (cells != null) history_capacity else 0,
            .history_count = 0,
            .history_write_idx = 0,
            .history_lines = .empty,
            .open_history_line = null,
            .current_attrs = default_cell_attrs,
            .dirty_rows = if (rows > 0) .{ .start_row = 0, .end_row = rows -| 1 } else null,
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
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.deinit(allocator);
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
    }

    /// Resize visible grid while preserving retained history rows.
    pub fn resize(self: *GridModel, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        self.allocator = allocator;
        try self.resizeWithReflow(allocator, rows, cols);
    }

    fn resizeWithReflow(self: *GridModel, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        const old_cells = self.cells;
        const old_row_wraps = self.row_wraps;
        const old_rows = self.rows;
        const old_history = self.history;
        const old_history_wraps = self.history_wraps;

        var logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty;
        defer {
            for (logical_lines.items) |*line| line.cells.deinit(allocator);
            logical_lines.deinit(allocator);
        }

        var current_line = try self.cloneOpenHistoryAsLogicalLine(allocator);
        defer current_line.cells.deinit(allocator);

        var cursor_line_index: usize = 0;
        var cursor_offset: usize = 0;
        var cursor_found = false;

        for (self.history_lines.items) |line| {
            var copied = try cloneHistoryLine(allocator, line.cells.items);
            copied.cursor_offset = null;
            try logical_lines.append(allocator, copied);
        }

        var row: u16 = 0;
        while (row < old_rows) : (row += 1) {
            try self.appendSourceRowToLogicalLines(
                allocator,
                &logical_lines,
                &current_line,
                row,
                self.cols,
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

        while (logical_lines.items.len > 1) {
            const last_idx = logical_lines.items.len - 1;
            const last = &logical_lines.items[last_idx];
            if (last.cells.items.len > 0) break;
            if (cursor_found and cursor_line_index == last_idx) break;
            last.cells.deinit(allocator);
            logical_lines.items.len = last_idx;
        }

        var flat_rows: std.ArrayListUnmanaged(Cell) = .empty;
        defer flat_rows.deinit(allocator);
        var rewrapped: std.ArrayListUnmanaged(RewrappedRow) = .empty;
        defer rewrapped.deinit(allocator);
        var line_row_starts: std.ArrayListUnmanaged(usize) = .empty;
        defer line_row_starts.deinit(allocator);
        var line_row_counts: std.ArrayListUnmanaged(usize) = .empty;
        defer line_row_counts.deinit(allocator);

        var global_cursor_row: usize = 0;
        var global_cursor_col: usize = 0;
        var next_wrap_pending = false;
        var row_cursor_base: usize = 0;

        for (logical_lines.items, 0..) |line, line_idx| {
            const has_cursor = cursor_found and cursor_line_index == line_idx;
            const line_cursor_offset = if (has_cursor) @min(cursor_offset, line.cells.items.len) else 0;
            const effective_len = line.cells.items.len;
            const row_count: usize = if (cols == 0) 0 else @max(1, std.math.divCeil(usize, effective_len, cols) catch unreachable);
            try line_row_starts.append(allocator, rewrapped.items.len);
            try line_row_counts.append(allocator, row_count);

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
                        try flat_rows.append(allocator, default_cell);
                    }
                }
            }

            row_cursor_base += row_count;
        }

        const total_rows = rewrapped.items.len;
        const visible_rows_kept: usize = @min(@as(usize, rows), total_rows);
        const visible_start = total_rows - visible_rows_kept;
        const top_blank_rows: usize = 0;
        const first_visible_line = firstLineForRow(line_row_starts.items, line_row_counts.items, visible_start) orelse logical_lines.items.len;
        const hidden_rows_in_first_visible_line: usize = if (first_visible_line < logical_lines.items.len)
            visible_start - line_row_starts.items[first_visible_line]
        else
            0;

        const cell_count = @as(usize, rows) * @as(usize, cols);
        var new_cells: ?[]Cell = null;
        if (cell_count > 0) {
            const buf = try allocator.alloc(Cell, cell_count);
            @memset(buf, default_cell);
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
        self.history = null;
        self.history_wraps = null;
        self.history_count = 0;
        self.history_write_idx = 0;
        self.row_origin = 0;
        self.view_padding_rows = 0;
        self.dirty_rows = if (rows > 0) .{ .start_row = 0, .end_row = rows -| 1 } else null;

        try self.replaceHistoryAuthority(
            allocator,
            logical_lines.items,
            line_row_starts.items,
            line_row_counts.items,
            first_visible_line,
            hidden_rows_in_first_visible_line,
            rewrapped.items,
            cols,
        );
        try self.rebuildHistoryProjection(allocator);

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
        cols: u16,
        cursor_found: *bool,
        cursor_line_index: *usize,
        cursor_offset: *usize,
    ) !void {
        const wrapped = self.rowWrapped(row_index);
        const is_cursor_row = row_index == self.cursor_row;
        const content_len = self.sourceRowContentLen(row_index, cols);

        if (is_cursor_row) {
            const row_cursor_offset = self.cursorOffsetInRow(cols);
            current_line.cursor_offset = current_line.cells.items.len + row_cursor_offset;
        }

        var col: u16 = 0;
        while (col < content_len) : (col += 1) {
            try current_line.cells.append(allocator, self.cellInfoAt(row_index, col));
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

    fn sourceRowContentLen(self: *const GridModel, row_index: u16, cols: u16) u16 {
        var last_non_zero: u16 = 0;
        var has_content = false;
        var col: u16 = 0;
        while (col < cols) : (col += 1) {
            const value = self.cellInfoAt(row_index, col);
            if (value.codepoint != 0) {
                has_content = true;
                last_non_zero = col + 1;
            }
        }

        var len: u16 = if (has_content) last_non_zero else 0;
        if (self.rowWrapped(row_index) and cols > 0) {
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

    fn cloneHistoryLine(allocator: std.mem.Allocator, cells: []const Cell) !LogicalLine {
        var line = LogicalLine{};
        try line.cells.appendSlice(allocator, cells);
        return line;
    }

    fn cloneHistoryAuthorityLine(allocator: std.mem.Allocator, cells: []const Cell) !HistoryLine {
        var line = HistoryLine{};
        try line.cells.appendSlice(allocator, cells);
        return line;
    }

    fn cloneOpenHistoryAsLogicalLine(self: *const GridModel, allocator: std.mem.Allocator) !LogicalLine {
        var line = LogicalLine{};
        if (self.open_history_line) |open_line| {
            try line.cells.appendSlice(allocator, open_line.cells.items);
        }
        return line;
    }

    fn firstLineForRow(line_row_starts: []const usize, line_row_counts: []const usize, row_index: usize) ?usize {
        for (line_row_starts, line_row_counts, 0..) |row_start, row_count, line_idx| {
            if (row_count == 0) continue;
            if (row_index < row_start + row_count) return line_idx;
        }
        return null;
    }

    fn replaceHistoryAuthority(
        self: *GridModel,
        allocator: std.mem.Allocator,
        logical_lines: []const LogicalLine,
        line_row_starts: []const usize,
        line_row_counts: []const usize,
        first_visible_line: usize,
        hidden_rows_in_first_visible_line: usize,
        rewrapped: []const RewrappedRow,
        cols: u16,
    ) !void {
        self.clearHistoryAuthority(allocator);

        const kept_complete_start = if (first_visible_line > @as(usize, self.history_capacity))
            first_visible_line - @as(usize, self.history_capacity)
        else
            0;

        var line_idx = kept_complete_start;
        while (line_idx < first_visible_line) : (line_idx += 1) {
            try self.history_lines.append(allocator, try cloneHistoryAuthorityLine(allocator, logical_lines[line_idx].cells.items));
        }

        if (first_visible_line < logical_lines.len and hidden_rows_in_first_visible_line > 0) {
            const line = logical_lines[first_visible_line];
            const row_start = line_row_starts[first_visible_line];
            const row_limit = @min(hidden_rows_in_first_visible_line, line_row_counts[first_visible_line]);
            var prefix_len: usize = 0;
            var hidden_row: usize = 0;
            while (hidden_row < row_limit) : (hidden_row += 1) {
                prefix_len += rewrapped[row_start + hidden_row].len;
            }
            prefix_len = @min(prefix_len, line.cells.items.len);
            self.open_history_line = try cloneHistoryAuthorityLine(allocator, line.cells.items[0..prefix_len]);
        }

        if (self.history_lines.items.len > self.history_capacity) {
            const drop = self.history_lines.items.len - self.history_capacity;
            var i: usize = 0;
            while (i < drop) : (i += 1) {
                self.history_lines.items[i].deinit(allocator);
            }
            std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
            self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
        }

        _ = cols;
    }

    fn clearHistoryAuthority(self: *GridModel, allocator: std.mem.Allocator) void {
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.clearRetainingCapacity();
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
    }

    fn rebuildHistoryProjection(self: *GridModel, allocator: std.mem.Allocator) !void {
        if (self.history) |buf| allocator.free(buf);
        self.history = null;
        if (self.history_wraps) |buf| allocator.free(buf);
        self.history_wraps = null;
        self.history_count = 0;
        self.history_write_idx = 0;

        if (self.history_capacity == 0 or self.cols == 0) return;

        var row_starts: std.ArrayListUnmanaged(usize) = .empty;
        defer row_starts.deinit(allocator);
        var row_lens: std.ArrayListUnmanaged(usize) = .empty;
        defer row_lens.deinit(allocator);
        var row_wraps: std.ArrayListUnmanaged(bool) = .empty;
        defer row_wraps.deinit(allocator);
        var flat_cells: std.ArrayListUnmanaged(Cell) = .empty;
        defer flat_cells.deinit(allocator);

        for (self.history_lines.items) |line| {
            try self.appendHistoryProjectionRows(allocator, line.cells.items, false, &row_starts, &row_lens, &row_wraps, &flat_cells);
        }
        if (self.open_history_line) |line| {
            try self.appendHistoryProjectionRows(allocator, line.cells.items, true, &row_starts, &row_lens, &row_wraps, &flat_cells);
        }

        self.history_count = row_wraps.items.len;
        self.history_write_idx = 0;
        self.history = try allocator.alloc(Cell, flat_cells.items.len);
        @memcpy(self.history.?, flat_cells.items);
        self.history_wraps = try allocator.alloc(bool, row_wraps.items.len);
        @memcpy(self.history_wraps.?, row_wraps.items);
    }

    fn appendHistoryProjectionRows(
        self: *const GridModel,
        allocator: std.mem.Allocator,
        cells: []const Cell,
        continues_to_visible: bool,
        row_starts: *std.ArrayListUnmanaged(usize),
        row_lens: *std.ArrayListUnmanaged(usize),
        row_wraps: *std.ArrayListUnmanaged(bool),
        flat_cells: *std.ArrayListUnmanaged(Cell),
    ) !void {
        const cols = @as(usize, self.cols);
        if (cols == 0) return;
        const row_count: usize = @max(1, std.math.divCeil(usize, cells.len, cols) catch unreachable);

        var row_idx: usize = 0;
        while (row_idx < row_count) : (row_idx += 1) {
            const start = row_idx * cols;
            const end = @min(cells.len, start + cols);
            try row_starts.append(allocator, flat_cells.items.len);
            try row_lens.append(allocator, end - start);
            try row_wraps.append(allocator, row_idx + 1 < row_count or continues_to_visible);
            var col_idx: usize = 0;
            while (col_idx < cols) : (col_idx += 1) {
                const src_idx = start + col_idx;
                if (src_idx < cells.len) {
                    try flat_cells.append(allocator, cells[src_idx]);
                } else {
                    try flat_cells.append(allocator, default_cell);
                }
            }
        }
    }

    fn storeHistoryRow(self: *GridModel, row: u16) void {
        if (self.history_capacity == 0) return;
        const allocator = self.allocator orelse return;
        const wrapped = self.rowWrapped(row);
        const len = self.visibleRowContentLen(row);
        if (self.open_history_line == null) self.open_history_line = .{};
        const open_line = &self.open_history_line.?;
        var col: u16 = 0;
        while (col < len) : (col += 1) {
            open_line.cells.append(allocator, self.cellInfoAt(row, col)) catch return;
        }
        if (!wrapped) {
            const finalized = self.open_history_line.?;
            self.open_history_line = null;
            self.history_lines.append(allocator, finalized) catch {
                var failed = finalized;
                failed.deinit(allocator);
                return;
            };
            self.pruneHistoryLines(allocator);
        }
        self.rebuildHistoryProjection(allocator) catch {};
    }

    fn visibleRowContentLen(self: *const GridModel, row: u16) u16 {
        var col = self.cols;
        while (col > 0) {
            const idx = col - 1;
            if (self.cellInfoAt(row, idx).codepoint != 0) return col;
            col -= 1;
        }
        if (self.rowWrapped(row) and self.cols > 0) return self.cols;
        return 0;
    }

    fn pruneHistoryLines(self: *GridModel, allocator: std.mem.Allocator) void {
        if (self.history_lines.items.len <= self.history_capacity) return;
        const drop = self.history_lines.items.len - self.history_capacity;
        var i: usize = 0;
        while (i < drop) : (i += 1) {
            self.history_lines.items[i].deinit(allocator);
        }
        std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
        self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
    }

    /// Reset visible grid state to defaults.
    pub fn reset(self: *GridModel) void {
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.wrap_pending = false;
        self.cursor_visible = true;
        self.cursor_style = types.default_cursor_style;
        self.auto_wrap = true;
        self.view_padding_rows = 0;
        self.row_origin = 0;
        self.current_attrs = default_cell_attrs;
        self.dirty_rows = if (self.rows > 0) .{ .start_row = 0, .end_row = self.rows -| 1 } else null;
        if (self.cells) |c| @memset(c, default_cell);
        if (self.row_wraps) |buf| @memset(buf, false);
    }

    pub fn peekDirtyRows(self: *const GridModel) ?DirtyRows {
        return self.dirty_rows;
    }

    pub fn clearDirtyRows(self: *GridModel) void {
        self.dirty_rows = null;
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const GridModel, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    pub fn cellInfoAt(self: *const GridModel, row: u16, col: u16) Cell {
        const c = self.cells orelse return default_cell;
        if (row >= self.rows or col >= self.cols) return default_cell;
        const start = self.rowStart(row);
        return c[start + @as(usize, col)];
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const GridModel, history_idx: usize, col: u16) u21 {
        return @intCast(self.historyCellAt(history_idx, col).codepoint);
    }

    pub fn historyCellAt(self: *const GridModel, history_idx: usize, col: u16) Cell {
        const h = self.history orelse return default_cell;
        if (history_idx >= self.history_count or col >= self.cols) return default_cell;
        const slot = self.historySlotForRecency(history_idx) orelse return default_cell;
        return h[slot * @as(usize, self.cols) + @as(usize, col)];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const GridModel) usize {
        return self.history_count;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const GridModel) u16 {
        return self.history_capacity;
    }

    /// Report whether selection endpoint should be invalidated.
    pub fn shouldInvalidateSelectionEndpoint(self: *const GridModel, endpoint_row: i32) bool {
        if (self.history_capacity == 0 or self.history_lines.items.len < self.history_capacity) {
            return false;
        }
        const projected_rows_i32: i32 = if (self.history_count > @as(usize, std.math.maxInt(i32)))
            std.math.maxInt(i32)
        else
            @intCast(self.history_count);
        if (endpoint_row < -projected_rows_i32) {
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
            .sgr => |sgr| self.applySgr(sgr.params[0..sgr.param_count]),
            .enter_alt_screen, .exit_alt_screen => {},
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
                self.markDirtyRows(self.cursor_row, self.rows -| 1);
                self.clearRowRange(self.cursor_row, self.cursor_col, self.cols);
                var r = self.cursor_row + 1;
                while (r < self.rows) : (r += 1) {
                    const start = self.rowStart(r);
                    @memset(c[start .. start + @as(usize, self.cols)], default_cell);
                    self.setRowWrapped(r, false);
                }
            },
            1 => {
                self.markDirtyRows(0, self.cursor_row);
                var r: u16 = 0;
                while (r < self.cursor_row) : (r += 1) {
                    const start = self.rowStart(r);
                    @memset(c[start .. start + @as(usize, self.cols)], default_cell);
                    self.setRowWrapped(r, false);
                }
                self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1);
            },
            2 => {
                self.markAllRowsDirty();
                @memset(c, default_cell);
                if (self.row_wraps) |buf| @memset(buf, false);
            },
            3 => {},
        }
    }

    fn eraseLine(self: *GridModel, mode: u2) void {
        _ = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        self.markDirtyRow(self.cursor_row);
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
            self.markDirtyRow(self.cursor_row);
            c[start + @as(usize, self.cursor_col)] = .{
                .codepoint = cp,
                .attrs = self.current_attrs,
            };
        }
        if (self.cursor_col < self.cols - 1) {
            self.cursor_col += 1;
        } else if (self.auto_wrap) {
            self.wrap_pending = true;
        }
    }

    fn applySgr(self: *GridModel, params: []const i32) void {
        if (params.len == 0) {
            self.current_attrs = default_cell_attrs;
            return;
        }

        var i: usize = 0;
        while (i < params.len) : (i += 1) {
            const p = params[i];
            switch (p) {
                0 => self.current_attrs = default_cell_attrs,
                1 => self.current_attrs.bold = true,
                4 => self.current_attrs.underline = true,
                5, 6 => self.current_attrs.blink = true,
                7 => self.current_attrs.reverse = true,
                22 => self.current_attrs.bold = false,
                24 => self.current_attrs.underline = false,
                25 => {
                    self.current_attrs.blink = false;
                    self.current_attrs.blink_fast = false;
                },
                27 => self.current_attrs.reverse = false,
                30...37 => self.current_attrs.fg = ansi16Color(@intCast(p - 30)),
                39 => self.current_attrs.fg = default_cell_attrs.fg,
                40...47 => self.current_attrs.bg = ansi16Color(@intCast(p - 40)),
                49 => self.current_attrs.bg = default_cell_attrs.bg,
                90...97 => self.current_attrs.fg = ansi16Color(@intCast((p - 90) + 8)),
                100...107 => self.current_attrs.bg = ansi16Color(@intCast((p - 100) + 8)),
                38, 48 => {
                    const is_fg = p == 38;
                    if (i + 1 >= params.len) break;
                    const mode = params[i + 1];
                    if (mode == 5) {
                        if (i + 2 >= params.len) break;
                        const color = indexed256Color(clampByte(params[i + 2]));
                        if (is_fg) self.current_attrs.fg = color else self.current_attrs.bg = color;
                        i += 2;
                    } else if (mode == 2) {
                        if (i + 4 >= params.len) break;
                        const color = Color{
                            .r = clampByte(params[i + 2]),
                            .g = clampByte(params[i + 3]),
                            .b = clampByte(params[i + 4]),
                        };
                        if (is_fg) self.current_attrs.fg = color else self.current_attrs.bg = color;
                        i += 4;
                    }
                },
                58 => {
                    if (i + 1 >= params.len) break;
                    const mode = params[i + 1];
                    if (mode == 5) {
                        if (i + 2 >= params.len) break;
                        self.current_attrs.underline_color = indexed256Color(clampByte(params[i + 2]));
                        i += 2;
                    } else if (mode == 2) {
                        if (i + 4 >= params.len) break;
                        self.current_attrs.underline_color = .{
                            .r = clampByte(params[i + 2]),
                            .g = clampByte(params[i + 3]),
                            .b = clampByte(params[i + 4]),
                        };
                        i += 4;
                    }
                },
                59 => self.current_attrs.underline_color = default_underline_color,
                else => {},
            }
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
        self.markAllRowsDirty();
        const row_len = @as(usize, self.cols);
        self.storeHistoryRow(0);
        self.row_origin = @intCast((@as(usize, self.row_origin) + 1) % @as(usize, self.rows));
        const bottom_start = self.rowStart(self.rows - 1);
        @memset(c[bottom_start .. bottom_start + row_len], default_cell);
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

    fn historySlotForRecency(self: *const GridModel, history_idx: usize) ?usize {
        if (history_idx >= self.history_count) return null;
        return self.history_count - 1 - history_idx;
    }

    fn historyRowWrapped(self: *const GridModel, history_idx: usize) bool {
        const wraps = self.history_wraps orelse return false;
        const slot = self.historySlotForRecency(history_idx) orelse return false;
        return wraps[slot];
    }

    fn clearRowRange(self: *GridModel, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const start = self.rowStart(row);
        @memset(c[start + @as(usize, start_col) .. start + @as(usize, end_col_exclusive)], default_cell);
    }

    fn markDirtyRow(self: *GridModel, row: u16) void {
        if (self.rows == 0 or row >= self.rows) return;
        self.markDirtyRows(row, row);
    }

    fn markDirtyRows(self: *GridModel, start_row: u16, end_row: u16) void {
        if (self.rows == 0) return;
        const start = @min(start_row, self.rows -| 1);
        const end = @min(end_row, self.rows -| 1);
        if (self.dirty_rows) |*d| {
            d.start_row = @min(d.start_row, start);
            d.end_row = @max(d.end_row, end);
        } else {
            self.dirty_rows = .{ .start_row = start, .end_row = end };
        }
    }

    fn markAllRowsDirty(self: *GridModel) void {
        if (self.rows == 0) return;
        self.dirty_rows = .{ .start_row = 0, .end_row = self.rows -| 1 };
    }

    fn clampByte(v: i32) u8 {
        return @intCast(std.math.clamp(v, 0, 255));
    }

    fn ansi16Color(idx: u8) Color {
        return switch (idx) {
            0 => .{ .r = 0, .g = 0, .b = 0 },
            1 => .{ .r = 170, .g = 0, .b = 0 },
            2 => .{ .r = 0, .g = 170, .b = 0 },
            3 => .{ .r = 170, .g = 85, .b = 0 },
            4 => .{ .r = 0, .g = 0, .b = 170 },
            5 => .{ .r = 170, .g = 0, .b = 170 },
            6 => .{ .r = 0, .g = 170, .b = 170 },
            7 => .{ .r = 170, .g = 170, .b = 170 },
            8 => .{ .r = 85, .g = 85, .b = 85 },
            9 => .{ .r = 255, .g = 85, .b = 85 },
            10 => .{ .r = 85, .g = 255, .b = 85 },
            11 => .{ .r = 255, .g = 255, .b = 85 },
            12 => .{ .r = 85, .g = 85, .b = 255 },
            13 => .{ .r = 255, .g = 85, .b = 255 },
            14 => .{ .r = 85, .g = 255, .b = 255 },
            15 => .{ .r = 255, .g = 255, .b = 255 },
            else => default_cell_attrs.fg,
        };
    }

    fn indexed256Color(idx: u8) Color {
        if (idx < 16) return ansi16Color(idx);
        if (idx < 232) {
            const i: u32 = idx - 16;
            return .{
                .r = @intCast((i / 36) * 51),
                .g = @intCast(((i / 6) % 6) * 51),
                .b = @intCast((i % 6) * 51),
            };
        }
        const gray: u8 = @intCast((@as(u32, idx) - 232) * 10 + 8);
        return .{ .r = gray, .g = gray, .b = gray };
    }
};
