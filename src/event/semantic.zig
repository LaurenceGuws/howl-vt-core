//! Responsibility: map parser-level events into semantic screen operations.
//! Ownership: event semantic module.
//! Reason: keep CSI/control interpretation separate from parser tokenization.

const std = @import("std");
const bridge_mod = @import("bridge.zig");

/// Event type alias consumed by semantic mapping.
pub const Event = bridge_mod.Event;

/// RGB color representation for 24-bit truecolor.
pub const Rgb = struct { r: u8, g: u8, b: u8 };

/// Individual SGR operation to apply in sequence.
pub const StyleOp = union(enum) {
    reset,
    bold_on,
    bold_off,
    dim_on,
    dim_off,
    strikethrough_on,
    strikethrough_off,
    underline_on,
    underline_off,
    blink_on,
    blink_off,
    conceal_on,
    conceal_off,
    inverse_on,
    inverse_off,
    fg_color: u8,
    bg_color: u8,
    fg_256: u8,
    bg_256: u8,
    fg_rgb: Rgb,
    bg_rgb: Rgb,
    underline_color_256: u8,
    underline_color_rgb: Rgb,
    underline_color_reset,
};

/// Screen-oriented semantic operations derived from parser events.
pub const SemanticEvent = union(enum) {
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_back: u16,
    cursor_position: struct { row: u16, col: u16 },
    write_text: []const u8,
    write_codepoint: u21,
    line_feed,
    carriage_return,
    backspace,
    erase_display: u2,
    erase_line: u2,
    style_reset,
    style_bold_on,
    style_bold_off,
    style_dim_on,
    style_dim_off,
    style_strikethrough_on,
    style_strikethrough_off,
    style_underline_on,
    style_underline_off,
    style_blink_on,
    style_blink_off,
    style_conceal_on,
    style_conceal_off,
    style_inverse_on,
    style_inverse_off,
    style_fg_color: u8,
    style_bg_color: u8,
    style_fg_256: u8,
    style_bg_256: u8,
    style_fg_rgb: Rgb,
    style_bg_rgb: Rgb,
    style_underline_color_256: u8,
    style_underline_color_rgb: Rgb,
    style_underline_color_reset,
    style_operations: struct {
        ops: [16]StyleOp,
        count: u8,
    },
};

/// Convert a parser event into a semantic screen operation when supported.
pub fn process(event: Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| return processCsi(sc.final, sc.params, sc.param_count),
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return processControl(c),
        .title_set, .invalid_sequence => return null,
    }
}

fn processCsi(final: u8, params: [16]i32, count: u8) ?SemanticEvent {
    switch (final) {
        'A' => return SemanticEvent{ .cursor_up = paramOrDefault1(params[0]) },
        'B' => return SemanticEvent{ .cursor_down = paramOrDefault1(params[0]) },
        'C' => return SemanticEvent{ .cursor_forward = paramOrDefault1(params[0]) },
        'D' => return SemanticEvent{ .cursor_back = paramOrDefault1(params[0]) },
        'H', 'f' => {
            const row = paramOrDefault1(params[0]);
            const col = paramOrDefault1(if (count >= 1) params[1] else 0);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'J' => return SemanticEvent{ .erase_display = eraseMode(params[0]) },
        'K' => return SemanticEvent{ .erase_line = eraseMode(params[0]) },
        'm' => return processSgr(params, count),
        else => return null,
    }
}

fn processControl(c: u8) ?SemanticEvent {
    return switch (c) {
        0x0A => SemanticEvent.line_feed,
        0x0D => SemanticEvent.carriage_return,
        0x08 => SemanticEvent.backspace,
        else => null,
    };
}

fn eraseMode(v: i32) u2 {
    return switch (v) {
        1 => 1,
        2 => 2,
        else => 0,
    };
}

fn clampRgbComponent(v: i32) u8 {
    if (v <= 0) return 0;
    if (v >= 255) return 255;
    return @intCast(v);
}

fn appendStyleOp(ops: *[16]StyleOp, op_count: *u8, op: StyleOp) bool {
    if (op_count.* >= ops.len) return false;
    ops[op_count.*] = op;
    op_count.* += 1;
    return true;
}

fn processSgr(params: [16]i32, count: u8) ?SemanticEvent {
    var ops: [16]StyleOp = undefined;
    var op_count: u8 = 0;
    var i: u8 = 0;
    const param_count: u8 = if (count == 0) 1 else @min(count, @as(u8, params.len));
    while (i < param_count and op_count < ops.len) : (i += 1) {
        const param = if (i < count) params[i] else 0;
        const op: ?StyleOp = switch (param) {
            0 => StyleOp.reset,
            1 => StyleOp.bold_on,
            22 => StyleOp.bold_off,
            2 => StyleOp.dim_on,
            9 => StyleOp.strikethrough_on,
            29 => StyleOp.strikethrough_off,
            4 => StyleOp.underline_on,
            24 => StyleOp.underline_off,
            5 => StyleOp.blink_on,
            25 => StyleOp.blink_off,
            8 => StyleOp.conceal_on,
            28 => StyleOp.conceal_off,
            7 => StyleOp.inverse_on,
            27 => StyleOp.inverse_off,
            30...37 => StyleOp{ .fg_color = @intCast(param - 30 + 1) },
            39 => StyleOp{ .fg_color = 0 },
            40...47 => StyleOp{ .bg_color = @intCast(param - 40 + 1) },
            49 => StyleOp{ .bg_color = 0 },
            90...97 => StyleOp{ .fg_color = @intCast(param - 90 + 9) },
            100...107 => StyleOp{ .bg_color = @intCast(param - 100 + 9) },
            38 => blk: {
                if (i + 1 < param_count and params[i + 1] == 2) {
                    if (i + 4 < param_count) {
                        const r = if (i + 2 < count) clampRgbComponent(params[i + 2]) else 0;
                        const g = if (i + 3 < count) clampRgbComponent(params[i + 3]) else 0;
                        const b = if (i + 4 < count) clampRgbComponent(params[i + 4]) else 0;
                        i += 4;
                        break :blk StyleOp{ .fg_rgb = .{ .r = r, .g = g, .b = b } };
                    }
                    // Incomplete truecolor form: consume remainder to avoid misinterpreting subparams.
                    i = param_count - 1;
                    break :blk null;
                } else if (i + 1 < param_count and params[i + 1] == 5) {
                    if (i + 2 < param_count) {
                        const color_idx = if (i + 2 < count) params[i + 2] else 0;
                        i += 2;
                        break :blk StyleOp{ .fg_256 = @intCast(color_idx & 0xFF) };
                    }
                    // Incomplete 256-color form: consume remainder to avoid misinterpreting subparams.
                    i = param_count - 1;
                    break :blk null;
                } else {
                    break :blk null;
                }
            },
            48 => blk: {
                if (i + 1 < param_count and params[i + 1] == 2) {
                    if (i + 4 < param_count) {
                        const r = if (i + 2 < count) clampRgbComponent(params[i + 2]) else 0;
                        const g = if (i + 3 < count) clampRgbComponent(params[i + 3]) else 0;
                        const b = if (i + 4 < count) clampRgbComponent(params[i + 4]) else 0;
                        i += 4;
                        break :blk StyleOp{ .bg_rgb = .{ .r = r, .g = g, .b = b } };
                    }
                    // Incomplete truecolor form: consume remainder to avoid misinterpreting subparams.
                    i = param_count - 1;
                    break :blk null;
                } else if (i + 1 < param_count and params[i + 1] == 5) {
                    if (i + 2 < param_count) {
                        const color_idx = if (i + 2 < count) params[i + 2] else 0;
                        i += 2;
                        break :blk StyleOp{ .bg_256 = @intCast(color_idx & 0xFF) };
                    }
                    // Incomplete 256-color form: consume remainder to avoid misinterpreting subparams.
                    i = param_count - 1;
                    break :blk null;
                } else {
                    break :blk null;
                }
            },
            58 => blk: {
                if (i + 1 < param_count and params[i + 1] == 2) {
                    if (i + 4 < param_count) {
                        const r = if (i + 2 < count) clampRgbComponent(params[i + 2]) else 0;
                        const g = if (i + 3 < count) clampRgbComponent(params[i + 3]) else 0;
                        const b = if (i + 4 < count) clampRgbComponent(params[i + 4]) else 0;
                        i += 4;
                        break :blk StyleOp{ .underline_color_rgb = .{ .r = r, .g = g, .b = b } };
                    }
                    i = param_count - 1;
                    break :blk null;
                } else if (i + 1 < param_count and params[i + 1] == 5) {
                    if (i + 2 < param_count) {
                        const color_idx = if (i + 2 < count) params[i + 2] else 0;
                        i += 2;
                        break :blk StyleOp{ .underline_color_256 = @intCast(color_idx & 0xFF) };
                    }
                    i = param_count - 1;
                    break :blk null;
                } else {
                    break :blk null;
                }
            },
            59 => StyleOp.underline_color_reset,
            else => null,
        };
        if (op) |o| {
            if (!appendStyleOp(&ops, &op_count, o)) break;
            if (param == 22) {
                if (!appendStyleOp(&ops, &op_count, StyleOp.dim_off)) break;
            }
        }
    }
    if (op_count == 0) return null;

    if (op_count == 1) {
        return switch (ops[0]) {
            .reset => SemanticEvent.style_reset,
            .bold_on => SemanticEvent.style_bold_on,
            .bold_off => SemanticEvent.style_bold_off,
            .dim_on => SemanticEvent.style_dim_on,
            .dim_off => SemanticEvent.style_dim_off,
            .strikethrough_on => SemanticEvent.style_strikethrough_on,
            .strikethrough_off => SemanticEvent.style_strikethrough_off,
            .underline_on => SemanticEvent.style_underline_on,
            .underline_off => SemanticEvent.style_underline_off,
            .blink_on => SemanticEvent.style_blink_on,
            .blink_off => SemanticEvent.style_blink_off,
            .conceal_on => SemanticEvent.style_conceal_on,
            .conceal_off => SemanticEvent.style_conceal_off,
            .inverse_on => SemanticEvent.style_inverse_on,
            .inverse_off => SemanticEvent.style_inverse_off,
            .fg_color => |c| SemanticEvent{ .style_fg_color = c },
            .bg_color => |c| SemanticEvent{ .style_bg_color = c },
            .fg_256 => |c| SemanticEvent{ .style_fg_256 = c },
            .bg_256 => |c| SemanticEvent{ .style_bg_256 = c },
            .fg_rgb => |rgb| SemanticEvent{ .style_fg_rgb = rgb },
            .bg_rgb => |rgb| SemanticEvent{ .style_bg_rgb = rgb },
            .underline_color_256 => |c| SemanticEvent{ .style_underline_color_256 = c },
            .underline_color_rgb => |rgb| SemanticEvent{ .style_underline_color_rgb = rgb },
            .underline_color_reset => SemanticEvent.style_underline_color_reset,
        };
    }
    return SemanticEvent{ .style_operations = .{ .ops = ops, .count = op_count } };
}

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn makeStyleChange(final: u8, p0: i32, p1: i32, count: u8) Event {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = p0;
    params[1] = p1;
    return Event{ .style_change = .{ .final = final, .params = params, .param_count = count } };
}

test "semantic: CUU explicit count" {
    const sem = process(makeStyleChange('A', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.cursor_up);
}

test "semantic: CUU zero param defaults to 1" {
    const sem = process(makeStyleChange('A', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_up);
}

test "semantic: CUD" {
    const sem = process(makeStyleChange('B', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 5), sem.cursor_down);
}

test "semantic: CUF" {
    const sem = process(makeStyleChange('C', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_forward);
}

test "semantic: CUB" {
    const sem = process(makeStyleChange('D', 4, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), sem.cursor_back);
}

test "semantic: CUP explicit row and col" {
    const sem = process(makeStyleChange('H', 3, 5, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 4), sem.cursor_position.col);
}

test "semantic: CUP no params defaults to origin" {
    const sem = process(makeStyleChange('H', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_position.col);
}

test "semantic: unsupported CSI returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(makeStyleChange('X', 1, 0, 1)));
}

test "semantic: text event maps to write_text" {
    const sem = process(Event{ .text = "hello" }) orelse return error.NoEvent;
    try std.testing.expectEqualSlices(u8, "hello", sem.write_text);
}

test "semantic: codepoint event maps to write_codepoint" {
    const sem = process(Event{ .codepoint = 0xE9 }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u21, 0xE9), sem.write_codepoint);
}

test "semantic: LF maps to line_feed" {
    const sem = process(Event{ .control = 0x0A }) orelse return error.NoEvent;
    try std.testing.expect(sem == .line_feed);
}

test "semantic: CR maps to carriage_return" {
    const sem = process(Event{ .control = 0x0D }) orelse return error.NoEvent;
    try std.testing.expect(sem == .carriage_return);
}

test "semantic: BS maps to backspace" {
    const sem = process(Event{ .control = 0x08 }) orelse return error.NoEvent;
    try std.testing.expect(sem == .backspace);
}

test "semantic: invalid_sequence returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event.invalid_sequence));
}

test "semantic: title_set returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .title_set = "My Title" }));
}

test "semantic: ED no param defaults to mode 0" {
    const sem = process(makeStyleChange('J', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 0), sem.erase_display);
}

test "semantic: ED mode 1 above" {
    const sem = process(makeStyleChange('J', 1, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 1), sem.erase_display);
}

test "semantic: ED mode 2 full" {
    const sem = process(makeStyleChange('J', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 2), sem.erase_display);
}

test "semantic: EL mode 0 right" {
    const sem = process(makeStyleChange('K', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 0), sem.erase_line);
}

test "semantic: EL mode 1 left" {
    const sem = process(makeStyleChange('K', 1, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 1), sem.erase_line);
}

test "semantic: EL mode 2 full line" {
    const sem = process(makeStyleChange('K', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 2), sem.erase_line);
}

test "semantic: EL invalid mode maps to 0" {
    const sem = process(makeStyleChange('K', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 0), sem.erase_line);
}

test "semantic: SGR reset with no params defaults to 0" {
    const sem = process(makeStyleChange('m', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_reset);
}

test "semantic: SGR 0 reset" {
    const sem = process(makeStyleChange('m', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_reset);
}

test "semantic: SGR 1 bold on" {
    const sem = process(makeStyleChange('m', 1, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_bold_on);
}

test "semantic: SGR 2 dim on" {
    const sem = process(makeStyleChange('m', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_dim_on);
}

test "semantic: SGR 22 emits bold_off and dim_off" {
    const sem = process(makeStyleChange('m', 22, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .bold_off);
    try std.testing.expect(sem.style_operations.ops[1] == .dim_off);
}

test "semantic: SGR 9 strikethrough on" {
    const sem = process(makeStyleChange('m', 9, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_strikethrough_on);
}

test "semantic: SGR 29 strikethrough off" {
    const sem = process(makeStyleChange('m', 29, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_strikethrough_off);
}

test "semantic: SGR 31 foreground red" {
    const sem = process(makeStyleChange('m', 31, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 2), sem.style_fg_color);
}

test "semantic: SGR 37 foreground white" {
    const sem = process(makeStyleChange('m', 37, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 8), sem.style_fg_color);
}

test "semantic: SGR 39 foreground reset" {
    const sem = process(makeStyleChange('m', 39, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 0), sem.style_fg_color);
}

test "semantic: SGR 44 background blue" {
    const sem = process(makeStyleChange('m', 44, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 5), sem.style_bg_color);
}

test "semantic: SGR 49 background reset" {
    const sem = process(makeStyleChange('m', 49, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 0), sem.style_bg_color);
}

test "semantic: SGR unsupported param returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(makeStyleChange('m', 6, 0, 1)));
}

test "semantic: SGR 90 bright foreground black" {
    const sem = process(makeStyleChange('m', 90, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 9), sem.style_fg_color);
}

test "semantic: SGR 97 bright foreground white" {
    const sem = process(makeStyleChange('m', 97, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 16), sem.style_fg_color);
}

test "semantic: SGR 100 bright background black" {
    const sem = process(makeStyleChange('m', 100, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 9), sem.style_bg_color);
}

test "semantic: SGR 107 bright background white" {
    const sem = process(makeStyleChange('m', 107, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 16), sem.style_bg_color);
}

test "semantic: SGR 4 underline on" {
    const sem = process(makeStyleChange('m', 4, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_underline_on);
}

test "semantic: SGR 24 underline off" {
    const sem = process(makeStyleChange('m', 24, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_underline_off);
}

test "semantic: SGR 5 blink on" {
    const sem = process(makeStyleChange('m', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_blink_on);
}

test "semantic: SGR 25 blink off" {
    const sem = process(makeStyleChange('m', 25, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_blink_off);
}

test "semantic: SGR 8 conceal on" {
    const sem = process(makeStyleChange('m', 8, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_conceal_on);
}

test "semantic: SGR 28 conceal off" {
    const sem = process(makeStyleChange('m', 28, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_conceal_off);
}

test "semantic: SGR 7 inverse on" {
    const sem = process(makeStyleChange('m', 7, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_inverse_on);
}

test "semantic: SGR 27 inverse off" {
    const sem = process(makeStyleChange('m', 27, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_inverse_off);
}

test "semantic: multi-param SGR 1;31 bold and red" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 1;
    params[1] = 31;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 2 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .bold_on);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.ops[1].fg_color);
}

test "semantic: multi-param SGR 0;44 reset and bg blue" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 0;
    params[1] = 44;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 2 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .reset);
    try std.testing.expectEqual(@as(u8, 5), sem.style_operations.ops[1].bg_color);
}

test "semantic: multi-param SGR with unsupported params skips them" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 1;
    params[1] = 6;
    params[2] = 31;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .bold_on);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.ops[1].fg_color);
}

test "semantic: multi-param SGR blink + fg + inverse preserves order" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 5;
    params[1] = 31;
    params[2] = 7;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 3), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .blink_on);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.ops[1].fg_color);
    try std.testing.expect(sem.style_operations.ops[2] == .inverse_on);
}

test "semantic: multi-param SGR conceal + color + reveal preserves order" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 8;
    params[1] = 31;
    params[2] = 28;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 3), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .conceal_on);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.ops[1].fg_color);
    try std.testing.expect(sem.style_operations.ops[2] == .conceal_off);
}

test "semantic: SGR no params defaults to reset" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 0 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_reset);
}

test "semantic: SGR 38;5;<n> foreground 256-color" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 38;
    params[1] = 5;
    params[2] = 196;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_fg_256);
    try std.testing.expectEqual(@as(u8, 196), sem.style_fg_256);
}

test "semantic: SGR 48;5;<n> background 256-color" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 48;
    params[1] = 5;
    params[2] = 21;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_bg_256);
    try std.testing.expectEqual(@as(u8, 21), sem.style_bg_256);
}

test "semantic: multi-param SGR 1;38;5;196 bold and fg 256" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 1;
    params[1] = 38;
    params[2] = 5;
    params[3] = 196;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 4 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .bold_on);
    try std.testing.expectEqual(@as(u8, 196), sem.style_operations.ops[1].fg_256);
}

test "semantic: malformed 256-color sequence (38;2) ignored safely" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 38;
    params[1] = 2;
    params[2] = 255;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } });
    try std.testing.expectEqual(@as(?SemanticEvent, null), sem);
}

test "semantic: SGR 38;2;r;g;b foreground RGB" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 38;
    params[1] = 2;
    params[2] = 255;
    params[3] = 0;
    params[4] = 0;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 5 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_fg_rgb);
    try std.testing.expectEqual(@as(u8, 255), sem.style_fg_rgb.r);
    try std.testing.expectEqual(@as(u8, 0), sem.style_fg_rgb.g);
    try std.testing.expectEqual(@as(u8, 0), sem.style_fg_rgb.b);
}

test "semantic: SGR 48;2;r;g;b background RGB" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 48;
    params[1] = 2;
    params[2] = 0;
    params[3] = 255;
    params[4] = 0;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 5 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_bg_rgb);
    try std.testing.expectEqual(@as(u8, 0), sem.style_bg_rgb.r);
    try std.testing.expectEqual(@as(u8, 255), sem.style_bg_rgb.g);
    try std.testing.expectEqual(@as(u8, 0), sem.style_bg_rgb.b);
}

test "semantic: SGR 58;5;<n> underline 256-color" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 58;
    params[1] = 5;
    params[2] = 201;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_underline_color_256);
    try std.testing.expectEqual(@as(u8, 201), sem.style_underline_color_256);
}

test "semantic: SGR 58;2;r;g;b underline RGB" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 58;
    params[1] = 2;
    params[2] = 12;
    params[3] = 34;
    params[4] = 56;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 5 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_underline_color_rgb);
    try std.testing.expectEqual(@as(u8, 12), sem.style_underline_color_rgb.r);
    try std.testing.expectEqual(@as(u8, 34), sem.style_underline_color_rgb.g);
    try std.testing.expectEqual(@as(u8, 56), sem.style_underline_color_rgb.b);
}

test "semantic: SGR 59 reset underline color" {
    const sem = process(makeStyleChange('m', 59, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_underline_color_reset);
}

test "semantic: malformed underline color sequence (58;2) ignored safely" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 58;
    params[1] = 2;
    params[2] = 255;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 3 } });
    try std.testing.expectEqual(@as(?SemanticEvent, null), sem);
}

test "semantic: RGB values clamped to 0-255" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 38;
    params[1] = 2;
    params[2] = 300;
    params[3] = -5;
    params[4] = 128;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 5 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_fg_rgb);
    try std.testing.expectEqual(@as(u8, 255), sem.style_fg_rgb.r);
    try std.testing.expectEqual(@as(u8, 0), sem.style_fg_rgb.g);
    try std.testing.expectEqual(@as(u8, 128), sem.style_fg_rgb.b);
}

test "semantic: multi-param SGR 1;38;2;255;128;0 bold and fg RGB" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 1;
    params[1] = 38;
    params[2] = 2;
    params[3] = 255;
    params[4] = 128;
    params[5] = 0;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 6 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .bold_on);
    try std.testing.expectEqual(@as(u8, 255), sem.style_operations.ops[1].fg_rgb.r);
    try std.testing.expectEqual(@as(u8, 128), sem.style_operations.ops[1].fg_rgb.g);
    try std.testing.expectEqual(@as(u8, 0), sem.style_operations.ops[1].fg_rgb.b);
}

test "semantic: multi-param SGR 4;58;5;33;59 preserves order" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    params[0] = 4;
    params[1] = 58;
    params[2] = 5;
    params[3] = 33;
    params[4] = 59;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 5 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 3), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .underline_on);
    try std.testing.expectEqual(@as(u8, 33), sem.style_operations.ops[1].underline_color_256);
    try std.testing.expect(sem.style_operations.ops[2] == .underline_color_reset);
}

test "semantic: SGR parameter count above internal params is truncated deterministically" {
    var params: [16]i32 = undefined;
    @memset(&params, 6);
    params[0] = 1;
    params[1] = 31;
    params[2] = 4;
    params[3] = 58;
    params[4] = 5;
    params[5] = 200;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 250 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 4), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .bold_on);
    try std.testing.expectEqual(@as(u8, 2), sem.style_operations.ops[1].fg_color);
    try std.testing.expect(sem.style_operations.ops[2] == .underline_on);
    try std.testing.expectEqual(@as(u8, 200), sem.style_operations.ops[3].underline_color_256);
}

test "semantic: repeated SGR 22 is truncated at op cap without overflow" {
    var params: [16]i32 = undefined;
    for (0..params.len) |idx| params[idx] = 22;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 16 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 16), sem.style_operations.count);
    try std.testing.expect(sem.style_operations.ops[0] == .bold_off);
    try std.testing.expect(sem.style_operations.ops[1] == .dim_off);
    try std.testing.expect(sem.style_operations.ops[14] == .bold_off);
    try std.testing.expect(sem.style_operations.ops[15] == .dim_off);
}

test "semantic: extended form near op cap truncates deterministically" {
    var params: [16]i32 = undefined;
    @memset(&params, 0);
    for (0..15) |idx| params[idx] = 1;
    params[15] = 38;
    const sem = process(Event{ .style_change = .{ .final = 'm', .params = params, .param_count = 16 } }) orelse return error.NoEvent;
    try std.testing.expect(sem == .style_operations);
    try std.testing.expectEqual(@as(u8, 15), sem.style_operations.count);
    for (0..15) |idx| {
        try std.testing.expect(sem.style_operations.ops[idx] == .bold_on);
    }
}
