//! Responsibility: export the selection domain object surface.
//! Ownership: selection package boundary.
//! Reason: keep one canonical owner for selection state and data shapes.

const model = @import("selection/model.zig");

pub const Selection = struct {
    pub const SelectionPos = model.SelectionPos;
    pub const TerminalSelection = model.TerminalSelection;
    pub const SelectionState = model.SelectionState;
};
