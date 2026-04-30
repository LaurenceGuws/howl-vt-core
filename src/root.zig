//! Responsibility: expose the vt-core package public surface.
//! Ownership: root API export boundary.
//! Reason: keep one primary host-facing object.

const std = @import("std");

pub const VtCore = @import("vt_core.zig").VtCore;

comptime {
    _ = @import("test/vt_core.zig");
}

test "root: exposes vt core object" {
    try std.testing.expect(@hasDecl(@This(), "VtCore"));
}
