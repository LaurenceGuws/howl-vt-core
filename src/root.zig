//! Responsibility: expose the package public module surface.
//! Ownership: root API export boundary.
//! Reason: provide stable import paths for parser/runtime/model lanes.

const std = @import("std");

/// Parser module export.
pub const parser = @import("parser/parser.zig");

/// Event pipeline module export.
pub const pipeline = @import("event/pipeline.zig");

/// Semantic mapping module export.
pub const semantic = @import("event/semantic.zig");

/// Screen state module export.
pub const screen = @import("screen/state.zig");

/// Shared model module export.
pub const model = @import("model.zig");

/// Runtime engine module export.
pub const runtime = @import("runtime/engine.zig");

comptime {
    _ = @import("test/relay.zig");
    _ = @import("test/api_api.zig");
}

test "root: exposes host-neutral module surface" {
    try std.testing.expect(@hasDecl(@This(), "parser"));
    try std.testing.expect(@hasDecl(@This(), "pipeline"));
    try std.testing.expect(@hasDecl(@This(), "semantic"));
    try std.testing.expect(@hasDecl(@This(), "screen"));
    try std.testing.expect(@hasDecl(@This(), "model"));
    try std.testing.expect(@hasDecl(@This(), "runtime"));
}
