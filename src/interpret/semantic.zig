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
    origin_mode: bool,
    application_cursor_keys: bool,
    focus_reporting: bool,
    bracketed_paste: bool,
    mouse_tracking_off,
    mouse_tracking_x10,
    mouse_tracking_button_event,
    mouse_tracking_any_event,
    mouse_protocol_sgr: bool,
    hyperlink_set: []const u8,
    hyperlink_clear,
    clipboard_set: []const u8,
    dec_mode_query: u16,
    device_status_report,
    cursor_position_report,
    primary_device_attributes,
    secondary_device_attributes,
    sgr: struct {
        params: [16]i32,
        param_count: u8,
    },
    enter_alt_screen: struct { clear: bool, save_cursor: bool },
    exit_alt_screen: struct { restore_cursor: bool },
    save_cursor,
    restore_cursor,
    insert_lines: u16,
    delete_lines: u16,
    delete_chars: u16,
    scroll_up_lines: u16,
    scroll_down_lines: u16,
    set_scroll_region: struct {
        top: u16,
        bottom: ?u16,
    },
    reset_screen,
    erase_display: u2,
    erase_line: u2,
    erase_chars: u16,
};

/// Map bridge event to semantic event when supported.
pub fn process(event: Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| return processCsi(sc.final, sc.params, sc.param_count, sc.leader, sc.private, sc.intermediates, sc.intermediates_len),
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return processControl(c),
        .osc => |osc| return processOsc(osc.kind, osc.payload),
        .esc_final => |final| return processEscFinal(final),
        .apc, .dcs, .invalid_sequence => return null,
    }
}

fn processEscFinal(final: u8) ?SemanticEvent {
    return switch (final) {
        '7' => SemanticEvent.save_cursor,
        '8' => SemanticEvent.restore_cursor,
        else => null,
    };
}

fn processOsc(kind: bridge_mod.OscKind, payload: []const u8) ?SemanticEvent {
    return switch (kind) {
        .hyperlink => blk: {
            const separator = std.mem.indexOfScalar(u8, payload, ';') orelse break :blk null;
            const uri = payload[separator + 1 ..];
            if (uri.len == 0) break :blk SemanticEvent.hyperlink_clear;
            break :blk SemanticEvent{ .hyperlink_set = uri };
        },
        .clipboard => SemanticEvent{ .clipboard_set = payload },
        else => null,
    };
}

fn processCsi(final: u8, params: [16]i32, count: u8, leader: u8, private: bool, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (private) {
        if (leader == '?' and count >= 1) {
            if (final == 'p' and intermediatesLenHas(intermediates, intermediates_len, '$')) {
                return SemanticEvent{ .dec_mode_query = paramOrDefault0(params[0]) };
            }
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
                6 => switch (final) {
                    'h' => SemanticEvent{ .origin_mode = true },
                    'l' => SemanticEvent{ .origin_mode = false },
                    else => null,
                },
                1 => switch (final) {
                    'h' => SemanticEvent{ .application_cursor_keys = true },
                    'l' => SemanticEvent{ .application_cursor_keys = false },
                    else => null,
                },
                1004 => switch (final) {
                    'h' => SemanticEvent{ .focus_reporting = true },
                    'l' => SemanticEvent{ .focus_reporting = false },
                    else => null,
                },
                2004 => switch (final) {
                    'h' => SemanticEvent{ .bracketed_paste = true },
                    'l' => SemanticEvent{ .bracketed_paste = false },
                    else => null,
                },
                1000 => switch (final) {
                    'h' => SemanticEvent.mouse_tracking_x10,
                    'l' => SemanticEvent.mouse_tracking_off,
                    else => null,
                },
                1002 => switch (final) {
                    'h' => SemanticEvent.mouse_tracking_button_event,
                    'l' => SemanticEvent.mouse_tracking_off,
                    else => null,
                },
                1003 => switch (final) {
                    'h' => SemanticEvent.mouse_tracking_any_event,
                    'l' => SemanticEvent.mouse_tracking_off,
                    else => null,
                },
                1006 => switch (final) {
                    'h' => SemanticEvent{ .mouse_protocol_sgr = true },
                    'l' => SemanticEvent{ .mouse_protocol_sgr = false },
                    else => null,
                },
                47 => switch (final) {
                    'h' => SemanticEvent{ .enter_alt_screen = .{ .clear = false, .save_cursor = false } },
                    'l' => SemanticEvent{ .exit_alt_screen = .{ .restore_cursor = false } },
                    else => null,
                },
                1047 => switch (final) {
                    'h' => SemanticEvent{ .enter_alt_screen = .{ .clear = true, .save_cursor = false } },
                    'l' => SemanticEvent{ .exit_alt_screen = .{ .restore_cursor = false } },
                    else => null,
                },
                1049 => switch (final) {
                    'h' => SemanticEvent{ .enter_alt_screen = .{ .clear = true, .save_cursor = true } },
                    'l' => SemanticEvent{ .exit_alt_screen = .{ .restore_cursor = true } },
                    else => null,
                },
                else => null,
            };
        }
        return null;
    }
    if (leader == '>') {
        return switch (final) {
            'c' => SemanticEvent.secondary_device_attributes,
            else => null,
        };
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
        'L' => return SemanticEvent{ .insert_lines = paramOrDefault1(params[0]) },
        'M' => return SemanticEvent{ .delete_lines = paramOrDefault1(params[0]) },
        'P' => return SemanticEvent{ .delete_chars = paramOrDefault1(params[0]) },
        'S' => return SemanticEvent{ .scroll_up_lines = paramOrDefault1(params[0]) },
        'T' => return SemanticEvent{ .scroll_down_lines = paramOrDefault1(params[0]) },
        'm' => return SemanticEvent{ .sgr = .{ .params = params, .param_count = count } },
        'H', 'f' => {
            const row = paramOrDefault1(params[0]);
            const col = paramOrDefault1(if (count >= 1) params[1] else 0);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'r' => return SemanticEvent{ .set_scroll_region = .{
            .top = paramOrDefault1(params[0]) - 1,
            .bottom = if (count >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        } },
        'J' => return SemanticEvent{ .erase_display = eraseMode(params[0]) },
        'K' => return SemanticEvent{ .erase_line = eraseMode(params[0]) },
        'X' => return SemanticEvent{ .erase_chars = paramOrDefault1(params[0]) },
        'n' => switch (paramOrDefault0(params[0])) {
            5 => return SemanticEvent.device_status_report,
            6 => return SemanticEvent.cursor_position_report,
            else => return null,
        },
        'c' => return SemanticEvent.primary_device_attributes,
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
        3 => 3,
        else => 0,
    };
}

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn paramOrDefault0(v: i32) u16 {
    if (v <= 0) return 0;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn intermediatesLenHas(intermediates: [4]u8, len: u8, needle: u8) bool {
    var idx: usize = 0;
    while (idx < len) : (idx += 1) {
        if (intermediates[idx] == needle) return true;
    }
    return false;
}
