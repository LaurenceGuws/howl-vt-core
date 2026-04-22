//! Responsibility: expose terminal model primitives and shared types.
//! Ownership: terminal model module boundary.
//! Reason: provide a stable model API independent of parser internals.

pub const types = @import("model/types.zig");
pub const selection = @import("model/selection.zig");
pub const metrics = @import("model/metrics.zig");

pub const CursorPos = types.CursorPos;
pub const CursorShape = types.CursorShape;
pub const CursorStyle = types.CursorStyle;
pub const Cell = types.Cell;
pub const CellAttrs = types.CellAttrs;
pub const Color = types.Color;
pub const SelectionPos = types.SelectionPos;
pub const TerminalSelection = types.TerminalSelection;

pub const SelectionState = selection.SelectionState;
pub const Metrics = metrics.Metrics;
