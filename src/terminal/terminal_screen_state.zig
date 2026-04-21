const semantic_mod = @import("parser_core_semantic_consumer.zig");

pub const SemanticEvent = semantic_mod.SemanticEvent;

pub const ScreenState = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,

    pub fn init(rows: u16, cols: u16) ScreenState {
        return .{ .rows = rows, .cols = cols, .cursor_row = 0, .cursor_col = 0 };
    }

    pub fn apply(self: *ScreenState, event: SemanticEvent) void {
        switch (event) {
            .cursor_up => |n| self.cursor_row = self.cursor_row -| n,
            .cursor_down => |n| self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1),
            .cursor_forward => |n| self.cursor_col = @min(self.cursor_col +| n, self.cols -| 1),
            .cursor_back => |n| self.cursor_col = self.cursor_col -| n,
            .cursor_position => |pos| {
                self.cursor_row = @min(pos.row, self.rows -| 1);
                self.cursor_col = @min(pos.col, self.cols -| 1);
            },
            else => {},
        }
    }
};
