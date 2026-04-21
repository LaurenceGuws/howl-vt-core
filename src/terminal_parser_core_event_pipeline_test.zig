const std = @import("std");
const pipeline_mod = @import("terminal/parser_core_event_pipeline.zig");

test "pipeline: mixed text and CSI and text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("hello\x1b[1mworld");

    try std.testing.expectEqual(@as(usize, 3), pl.len());
    try std.testing.expect(pl.events()[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", pl.events()[0].text);
    try std.testing.expect(pl.events()[1] == .style_change);
    try std.testing.expectEqual(@as(u8, 'm'), pl.events()[1].style_change.final);
    try std.testing.expectEqual(@as(i32, 1), pl.events()[1].style_change.params[0]);
    try std.testing.expect(pl.events()[2] == .text);
    try std.testing.expectEqualSlices(u8, "world", pl.events()[2].text);
}

test "pipeline: UTF-8 codepoint and control byte" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("\xC3\xA9");
    pl.feedByte(0x07);

    try std.testing.expectEqual(@as(usize, 2), pl.len());
    try std.testing.expect(pl.events()[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), pl.events()[0].codepoint);
    try std.testing.expect(pl.events()[1] == .control);
    try std.testing.expectEqual(@as(u8, 0x07), pl.events()[1].control);
}

test "pipeline: OSC title payload" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("\x1b]My Title\x07");

    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .title_set);
    try std.testing.expectEqualSlices(u8, "My Title", pl.events()[0].title_set);
}

test "pipeline: reset clears events and parser state" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("abc\x1b[1m");
    try std.testing.expectEqual(@as(usize, 2), pl.len());

    pl.reset();

    try std.testing.expect(pl.isEmpty());

    // After reset, new input is processed fresh
    pl.feedSlice("xyz");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .text);
    try std.testing.expectEqualSlices(u8, "xyz", pl.events()[0].text);
}

test "pipeline: split input across multiple feedSlice calls" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("\x1b[");
    try std.testing.expectEqual(@as(usize, 0), pl.len());

    pl.feedSlice("3");
    try std.testing.expectEqual(@as(usize, 0), pl.len());

    pl.feedSlice("1m");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .style_change);
    try std.testing.expectEqual(@as(i32, 31), pl.events()[0].style_change.params[0]);
}

test "pipeline: invalid UTF-8 propagates as invalid_sequence" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedByte(0x80);

    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .invalid_sequence);
}

test "pipeline: FIFO event order under interleaved feeds" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("a");
    pl.feedSlice("b");
    pl.feedByte(0x07);
    pl.feedSlice("\x1b[0m");

    try std.testing.expectEqual(@as(usize, 4), pl.len());
    try std.testing.expect(pl.events()[0] == .text);
    try std.testing.expectEqualSlices(u8, "a", pl.events()[0].text);
    try std.testing.expect(pl.events()[1] == .text);
    try std.testing.expectEqualSlices(u8, "b", pl.events()[1].text);
    try std.testing.expect(pl.events()[2] == .control);
    try std.testing.expect(pl.events()[3] == .style_change);
}

test "pipeline: OSC split across feeds" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("\x1b]hello");
    try std.testing.expectEqual(@as(usize, 0), pl.len());

    pl.feedSlice(" world\x07");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .title_set);
    try std.testing.expectEqualSlices(u8, "hello world", pl.events()[0].title_set);
}

test "replay: stray ESC inside OSC payload is dropped; following byte joins payload" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    // ESC inside OSC: stray ESC dropped, following byte 't' appended
    pl.feedSlice("\x1b]ti\x1btle\x07");

    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .title_set);
    try std.testing.expectEqualSlices(u8, "title", pl.events()[0].title_set);
}

test "replay: invalid UTF-8 mid-stream propagated as invalid_sequence" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("a");
    pl.feedByte(0xFE);
    pl.feedSlice("b");

    try std.testing.expectEqual(@as(usize, 3), pl.len());
    try std.testing.expect(pl.events()[0] == .text);
    try std.testing.expect(pl.events()[1] == .invalid_sequence);
    try std.testing.expect(pl.events()[2] == .text);
}

test "replay: FIFO order preserved under multi-step split CSI and text" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("pre");
    pl.feedSlice("\x1b[");
    pl.feedSlice("1;32");
    pl.feedSlice("m");
    pl.feedSlice("post");

    try std.testing.expectEqual(@as(usize, 3), pl.len());
    try std.testing.expect(pl.events()[0] == .text);
    try std.testing.expectEqualSlices(u8, "pre", pl.events()[0].text);
    try std.testing.expect(pl.events()[1] == .style_change);
    try std.testing.expectEqual(@as(i32, 1), pl.events()[1].style_change.params[0]);
    try std.testing.expectEqual(@as(i32, 32), pl.events()[1].style_change.params[1]);
    try std.testing.expect(pl.events()[2] == .text);
    try std.testing.expectEqualSlices(u8, "post", pl.events()[2].text);
}

test "replay: reset mid-stream discards partial state and partial events" {
    const gpa = std.testing.allocator;
    var pl = try pipeline_mod.Pipeline.init(gpa);
    defer pl.deinit();

    pl.feedSlice("keep");
    pl.reset();
    pl.feedSlice("\x1b[");
    // Partial CSI — no event yet
    try std.testing.expectEqual(@as(usize, 0), pl.len());
    pl.feedSlice("2m");
    try std.testing.expectEqual(@as(usize, 1), pl.len());
    try std.testing.expect(pl.events()[0] == .style_change);
    try std.testing.expectEqual(@as(i32, 2), pl.events()[0].style_change.params[0]);
}
