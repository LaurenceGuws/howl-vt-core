//! Responsibility: expose the vt-core package public surface.
//! Ownership: root API export boundary.
//! Reason: keep one primary host-facing object.

/// Primary vt-core facade type.
pub const VtCore = @import("vt_core.zig").VtCore;

test {
    _ = @import("test/pipeline_regression.zig");
    _ = @import("test/scrollback_regression.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/semantic_mapping.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/system_flows.zig");
}
