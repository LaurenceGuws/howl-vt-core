//! Responsibility: map parsed records into semantic grid operations.
//! Ownership: interpret translation layer.
//! Reason: separate escape parsing from grid behavior intent.

const std = @import("std");
const bridge_mod = @import("bridge.zig");

/// Bridge event alias for semantic mapping.
const Event = bridge_mod.Event;

/// Screen-directed semantic event union.
pub const SemanticEvent = union(enum) {
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_back: u16,
    cursor_next_line: u16,
    cursor_prev_line: u16,
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

/// Map bridge event to semantic event when supported.
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
        'B', 'e' => return SemanticEvent{ .cursor_down = paramOrDefault1(params[0]) },
        'C', 'a' => return SemanticEvent{ .cursor_forward = paramOrDefault1(params[0]) },
        'D' => return SemanticEvent{ .cursor_back = paramOrDefault1(params[0]) },
        'E' => return SemanticEvent{ .cursor_next_line = paramOrDefault1(params[0]) },
        'F' => return SemanticEvent{ .cursor_prev_line = paramOrDefault1(params[0]) },
        'G', '`' => return SemanticEvent{ .cursor_horizontal_absolute = paramOrDefault1(params[0]) - 1 },
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
