//! Responsibility: export the snapshot domain object surface.
//! Ownership: snapshot package boundary.
//! Reason: keep one canonical owner for observable-state capture types.

const model = @import("snapshot/model.zig");

pub const Snapshot = struct {
    pub const VtCoreSnapshot = model.VtCoreSnapshot;
};
