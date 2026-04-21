const std = @import("std");
const consumer = @import("terminal/parser_core_semantic_consumer.zig");

const CoreEvent = consumer.CoreEvent;
const SemanticEvent = consumer.SemanticEvent;

fn makeStyleChange(final: u8, p0: i32, p1: i32, count: u8) CoreEvent {
    var params = [_]i32{0} ** 16;
    params[0] = p0;
    params[1] = p1;
    return CoreEvent{ .style_change = .{ .final = final, .params = params, .param_count = count } };
}

test "semantic_consumer: CUU explicit count" {
    const ev = makeStyleChange('A', 3, 0, 1);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_up);
    try std.testing.expectEqual(@as(u16, 3), sem.cursor_up);
}

test "semantic_consumer: CUU zero param defaults to 1" {
    const ev = makeStyleChange('A', 0, 0, 1);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_up);
}

test "semantic_consumer: CUU no params defaults to 1" {
    const ev = makeStyleChange('A', 0, 0, 0);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_up);
}

test "semantic_consumer: CUD" {
    const ev = makeStyleChange('B', 5, 0, 1);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_down);
    try std.testing.expectEqual(@as(u16, 5), sem.cursor_down);
}

test "semantic_consumer: CUF" {
    const ev = makeStyleChange('C', 2, 0, 1);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_forward);
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_forward);
}

test "semantic_consumer: CUB" {
    const ev = makeStyleChange('D', 4, 0, 1);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_back);
    try std.testing.expectEqual(@as(u16, 4), sem.cursor_back);
}

test "semantic_consumer: CUP explicit row and col" {
    // count=1 means two params were parsed (0-indexed last param index)
    const ev = makeStyleChange('H', 3, 5, 1);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_position);
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 4), sem.cursor_position.col);
}

test "semantic_consumer: CUP no params defaults to origin" {
    // count=0, params[0]=0 (no param given)
    const ev = makeStyleChange('H', 0, 0, 0);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_position.col);
}

test "semantic_consumer: CUP one param defaults col to 0" {
    // count=0, params[0]=4 (one param, no separator seen)
    const ev = makeStyleChange('H', 4, 0, 0);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_position.col);
}

test "semantic_consumer: CUP via f final" {
    // count=1 means two params (2;3 → row=2, col=3 → 0-based: 1,2)
    const ev = makeStyleChange('f', 2, 3, 1);
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_position);
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_position.col);
}

test "semantic_consumer: non-cursor CSI returns null" {
    const ev = makeStyleChange('m', 1, 0, 1);
    try std.testing.expectEqual(@as(?SemanticEvent, null), consumer.process(ev));
}

test "semantic_consumer: control event returns null" {
    const ev = CoreEvent{ .control = 0x07 };
    try std.testing.expectEqual(@as(?SemanticEvent, null), consumer.process(ev));
}

test "semantic_consumer: invalid_sequence returns null" {
    const ev = CoreEvent.invalid_sequence;
    try std.testing.expectEqual(@as(?SemanticEvent, null), consumer.process(ev));
}

test "semantic_consumer: text event maps to write_text" {
    const ev = CoreEvent{ .text = "hello" };
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .write_text);
    try std.testing.expectEqualSlices(u8, "hello", sem.write_text);
}

test "semantic_consumer: codepoint event maps to write_codepoint" {
    const ev = CoreEvent{ .codepoint = 0xE9 };
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .write_codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), sem.write_codepoint);
}

test "semantic_consumer: LF maps to line_feed" {
    const ev = CoreEvent{ .control = 0x0A };
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .line_feed);
}

test "semantic_consumer: CR maps to carriage_return" {
    const ev = CoreEvent{ .control = 0x0D };
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .carriage_return);
}

test "semantic_consumer: BS maps to backspace" {
    const ev = CoreEvent{ .control = 0x08 };
    const sem = consumer.process(ev) orelse return error.NoEvent;
    try std.testing.expect(sem == .backspace);
}

test "semantic_consumer: unsupported control returns null" {
    const ev = CoreEvent{ .control = 0x01 };
    try std.testing.expectEqual(@as(?SemanticEvent, null), consumer.process(ev));
}

test "semantic_consumer: title_set returns null" {
    const ev = CoreEvent{ .title_set = "My Title" };
    try std.testing.expectEqual(@as(?SemanticEvent, null), consumer.process(ev));
}
