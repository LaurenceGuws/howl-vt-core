//! Responsibility: expose the public Howl Terminal module surface.
//! Ownership: package root API boundary.
//! Reason: provide stable imports for parser and model primitives.

/// Parser module exports for byte-stream decoding and escape parsing.
pub const parser = @import("parser/parser.zig");
/// Pipeline module export for parser-to-screen event flow orchestration.
pub const pipeline = @import("event/pipeline.zig");
/// Semantic module export for mapping parser events to screen operations.
pub const semantic = @import("event/semantic.zig");
/// Screen module export for cursor/cell state application.
pub const screen = @import("screen/state.zig");
/// Model module exports for shared terminal data types and state primitives.
pub const model = @import("model.zig");

comptime {
    _ = @import("test/relay.zig");
}
