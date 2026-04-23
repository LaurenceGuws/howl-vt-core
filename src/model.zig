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
/// Logical key identifier re-export.
pub const Key = types.Key;
/// Modifier flags re-export.
pub const Modifier = types.Modifier;
/// Physical key identifier re-export.
pub const PhysicalKey = types.PhysicalKey;
/// Keyboard metadata re-export.
pub const KeyboardAlternateMetadata = types.KeyboardAlternateMetadata;
/// Mouse button enum re-export.
pub const MouseButton = types.MouseButton;
/// Mouse event kind enum re-export.
pub const MouseEventKind = types.MouseEventKind;
/// Mouse event struct re-export.
pub const MouseEvent = types.MouseEvent;
/// Modifier constants re-export.
pub const VTERM_MOD_NONE = types.VTERM_MOD_NONE;
pub const VTERM_MOD_SHIFT = types.VTERM_MOD_SHIFT;
pub const VTERM_MOD_ALT = types.VTERM_MOD_ALT;
pub const VTERM_MOD_CTRL = types.VTERM_MOD_CTRL;
/// Key constants re-export.
pub const VTERM_KEY_NONE = types.VTERM_KEY_NONE;
pub const VTERM_KEY_ENTER = types.VTERM_KEY_ENTER;
pub const VTERM_KEY_TAB = types.VTERM_KEY_TAB;
pub const VTERM_KEY_BACKSPACE = types.VTERM_KEY_BACKSPACE;
pub const VTERM_KEY_ESCAPE = types.VTERM_KEY_ESCAPE;
pub const VTERM_KEY_UP = types.VTERM_KEY_UP;
pub const VTERM_KEY_DOWN = types.VTERM_KEY_DOWN;
pub const VTERM_KEY_LEFT = types.VTERM_KEY_LEFT;
pub const VTERM_KEY_RIGHT = types.VTERM_KEY_RIGHT;

/// Selection state API re-export.
pub const SelectionState = selection.SelectionState;
/// Metrics API re-export.
pub const Metrics = metrics.Metrics;
