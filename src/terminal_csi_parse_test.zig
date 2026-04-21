//! HT-004: First proof test - CSI parser tokenization.
//! Demonstrates that core parser primitives work: feed bytes, parse sequences, capture params.

const std = @import("std");
const parser_mod = @import("terminal/parser.zig");
const csi = parser_mod.csi;
const utf8 = parser_mod.utf8;
const stream = parser_mod.stream;

test "CSI parser: basic ANSI color sequence (31m = red)" {
    var parser = csi.CsiParser{};
    var action: ?csi.CsiAction = null;

    for ("31m") |byte| {
        action = parser.feed(byte);
    }

    try std.testing.expectEqual(@as(u8, 'm'), action.?.final);
    try std.testing.expectEqual(@as(i32, 31), action.?.params[0]);
    try std.testing.expectEqual(@as(u8, 1), action.?.count);
}

test "CSI parser: multi-param sequence (1;31;40m = bold red on black)" {
    var parser = csi.CsiParser{};
    var action: ?csi.CsiAction = null;

    for ("1;31;40m") |byte| {
        action = parser.feed(byte);
    }

    try std.testing.expectEqual(@as(u8, 'm'), action.?.final);
    try std.testing.expectEqual(@as(i32, 1), action.?.params[0]);
    try std.testing.expectEqual(@as(i32, 31), action.?.params[1]);
    try std.testing.expectEqual(@as(i32, 40), action.?.params[2]);
    try std.testing.expectEqual(@as(u8, 3), action.?.count);
}

test "CSI parser: cursor position query (6n)" {
    var parser = csi.CsiParser{};
    var action: ?csi.CsiAction = null;

    for ("6n") |byte| {
        action = parser.feed(byte);
    }

    try std.testing.expectEqual(@as(u8, 'n'), action.?.final);
}

test "CSI parser: private mode (DEC) (?25h = show cursor)" {
    var parser = csi.CsiParser{};
    var action: ?csi.CsiAction = null;

    for ("?25h") |byte| {
        action = parser.feed(byte);
    }

    try std.testing.expectEqual(@as(u8, 'h'), action.?.final);
    try std.testing.expect(action.?.private);
    try std.testing.expectEqual(@as(u8, '?'), action.?.leader);
    try std.testing.expectEqual(@as(i32, 25), action.?.params[0]);
}

test "UTF8 decoder: ASCII passthrough" {
    var decoder = utf8.Utf8Decoder{};
    const result = decoder.feed('A');
    try std.testing.expectEqual(@as(u21, 'A'), result.codepoint);
}

test "UTF8 decoder: multi-byte UTF-8 sequence (€ = U+20AC)" {
    var decoder = utf8.Utf8Decoder{};

    var result = decoder.feed(0xE2); // First byte of 3-byte sequence
    try std.testing.expect(result == .incomplete);

    result = decoder.feed(0x82); // Second byte
    try std.testing.expect(result == .incomplete);

    result = decoder.feed(0xAC); // Third byte
    try std.testing.expectEqual(@as(u21, 0x20AC), result.codepoint);
}

test "Stream event: control vs codepoint distinction" {
    var str = stream.Stream{};

    const event_ctrl = str.feed(0x07); // BEL control
    try std.testing.expect(event_ctrl.?.control == 0x07);

    str.reset();
    const event_text = str.feed('X'); // Regular character
    try std.testing.expect(event_text.?.codepoint == 'X');
}
