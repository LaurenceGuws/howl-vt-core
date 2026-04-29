//! Responsibility: expose terminal model primitives and re-exports.
//! Ownership: model API module boundary.
//! Reason: centralize shared types for and consumers.

/// Types submodule export.
pub const types = @import("model/types.zig");

/// Selection submodule export.
pub const selection = @import("model/selection.zig");

/// Metrics submodule export.
pub const metrics = @import("model/metrics.zig");

/// Snapshot submodule export.
pub const snapshot = @import("model/snapshot.zig");

/// Cursor position type re-export.
pub const CursorPos = types.CursorPos;

/// Cursor shape type re-export.
pub const CursorShape = types.CursorShape;

/// Cursor style type re-export.
pub const CursorStyle = types.CursorStyle;

/// Cell type re-export.
pub const Cell = types.Cell;

/// Cell attribute type re-export.
pub const CellAttrs = types.CellAttrs;

/// Color type re-export.
pub const Color = types.Color;

/// Selection position type re-export.
pub const SelectionPos = types.SelectionPos;

/// Terminal selection type re-export.
pub const TerminalSelection = types.TerminalSelection;

/// Logical key type re-export.
pub const Key = types.Key;

/// Modifier type re-export.
pub const Modifier = types.Modifier;

/// Physical key type re-export.
pub const PhysicalKey = types.PhysicalKey;

/// Alternate keyboard metadata re-export.
pub const KeyboardAlternateMetadata = types.KeyboardAlternateMetadata;

/// Mouse button enum re-export.
pub const MouseButton = types.MouseButton;

/// Mouse event kind enum re-export.
pub const MouseEventKind = types.MouseEventKind;

/// Mouse event type re-export.
pub const MouseEvent = types.MouseEvent;

/// No-modifier constant re-export.
pub const VTERM_MOD_NONE = types.VTERM_MOD_NONE;

/// Shift modifier constant re-export.
pub const VTERM_MOD_SHIFT = types.VTERM_MOD_SHIFT;

/// Alt modifier constant re-export.
pub const VTERM_MOD_ALT = types.VTERM_MOD_ALT;

/// Ctrl modifier constant re-export.
pub const VTERM_MOD_CTRL = types.VTERM_MOD_CTRL;

/// No-key constant re-export.
pub const VTERM_KEY_NONE = types.VTERM_KEY_NONE;

/// Enter key constant re-export.
pub const VTERM_KEY_ENTER = types.VTERM_KEY_ENTER;

/// Tab key constant re-export.
pub const VTERM_KEY_TAB = types.VTERM_KEY_TAB;

/// Backspace key constant re-export.
pub const VTERM_KEY_BACKSPACE = types.VTERM_KEY_BACKSPACE;

/// Escape key constant re-export.
pub const VTERM_KEY_ESCAPE = types.VTERM_KEY_ESCAPE;

/// Up key constant re-export.
pub const VTERM_KEY_UP = types.VTERM_KEY_UP;

/// Down key constant re-export.
pub const VTERM_KEY_DOWN = types.VTERM_KEY_DOWN;

/// Left key constant re-export.
pub const VTERM_KEY_LEFT = types.VTERM_KEY_LEFT;

/// Right key constant re-export.
pub const VTERM_KEY_RIGHT = types.VTERM_KEY_RIGHT;

/// Insert key constant re-export.
pub const VTERM_KEY_INS = types.VTERM_KEY_INS;

/// Delete key constant re-export.
pub const VTERM_KEY_DEL = types.VTERM_KEY_DEL;

/// Home key constant re-export.
pub const VTERM_KEY_HOME = types.VTERM_KEY_HOME;

/// End key constant re-export.
pub const VTERM_KEY_END = types.VTERM_KEY_END;

/// PageUp key constant re-export.
pub const VTERM_KEY_PAGEUP = types.VTERM_KEY_PAGEUP;

/// PageDown key constant re-export.
pub const VTERM_KEY_PAGEDOWN = types.VTERM_KEY_PAGEDOWN;

/// F1 key constant re-export.
pub const VTERM_KEY_F1 = types.VTERM_KEY_F1;

/// F2 key constant re-export.
pub const VTERM_KEY_F2 = types.VTERM_KEY_F2;

/// F3 key constant re-export.
pub const VTERM_KEY_F3 = types.VTERM_KEY_F3;

/// F4 key constant re-export.
pub const VTERM_KEY_F4 = types.VTERM_KEY_F4;

/// F5 key constant re-export.
pub const VTERM_KEY_F5 = types.VTERM_KEY_F5;

/// F6 key constant re-export.
pub const VTERM_KEY_F6 = types.VTERM_KEY_F6;

/// F7 key constant re-export.
pub const VTERM_KEY_F7 = types.VTERM_KEY_F7;

/// F8 key constant re-export.
pub const VTERM_KEY_F8 = types.VTERM_KEY_F8;

/// F9 key constant re-export.
pub const VTERM_KEY_F9 = types.VTERM_KEY_F9;

/// F10 key constant re-export.
pub const VTERM_KEY_F10 = types.VTERM_KEY_F10;

/// F11 key constant re-export.
pub const VTERM_KEY_F11 = types.VTERM_KEY_F11;

/// F12 key constant re-export.
pub const VTERM_KEY_F12 = types.VTERM_KEY_F12;

/// Selection state API re-export.
pub const SelectionState = selection.SelectionState;

/// Metrics API re-export.
pub const Metrics = metrics.Metrics;

/// VtCore snapshot re-export.
pub const VtCoreSnapshot = snapshot.VtCoreSnapshot;
