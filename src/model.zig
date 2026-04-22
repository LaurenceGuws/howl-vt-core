//! Responsibility: expose terminal model primitives and shared types.
//! Ownership: terminal model module boundary.
//! Reason: provide a stable model API independent of parser internals.

/// Types submodule containing shared model value types.
pub const types = @import("model/types.zig");
/// Selection submodule containing selection lifecycle state.
pub const selection = @import("model/selection.zig");
/// Metrics submodule containing lightweight runtime counters/EMA state.
pub const metrics = @import("model/metrics.zig");

/// Cursor position type re-export.
pub const CursorPos = types.CursorPos;
/// Cursor shape enum re-export.
pub const CursorShape = types.CursorShape;
/// Cursor style struct re-export.
pub const CursorStyle = types.CursorStyle;
/// Cell struct re-export.
pub const Cell = types.Cell;
/// Cell attribute struct re-export.
pub const CellAttrs = types.CellAttrs;
/// Color struct re-export.
pub const Color = types.Color;
/// Selection position re-export.
pub const SelectionPos = types.SelectionPos;
/// Terminal selection struct re-export.
pub const TerminalSelection = types.TerminalSelection;

/// Selection state API re-export.
pub const SelectionState = selection.SelectionState;
/// Metrics API re-export.
pub const Metrics = metrics.Metrics;
