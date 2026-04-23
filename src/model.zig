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
/// Shift modifier bit re-export.
pub const VTERM_MOD_SHIFT = types.VTERM_MOD_SHIFT;
/// Alt modifier bit re-export.
pub const VTERM_MOD_ALT = types.VTERM_MOD_ALT;
/// Ctrl modifier bit re-export.
pub const VTERM_MOD_CTRL = types.VTERM_MOD_CTRL;
/// Key constants re-export.
pub const VTERM_KEY_NONE = types.VTERM_KEY_NONE;
/// Enter key identifier re-export.
pub const VTERM_KEY_ENTER = types.VTERM_KEY_ENTER;
/// Tab key identifier re-export.
pub const VTERM_KEY_TAB = types.VTERM_KEY_TAB;
/// Backspace key identifier re-export.
pub const VTERM_KEY_BACKSPACE = types.VTERM_KEY_BACKSPACE;
/// Escape key identifier re-export.
pub const VTERM_KEY_ESCAPE = types.VTERM_KEY_ESCAPE;
/// Up-arrow key identifier re-export.
pub const VTERM_KEY_UP = types.VTERM_KEY_UP;
/// Down-arrow key identifier re-export.
pub const VTERM_KEY_DOWN = types.VTERM_KEY_DOWN;
/// Left-arrow key identifier re-export.
pub const VTERM_KEY_LEFT = types.VTERM_KEY_LEFT;
/// Right-arrow key identifier re-export.
pub const VTERM_KEY_RIGHT = types.VTERM_KEY_RIGHT;
/// Insert key identifier re-export.
pub const VTERM_KEY_INS = types.VTERM_KEY_INS;
/// Delete key identifier re-export.
pub const VTERM_KEY_DEL = types.VTERM_KEY_DEL;
/// Home key identifier re-export.
pub const VTERM_KEY_HOME = types.VTERM_KEY_HOME;
/// End key identifier re-export.
pub const VTERM_KEY_END = types.VTERM_KEY_END;
/// Page-up key identifier re-export.
pub const VTERM_KEY_PAGEUP = types.VTERM_KEY_PAGEUP;
/// Page-down key identifier re-export.
pub const VTERM_KEY_PAGEDOWN = types.VTERM_KEY_PAGEDOWN;
/// Function key F1 identifier re-export.
pub const VTERM_KEY_F1 = types.VTERM_KEY_F1;
/// Function key F2 identifier re-export.
pub const VTERM_KEY_F2 = types.VTERM_KEY_F2;
/// Function key F3 identifier re-export.
pub const VTERM_KEY_F3 = types.VTERM_KEY_F3;
/// Function key F4 identifier re-export.
pub const VTERM_KEY_F4 = types.VTERM_KEY_F4;
/// Function key F5 identifier re-export.
pub const VTERM_KEY_F5 = types.VTERM_KEY_F5;
/// Function key F6 identifier re-export.
pub const VTERM_KEY_F6 = types.VTERM_KEY_F6;
/// Function key F7 identifier re-export.
pub const VTERM_KEY_F7 = types.VTERM_KEY_F7;
/// Function key F8 identifier re-export.
pub const VTERM_KEY_F8 = types.VTERM_KEY_F8;
/// Function key F9 identifier re-export.
pub const VTERM_KEY_F9 = types.VTERM_KEY_F9;
/// Function key F10 identifier re-export.
pub const VTERM_KEY_F10 = types.VTERM_KEY_F10;
/// Function key F11 identifier re-export.
pub const VTERM_KEY_F11 = types.VTERM_KEY_F11;
/// Function key F12 identifier re-export.
pub const VTERM_KEY_F12 = types.VTERM_KEY_F12;

/// Selection state API re-export.
pub const SelectionState = selection.SelectionState;
/// Metrics API re-export.
pub const Metrics = metrics.Metrics;
