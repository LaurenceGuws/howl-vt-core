//! Responsibility: expose the public Howl Terminal module surface.
//! Ownership: package root API boundary.
//! Reason: provide stable imports for parser and model primitives.

pub const parser = @import("terminal/parser.zig");
pub const model = @import("terminal/model.zig");
pub const pipeline = @import("terminal/parser_core_event_pipeline.zig");
pub const semantic_consumer = @import("terminal/parser_core_semantic_consumer.zig");
pub const screen_state = @import("terminal/terminal_screen_state.zig");
