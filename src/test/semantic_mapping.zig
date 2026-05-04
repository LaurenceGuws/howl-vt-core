//! Responsibility: mapping coverage from bridge events to semantic events.
//! Ownership: parser-to-semantic translation correctness tests.
//! Reason: make translation defaults, aliases, and private modes explicit.

const std = @import("std");
const interpret_owner = @import("../interpret.zig");

const Interpret = interpret_owner.Interpret;
const Event = Interpret.Event;
const SemanticEvent = Interpret.SemanticEvent;
const process = Interpret.process;
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

test "semantic: CUD alias 'e'" {
    const sem = process(makeStyleChange('e', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 5), sem.cursor_down);
}

test "semantic: CUD alias 'e' zero param defaults to 1" {
    const sem = process(makeStyleChange('e', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_down);
}

test "semantic: CUF" {
    const sem = process(makeStyleChange('C', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_forward);
}

test "semantic: CUF alias 'a'" {
    const sem = process(makeStyleChange('a', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_forward);
}

test "semantic: CUF alias 'a' zero param defaults to 1" {
    const sem = process(makeStyleChange('a', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_forward);
}

test "semantic: CUB" {
    const sem = process(makeStyleChange('D', 4, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), sem.cursor_back);
}

test "semantic: CNL explicit count" {
    const sem = process(makeStyleChange('E', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.cursor_next_line);
}

test "semantic: CNL zero param defaults to 1" {
    const sem = process(makeStyleChange('E', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_next_line);
}

test "semantic: CPL explicit count" {
    const sem = process(makeStyleChange('F', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_prev_line);
}

test "semantic: CPL zero param defaults to 1" {
    const sem = process(makeStyleChange('F', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_prev_line);
}

test "semantic: CHA explicit column" {
    const sem = process(makeStyleChange('G', 7, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 6), sem.cursor_horizontal_absolute);
}

test "semantic: CHA zero param defaults to column 0" {
    const sem = process(makeStyleChange('G', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_horizontal_absolute);
}

test "semantic: CHA alias backtick explicit column" {
    const sem = process(makeStyleChange('`', 7, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 6), sem.cursor_horizontal_absolute);
}

test "semantic: CHA alias backtick zero param defaults to column 0" {
    const sem = process(makeStyleChange('`', 0, 0, 1)) orelse return error.NoEvent;
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

test "semantic: IL explicit count" {
    const sem = process(makeStyleChange('L', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.insert_lines);
}

test "semantic: DL defaults to one line" {
    const sem = process(makeStyleChange('M', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.delete_lines);
}

test "semantic: SU explicit count" {
    const sem = process(makeStyleChange('S', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.scroll_up_lines);
}

test "semantic: SD defaults to one line" {
    const sem = process(makeStyleChange('T', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.scroll_down_lines);
}

test "semantic: DECSTBM captures top and bottom margins" {
    const sem = process(makeStyleChange('r', 2, 5, 2)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.set_scroll_region.top);
    try std.testing.expectEqual(@as(?u16, 4), sem.set_scroll_region.bottom);
}

test "semantic: DECSTBM with omitted bottom resets to viewport bottom" {
    const sem = process(makeStyleChange('r', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.set_scroll_region.top);
    try std.testing.expectEqual(@as(?u16, null), sem.set_scroll_region.bottom);
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
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(makeStyleChange('x', 1, 0, 1)));
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

test "semantic: DEC private origin mode enable maps true" {
    var params = [_]i32{0} ** 16;
    params[0] = 6;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.origin_mode);
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

test "semantic: OSC title transport returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .osc = .{
        .kind = .title,
        .command = @as(?u16, 0),
        .payload = "My Title",
        .terminator = .bel,
    } }));
}

test "semantic: OSC 8 maps to hyperlink set and clear" {
    try std.testing.expectEqualStrings("https://example.com", process(Event{ .osc = .{
        .kind = .hyperlink,
        .command = @as(?u16, 8),
        .payload = ";https://example.com",
        .terminator = .bel,
    } }).?.hyperlink_set);
    try std.testing.expect(process(Event{ .osc = .{
        .kind = .hyperlink,
        .command = @as(?u16, 8),
        .payload = ";",
        .terminator = .bel,
    } }).? == .hyperlink_clear);
}

test "semantic: OSC 52 maps to clipboard set" {
    try std.testing.expectEqualStrings("c;Zm9v", process(Event{ .osc = .{
        .kind = .clipboard,
        .command = @as(?u16, 52),
        .payload = "c;Zm9v",
        .terminator = .bel,
    } }).?.clipboard_set);
}

test "semantic: APC DCS and ESC transport return null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .apc = "kitty" }));
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .dcs = "data" }));
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .esc_final = 'M' }));
}

test "semantic: DEC save and restore cursor from ESC finals" {
    try std.testing.expect(process(Event{ .esc_final = '7' }).? == .save_cursor);
    try std.testing.expect(process(Event{ .esc_final = '8' }).? == .restore_cursor);
}

test "semantic: DEC private application cursor enable maps true" {
    var params = [_]i32{0} ** 16;
    params[0] = 1;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.application_cursor_keys);
}

test "semantic: DEC private focus reporting enable maps true" {
    var params = [_]i32{0} ** 16;
    params[0] = 1004;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.focus_reporting);
}

test "semantic: DEC private bracketed paste disable maps false" {
    var params = [_]i32{0} ** 16;
    params[0] = 2004;
    const ev = Event{ .style_change = .{
        .final = 'l',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(!process(ev).?.bracketed_paste);
}

test "semantic: DEC private mouse tracking mode mappings" {
    var params = [_]i32{0} ** 16;
    params[0] = 1000;
    var ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).? == .mouse_tracking_x10);
    params[0] = 1002;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).? == .mouse_tracking_button_event);
    params[0] = 1003;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).? == .mouse_tracking_any_event);
    params[0] = 1006;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).?.mouse_protocol_sgr);
}

test "semantic: DSR 5 maps to device status report" {
    const sem = process(makeStyleChange('n', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .device_status_report);
}

test "semantic: DSR 6 maps to cursor position report" {
    const sem = process(makeStyleChange('n', 6, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_position_report);
}

test "semantic: DA maps to primary device attributes" {
    const sem = process(makeStyleChange('c', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expect(sem == .primary_device_attributes);
}

test "semantic: DA2 maps to secondary device attributes" {
    const params = [_]i32{0} ** 16;
    const ev = Event{ .style_change = .{
        .final = 'c',
        .params = params,
        .param_count = 0,
        .leader = '>',
        .private = false,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).? == .secondary_device_attributes);
}

test "semantic: DECRQM maps to dec mode query" {
    var params = [_]i32{0} ** 16;
    params[0] = 1004;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '$';
    const ev = Event{ .style_change = .{
        .final = 'p',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } };
    try std.testing.expectEqual(@as(u16, 1004), process(ev).?.dec_mode_query);
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
