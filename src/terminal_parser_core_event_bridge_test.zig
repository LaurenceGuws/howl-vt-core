const std = @import("std");
const parser_mod = @import("terminal/parser.zig");
const bridge_mod = @import("terminal/parser_core_event_bridge.zig");

test "parser_core_event_bridge: text" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("hello");

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", bridge.events.items[0].text);
}

test "parser_core_event_bridge: codepoint" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("\xC3\xA9");

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), bridge.events.items[0].codepoint);
}

test "parser_core_event_bridge: control" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleByte(0x07);

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .control);
    try std.testing.expectEqual(@as(u8, 0x07), bridge.events.items[0].control);
}

test "parser_core_event_bridge: style_change" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b[31m");

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(u8, 'm'), bridge.events.items[0].style_change.final);
    try std.testing.expectEqual(@as(i32, 31), bridge.events.items[0].style_change.params[0]);
}

test "parser_core_event_bridge: title_set" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b]My Window\x07");

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .title_set);
    try std.testing.expectEqualSlices(u8, "My Window", bridge.events.items[0].title_set);
}

test "parser_core_event_bridge: mixed" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("text\x1b[1m");

    try std.testing.expectEqual(@as(usize, 2), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .text);
    try std.testing.expect(bridge.events.items[1] == .style_change);
}

test "parser_core_event_bridge: multi_param" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b[1;31;40m");

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(i32, 1), bridge.events.items[0].style_change.params[0]);
    try std.testing.expectEqual(@as(i32, 31), bridge.events.items[0].style_change.params[1]);
    try std.testing.expectEqual(@as(i32, 40), bridge.events.items[0].style_change.params[2]);
}

test "parser_core_event_bridge: osc_non_title_payload_maps_to_title_set" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    // OSC hyperlink command (8;;url) — bridge does not parse command prefix
    parser.handleSlice("\x1b]8;;https://example.com\x07");

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .title_set);
    try std.testing.expectEqualSlices(u8, "8;;https://example.com", bridge.events.items[0].title_set);
}

test "parser_core_event_bridge: osc_terminator_ignored" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    // BEL-terminated and ST-terminated OSC both emit title_set
    parser.handleSlice("\x1b]label\x07");
    parser.handleSlice("\x1b]label\x1b\\");

    try std.testing.expectEqual(@as(usize, 2), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .title_set);
    try std.testing.expect(bridge.events.items[1] == .title_set);
    try std.testing.expectEqualSlices(u8, "label", bridge.events.items[0].title_set);
    try std.testing.expectEqualSlices(u8, "label", bridge.events.items[1].title_set);
}

test "parser_core_event_bridge: apc_produces_no_event" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b_kitty\x1b\\");

    try std.testing.expectEqual(@as(usize, 0), bridge.events.items.len);
}

test "parser_core_event_bridge: dcs_produces_no_event" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1bPdata\x1b\\");

    try std.testing.expectEqual(@as(usize, 0), bridge.events.items.len);
}

test "parser_core_event_bridge: invalid_sequence_propagated" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    // Lone continuation byte — invalid UTF-8
    parser.handleByte(0x80);

    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .invalid_sequence);
}

test "parser_core_event_bridge: payload_ownership_safe_after_continued_parse" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("abc");
    // Capture the pointer before feeding more input
    const first_ptr = bridge.events.items[0].text.ptr;

    // Feed more input; parser may reuse internal buffers
    parser.handleSlice("xyz");

    // First event payload must still be intact (bridge owns its copy)
    try std.testing.expectEqualSlices(u8, "abc", bridge.events.items[0].text);
    try std.testing.expectEqual(first_ptr, bridge.events.items[0].text.ptr);
    try std.testing.expectEqualSlices(u8, "xyz", bridge.events.items[1].text);
}

test "parser_core_event_bridge: len and isEmpty on empty queue" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    try std.testing.expectEqual(@as(usize, 0), bridge.len());
    try std.testing.expect(bridge.isEmpty());
}

test "parser_core_event_bridge: len tracks event count" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("ab");
    try std.testing.expectEqual(@as(usize, 1), bridge.len());
    try std.testing.expect(!bridge.isEmpty());

    parser.handleSlice("\x1b[1m");
    try std.testing.expectEqual(@as(usize, 2), bridge.len());
}

test "parser_core_event_bridge: clear frees owned payloads and resets queue" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("hello");
    parser.handleSlice("\x1b]title\x07");
    try std.testing.expectEqual(@as(usize, 2), bridge.len());

    bridge.clear();

    try std.testing.expectEqual(@as(usize, 0), bridge.len());
    try std.testing.expect(bridge.isEmpty());

    // Feed again after clear; allocator detects double-free or leak if clear was wrong
    parser.handleSlice("world");
    try std.testing.expectEqual(@as(usize, 1), bridge.len());
}

test "parser_core_event_bridge: drainInto transfers FIFO order and clears bridge" {
    const gpa = std.testing.allocator;
    var bridge = bridge_mod.ParserCoreBridge.init(gpa);
    defer bridge.deinit();

    var parser = try parser_mod.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();

    parser.handleSlice("abc");
    parser.handleSlice("\x1b[31m");
    parser.handleByte(0x80);

    var dest = std.ArrayList(bridge_mod.CoreEvent){};
    defer {
        for (dest.items) |ev| {
            switch (ev) {
                .text, .title_set => |data| gpa.free(data),
                else => {},
            }
        }
        dest.deinit(gpa);
    }

    try bridge.drainInto(&dest, gpa);

    try std.testing.expectEqual(@as(usize, 0), bridge.len());
    try std.testing.expectEqual(@as(usize, 3), dest.items.len);
    try std.testing.expect(dest.items[0] == .text);
    try std.testing.expect(dest.items[1] == .style_change);
    try std.testing.expect(dest.items[2] == .invalid_sequence);
    try std.testing.expectEqualSlices(u8, "abc", dest.items[0].text);
}
