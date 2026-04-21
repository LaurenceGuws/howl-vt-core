//! Responsibility: provide local package smoke entrypoint.
//! Ownership: package executable stub.
//! Reason: keep a minimal runnable binary during module extraction phase.

const std = @import("std");
const terminal = @import("terminal");

pub fn main() !void {
    std.debug.print("Howl Terminal primitives loaded.\n", .{});
    _ = terminal;
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
