//! Responsibility: export the interpret domain object surface.
//! Ownership: interpret package boundary.
//! Reason: keep one canonical owner for parser-to-grid translation flow.

const bridge = @import("interpret/bridge.zig");
const semantic = @import("interpret/semantic.zig");
const pipeline = @import("interpret/pipeline.zig");

pub const Interpret = struct {
    pub const Event = bridge.Event;
    pub const Bridge = bridge.Bridge;
    pub const SemanticEvent = semantic.SemanticEvent;
    pub const Pipeline = pipeline.Pipeline;

    pub const process = semantic.process;
};
