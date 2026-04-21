const std = @import("std");
const bridge_mod = @import("parser_core_event_bridge.zig");

pub const CoreEvent = bridge_mod.CoreEvent;

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
};

pub fn process(event: CoreEvent) ?SemanticEvent {
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

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}
