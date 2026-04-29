//! Responsibility: verify the stable public API api for vt-core consumers.
//! Ownership: API conformance test surface.
//! Reason: keep non-trivial facade/signature checks out of the root export file.

const std = @import("std");
const mod = @import("../runtime/vt_core.zig");
const screen_mod = @import("../screen/state.zig");
const model_mod = @import("../model.zig");

test "root: VtCore exposes stable facade methods" {
    const VtCore = mod.VtCore;
    try std.testing.expect(@hasDecl(VtCore, "init"));
    try std.testing.expect(@hasDecl(VtCore, "initWithCells"));
    try std.testing.expect(@hasDecl(VtCore, "deinit"));
    try std.testing.expect(@hasDecl(VtCore, "feedByte"));
    try std.testing.expect(@hasDecl(VtCore, "feedSlice"));
    try std.testing.expect(@hasDecl(VtCore, "apply"));
    try std.testing.expect(@hasDecl(VtCore, "clear"));
    try std.testing.expect(@hasDecl(VtCore, "reset"));
    try std.testing.expect(@hasDecl(VtCore, "resetScreen"));
    try std.testing.expect(@hasDecl(VtCore, "screen"));
    try std.testing.expect(@hasDecl(VtCore, "queuedEventCount"));
}

test "root: VtCore method signatures remain host-facing" {
    const VtCore = mod.VtCore;
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
    const screen_fn: fn (*const VtCore) *const ScreenState = VtCore.screen;
    const queue_fn: fn (*const VtCore) usize = VtCore.queuedEventCount;
    _ = .{ init_fn, init_cells_fn, deinit_fn, feed_byte_fn, feed_slice_fn, apply_fn, clear_fn, reset_fn, reset_screen_fn, screen_fn, queue_fn };
}

test "const-read history and selection accessors stay stable" {
    const VtCore = mod.VtCore;
    const history_row_fn: fn (*const VtCore, u16, u16) u21 = VtCore.historyRowAt;
    const history_count_fn: fn (*const VtCore) u16 = VtCore.historyCount;
    const history_capacity_fn: fn (*const VtCore) u16 = VtCore.historyCapacity;
    const selection_state_fn: fn (*const VtCore) ?model_mod.TerminalSelection = VtCore.selectionState;
    _ = .{ history_row_fn, history_count_fn, history_capacity_fn, selection_state_fn };
}

test "lifecycle extension methods stay stable" {
    const VtCore = mod.VtCore;
    const init_cells_history_fn: fn (std.mem.Allocator, u16, u16, u16) anyerror!VtCore = VtCore.initWithCellsAndHistory;
    const selection_start_fn: fn (*VtCore, i32, u16) void = VtCore.selectionStart;
    const selection_update_fn: fn (*VtCore, i32, u16) void = VtCore.selectionUpdate;
    const selection_finish_fn: fn (*VtCore) void = VtCore.selectionFinish;
    const selection_clear_fn: fn (*VtCore) void = VtCore.selectionClear;
    _ = .{ init_cells_history_fn, selection_start_fn, selection_update_fn, selection_finish_fn, selection_clear_fn };
}

test "snapshot surface remains deterministic" {
    const VtCore = mod.VtCore;
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

test "encodeKey and encodeMouse methods are callable" {
    const VtCore = mod.VtCore;
    const allocator = std.testing.allocator;
    var vt_core = try VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    const encode_key_fn: fn (*VtCore, model_mod.Key, model_mod.Modifier) []const u8 = VtCore.encodeKey;
    const encode_mouse_fn: fn (*VtCore, model_mod.MouseEvent) []const u8 = VtCore.encodeMouse;
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

test "encodeMouse returns empty output" {
    const allocator = std.testing.allocator;
    var vt_core = try mod.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("TEST");
    vt_core.apply();

    const mouse_event = model_mod.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = 0,
        .col = 0,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 0,
    };

    const output = vt_core.encodeMouse(mouse_event);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    try std.testing.expectEqualSlices(u8, "", output);
}

test "encodeMouse does not mutate observable vt_core state" {
    const allocator = std.testing.allocator;
    var vt_core = try mod.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("HELLO");
    vt_core.apply();

    var snap_before = try vt_core.snapshot();
    defer snap_before.deinit();

    const mouse_event = model_mod.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };

    _ = vt_core.encodeMouse(mouse_event);

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
}

test "root exposes key and modifier constants" {
    const root = @import("../root.zig");
    _ = root.mod_none;
    _ = root.mod_shift;
    _ = root.mod_alt;
    _ = root.mod_ctrl;
    _ = root.key_enter;
    _ = root.key_tab;
    _ = root.key_backspace;
    _ = root.key_escape;
    _ = root.key_up;
    _ = root.key_down;
    _ = root.key_left;
    _ = root.key_right;
}
