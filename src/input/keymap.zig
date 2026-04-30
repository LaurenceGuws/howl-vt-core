//! Responsibility: define terminal key and modifier vocabulary.
//! Ownership: input key mapping authority.
//! Reason: keep key/mod semantics local to input layer.

/// Terminal key identifier type.
pub const Key = u32;
/// Terminal modifier bitset type.
pub const Modifier = u8;

/// No key.
pub const VTERM_KEY_NONE: Key = 0;
/// Enter/return key.
pub const VTERM_KEY_ENTER: Key = 1;
/// Tab key.
pub const VTERM_KEY_TAB: Key = 2;
/// Backspace key.
pub const VTERM_KEY_BACKSPACE: Key = 3;
/// Escape key.
pub const VTERM_KEY_ESCAPE: Key = 4;
/// Arrow up key.
pub const VTERM_KEY_UP: Key = 5;
/// Arrow down key.
pub const VTERM_KEY_DOWN: Key = 6;
/// Arrow left key.
pub const VTERM_KEY_LEFT: Key = 7;
/// Arrow right key.
pub const VTERM_KEY_RIGHT: Key = 8;
/// Insert key.
pub const VTERM_KEY_INS: Key = 9;
/// Delete key.
pub const VTERM_KEY_DEL: Key = 10;
/// Home key.
pub const VTERM_KEY_HOME: Key = 11;
/// End key.
pub const VTERM_KEY_END: Key = 12;
/// Page up key.
pub const VTERM_KEY_PAGEUP: Key = 13;
/// Page down key.
pub const VTERM_KEY_PAGEDOWN: Key = 14;
/// Left Shift key.
pub const VTERM_KEY_LEFT_SHIFT: Key = 15;
/// Right Shift key.
pub const VTERM_KEY_RIGHT_SHIFT: Key = 16;
/// Left Control key.
pub const VTERM_KEY_LEFT_CTRL: Key = 17;
/// Right Control key.
pub const VTERM_KEY_RIGHT_CTRL: Key = 18;
/// Left Alt key.
pub const VTERM_KEY_LEFT_ALT: Key = 19;
/// Right Alt key.
pub const VTERM_KEY_RIGHT_ALT: Key = 20;
/// Left Super key.
pub const VTERM_KEY_LEFT_SUPER: Key = 21;
/// Right Super key.
pub const VTERM_KEY_RIGHT_SUPER: Key = 22;
/// Function key F1.
pub const VTERM_KEY_F1: Key = 23;
/// Function key F2.
pub const VTERM_KEY_F2: Key = 24;
/// Function key F3.
pub const VTERM_KEY_F3: Key = 25;
/// Function key F4.
pub const VTERM_KEY_F4: Key = 26;
/// Function key F5.
pub const VTERM_KEY_F5: Key = 27;
/// Function key F6.
pub const VTERM_KEY_F6: Key = 28;
/// Function key F7.
pub const VTERM_KEY_F7: Key = 29;
/// Function key F8.
pub const VTERM_KEY_F8: Key = 30;
/// Function key F9.
pub const VTERM_KEY_F9: Key = 31;
/// Function key F10.
pub const VTERM_KEY_F10: Key = 32;
/// Function key F11.
pub const VTERM_KEY_F11: Key = 33;
/// Function key F12.
pub const VTERM_KEY_F12: Key = 34;

/// No modifiers.
pub const VTERM_MOD_NONE: Modifier = 0;
/// Shift modifier bit.
pub const VTERM_MOD_SHIFT: Modifier = 1;
/// Alt modifier bit.
pub const VTERM_MOD_ALT: Modifier = 2;
/// Control modifier bit.
pub const VTERM_MOD_CTRL: Modifier = 4;
