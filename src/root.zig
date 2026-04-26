//! Responsibility: expose the package public module surface.
//! Ownership: root API export boundary.
//! Reason: provide stable import paths for parser/runtime/model lanes.

const std = @import("std");

/// Parser module export.
pub const parser = @import("parser/parser.zig");

/// Event pipeline module export.
pub const pipeline = @import("event/pipeline.zig");

/// Semantic mapping module export.
pub const semantic = @import("event/semantic.zig");

/// Screen state module export.
pub const screen = @import("screen/state.zig");

/// Shared model module export.
pub const model = @import("model.zig");

/// Runtime engine module export.
pub const runtime = @import("runtime/engine.zig");

comptime {
    _ = @import("test/relay.zig");
}

test "root: exposes host-neutral module surface" {
    try std.testing.expect(@hasDecl(@This(), "parser"));
    try std.testing.expect(@hasDecl(@This(), "pipeline"));
    try std.testing.expect(@hasDecl(@This(), "semantic"));
    try std.testing.expect(@hasDecl(@This(), "screen"));
    try std.testing.expect(@hasDecl(@This(), "model"));
    try std.testing.expect(@hasDecl(@This(), "runtime"));
}

test "root: runtime Engine exposes stable facade methods" {
    const Engine = runtime.Engine;
    try std.testing.expect(@hasDecl(Engine, "init"));
    try std.testing.expect(@hasDecl(Engine, "initWithCells"));
    try std.testing.expect(@hasDecl(Engine, "deinit"));
    try std.testing.expect(@hasDecl(Engine, "feedByte"));
    try std.testing.expect(@hasDecl(Engine, "feedSlice"));
    try std.testing.expect(@hasDecl(Engine, "apply"));
    try std.testing.expect(@hasDecl(Engine, "clear"));
    try std.testing.expect(@hasDecl(Engine, "reset"));
    try std.testing.expect(@hasDecl(Engine, "resetScreen"));
    try std.testing.expect(@hasDecl(Engine, "screen"));
    try std.testing.expect(@hasDecl(Engine, "queuedEventCount"));
}

test "root: runtime Engine method signatures remain host-facing" {
    const Engine = runtime.Engine;
    const Allocator = std.mem.Allocator;
    const ScreenState = screen.ScreenState;
    const init_fn: fn (Allocator, u16, u16) anyerror!Engine = Engine.init;
    const init_cells_fn: fn (Allocator, u16, u16) anyerror!Engine = Engine.initWithCells;
    const deinit_fn: fn (*Engine) void = Engine.deinit;
    const feed_byte_fn: fn (*Engine, u8) void = Engine.feedByte;
    const feed_slice_fn: fn (*Engine, []const u8) void = Engine.feedSlice;
    const apply_fn: fn (*Engine) void = Engine.apply;
    const clear_fn: fn (*Engine) void = Engine.clear;
    const reset_fn: fn (*Engine) void = Engine.reset;
    const reset_screen_fn: fn (*Engine) void = Engine.resetScreen;
    const screen_fn: fn (*const Engine) *const ScreenState = Engine.screen;
    const queue_fn: fn (*const Engine) usize = Engine.queuedEventCount;
    _ = .{ init_fn, init_cells_fn, deinit_fn, feed_byte_fn, feed_slice_fn, apply_fn, clear_fn, reset_fn, reset_screen_fn, screen_fn, queue_fn };
}

test "runtime: const-read history and selection accessors stay stable" {
    const Engine = runtime.Engine;
    const history_row_fn: fn (*const Engine, u16, u16) u21 = Engine.historyRowAt;
    const history_count_fn: fn (*const Engine) u16 = Engine.historyCount;
    const history_capacity_fn: fn (*const Engine) u16 = Engine.historyCapacity;
    const selection_state_fn: fn (*const Engine) ?model.TerminalSelection = Engine.selectionState;
    _ = .{ history_row_fn, history_count_fn, history_capacity_fn, selection_state_fn };
}

test "runtime: lifecycle extension methods stay stable" {
    const Engine = runtime.Engine;
    const init_cells_history_fn: fn (std.mem.Allocator, u16, u16, u16) anyerror!Engine = Engine.initWithCellsAndHistory;
    const selection_start_fn: fn (*Engine, i32, u16) void = Engine.selectionStart;
    const selection_update_fn: fn (*Engine, i32, u16) void = Engine.selectionUpdate;
    const selection_finish_fn: fn (*Engine) void = Engine.selectionFinish;
    const selection_clear_fn: fn (*Engine) void = Engine.selectionClear;
    _ = .{ init_cells_history_fn, selection_start_fn, selection_update_fn, selection_finish_fn, selection_clear_fn };
}

test "runtime: snapshot surface remains deterministic" {
    const Engine = runtime.Engine;
    const allocator = std.testing.allocator;
    var engine = try Engine.initWithCells(allocator, 5, 10);
    defer engine.deinit();

    engine.feedSlice("TEST");
    engine.apply();

    var snap1 = try engine.snapshot();
    defer snap1.deinit();

    var snap2 = try engine.snapshot();
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.rows, snap2.rows);
    try std.testing.expectEqual(snap1.cols, snap2.cols);
    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
}

test "runtime: encodeKey and encodeMouse methods are callable" {
    const Engine = runtime.Engine;
    const allocator = std.testing.allocator;
    var engine = try Engine.initWithCells(allocator, 5, 10);
    defer engine.deinit();

    const encode_key_fn: fn (*Engine, model.Key, model.Modifier) []const u8 = Engine.encodeKey;
    const encode_mouse_fn: fn (*Engine, model.MouseEvent) []const u8 = Engine.encodeMouse;
    _ = .{ encode_key_fn, encode_mouse_fn };

    engine.feedSlice("TEST");
    engine.apply();

    var snap_before = try engine.snapshot();
    defer snap_before.deinit();

    _ = engine.encodeKey('A', 0);
    _ = engine.encodeKey('B', 0);

    var snap_after = try engine.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
}

test "runtime: encodeMouse returns empty output" {
    const allocator = std.testing.allocator;
    var engine = try runtime.Engine.initWithCells(allocator, 5, 10);
    defer engine.deinit();

    engine.feedSlice("TEST");
    engine.apply();

    const mouse_event = model.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = 0,
        .col = 0,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 0,
    };

    const output = engine.encodeMouse(mouse_event);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    try std.testing.expectEqualSlices(u8, "", output);
}

test "runtime: encodeMouse does not mutate observable engine state" {
    const allocator = std.testing.allocator;
    var engine = try runtime.Engine.initWithCells(allocator, 5, 10);
    defer engine.deinit();

    engine.feedSlice("HELLO");
    engine.apply();

    var snap_before = try engine.snapshot();
    defer snap_before.deinit();

    const mouse_event = model.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };

    _ = engine.encodeMouse(mouse_event);

    var snap_after = try engine.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
}
