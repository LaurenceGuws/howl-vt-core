//! Responsibility: export the grid domain object surface.
//! Ownership: grid package boundary.
//! Reason: keep one canonical owner for grid state and behavior.

const model = @import("grid/model.zig");

pub const Grid = struct {
    pub const GridModel = model.GridModel;
};
