//! Responsibility: expose the public Howl Terminal module surface.
//! Ownership: package root API boundary.
//! Reason: provide stable imports for parser and model primitives.

pub const parser = @import("parser/parser.zig");
pub const model = @import("model.zig");
pub const pipeline = @import("event/pipeline.zig");
pub const semantic = @import("event/semantic.zig");
pub const screen = @import("screen/state.zig");

comptime {
    _ = @import("test/relay.zig");
}
