//! Responsibility: map parser-level events into semantic screen operations.
//! Ownership: event semantic module.
//! Reason: keep CSI/control interpretation separate from parser tokenization.

const std = @import("std");
const bridge_mod = @import("bridge.zig");

/// Event type alias consumed by semantic mapping.
pub const Event = bridge_mod.Event;

/// Screen-oriented semantic operations derived from parser events.
pub const SemanticEvent = union(enum) {
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_back: u16,
    cursor_horizontal_absolute: u16,
    cursor_vertical_absolute: u16,
    cursor_position: struct { row: u16, col: u16 },
    write_text: []const u8,
    write_codepoint: u21,
    line_feed,
    carriage_return,
    backspace,
    horizontal_tab,
    horizontal_tab_forward: u16,
    horizontal_tab_back: u16,
    cursor_visible: bool,
    auto_wrap: bool,
    reset_screen,
    erase_display: u2,
    erase_line: u2,
};

/// Convert a parser event into a semantic screen operation when supported.
pub fn process(event: Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| return processCsi(sc.final, sc.params, sc.param_count, sc.leader, sc.private, sc.intermediates, sc.intermediates_len),
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return processControl(c),
        .title_set, .invalid_sequence => return null,
    }
}

fn processCsi(final: u8, params: [16]i32, count: u8, leader: u8, private: bool, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (private) {
        if (leader == '?' and count >= 1) {
            return switch (params[0]) {
                25 => switch (final) {
                    'h' => SemanticEvent{ .cursor_visible = true },
                    'l' => SemanticEvent{ .cursor_visible = false },
                    else => null,
                },
                7 => switch (final) {
                    'h' => SemanticEvent{ .auto_wrap = true },
                    'l' => SemanticEvent{ .auto_wrap = false },
                    else => null,
                },
                else => null,
            };
        }
        return null;
    }
    if (leader != 0) return null;
    switch (final) {
        'A' => return SemanticEvent{ .cursor_up = paramOrDefault1(params[0]) },
        'B' => return SemanticEvent{ .cursor_down = paramOrDefault1(params[0]) },
        'C' => return SemanticEvent{ .cursor_forward = paramOrDefault1(params[0]) },
        'D' => return SemanticEvent{ .cursor_back = paramOrDefault1(params[0]) },
        'G' => return SemanticEvent{ .cursor_horizontal_absolute = paramOrDefault1(params[0]) - 1 },
        'd' => return SemanticEvent{ .cursor_vertical_absolute = paramOrDefault1(params[0]) - 1 },
        'I' => return SemanticEvent{ .horizontal_tab_forward = paramOrDefault1(params[0]) },
        'Z' => return SemanticEvent{ .horizontal_tab_back = paramOrDefault1(params[0]) },
        'H', 'f' => {
            const row = paramOrDefault1(params[0]);
            const col = paramOrDefault1(if (count >= 1) params[1] else 0);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'J' => return SemanticEvent{ .erase_display = eraseMode(params[0]) },
        'K' => return SemanticEvent{ .erase_line = eraseMode(params[0]) },
        'p' => {
            if (count == 0 and intermediates_len == 1 and intermediates[0] == '!') {
                return SemanticEvent.reset_screen;
            }
            return null;
        },
        else => return null,
    }
}

fn processControl(c: u8) ?SemanticEvent {
    return switch (c) {
        0x0A => SemanticEvent.line_feed,
        0x0D => SemanticEvent.carriage_return,
        0x08 => SemanticEvent.backspace,
        0x09 => SemanticEvent.horizontal_tab,
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

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn makeStyleChange(final: u8, p0: i32, p1: i32, count: u8) Event {
    var params = [_]i32{0} ** 16;
    params[0] = p0;
    params[1] = p1;
    return Event{ .style_change = .{
        .final = final,
        .params = params,
        .param_count = count,
        .leader = 0,
        .private = false,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
}

fn makeStyleChangeWithIntermediate(final: u8, intermediate: u8) Event {
    const params = [_]i32{0} ** 16;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = intermediate;
    return Event{ .style_change = .{
        .final = final,
        .params = params,
        .param_count = 0,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } };
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

test "semantic: CHA explicit column" {
    const sem = process(makeStyleChange('G', 7, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 6), sem.cursor_horizontal_absolute);
}

test "semantic: CHA zero param defaults to column 0" {
    const sem = process(makeStyleChange('G', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_horizontal_absolute);
}

test "semantic: VPA explicit row" {
    const sem = process(makeStyleChange('d', 9, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 8), sem.cursor_vertical_absolute);
}

test "semantic: VPA zero param defaults to row 0" {
    const sem = process(makeStyleChange('d', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_vertical_absolute);
}

test "semantic: CHT explicit count" {
    const sem = process(makeStyleChange('I', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.horizontal_tab_forward);
}

test "semantic: CHT zero param defaults to 1" {
    const sem = process(makeStyleChange('I', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.horizontal_tab_forward);
}

test "semantic: CHT large param saturates to u16 max" {
    const sem = process(makeStyleChange('I', 999999, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(std.math.maxInt(u16), sem.horizontal_tab_forward);
}

test "semantic: CBT explicit count" {
    const sem = process(makeStyleChange('Z', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.horizontal_tab_back);
}

test "semantic: CBT zero param defaults to 1" {
    const sem = process(makeStyleChange('Z', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.horizontal_tab_back);
}

test "semantic: CBT large param saturates to u16 max" {
    const sem = process(makeStyleChange('Z', 999999, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(std.math.maxInt(u16), sem.horizontal_tab_back);
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

test "semantic: non-cursor CSI returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(makeStyleChange('m', 1, 0, 1)));
}

test "semantic: DECSTR maps to reset_screen" {
    const sem = process(makeStyleChangeWithIntermediate('p', '!')) orelse return error.NoEvent;
    try std.testing.expect(sem == .reset_screen);
}

test "semantic: DEC private cursor show maps to cursor_visible true" {
    var params = [_]i32{0} ** 16;
    params[0] = 25;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.cursor_visible);
}

test "semantic: DEC private cursor hide maps to cursor_visible false" {
    var params = [_]i32{0} ** 16;
    params[0] = 25;
    const ev = Event{ .style_change = .{
        .final = 'l',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(!process(ev).?.cursor_visible);
}

test "semantic: DEC private wrap enable maps to auto_wrap true" {
    var params = [_]i32{0} ** 16;
    params[0] = 7;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.auto_wrap);
}

test "semantic: DEC private wrap disable maps to auto_wrap false" {
    var params = [_]i32{0} ** 16;
    params[0] = 7;
    const ev = Event{ .style_change = .{
        .final = 'l',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(!process(ev).?.auto_wrap);
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

test "semantic: HT maps to horizontal_tab" {
    const sem = process(Event{ .control = 0x09 }) orelse return error.NoEvent;
    try std.testing.expect(sem == .horizontal_tab);
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
