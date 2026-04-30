//! Responsibility: expose the vt-core package public surface.
//! Ownership: root API export boundary.
//! Reason: keep one primary host-facing object.

/// Primary vt-core facade type.
pub const VtCore = @import("vt_core.zig").VtCore;

test {
    _ = @import("test/pipeline.zig");
    _ = @import("test/screen_state.zig");
    _ = @import("test/semantic.zig");
    _ = @import("test/snapshot.zig");
    _ = @import("test/vt_core.zig");
}
