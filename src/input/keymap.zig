//! Responsibility: define terminal key and modifier vocabulary.
//! Ownership: input key mapping authority.
//! Reason: keep key/mod semantics local to input layer.

pub const Key = u32;
pub const Modifier = u8;

pub const VTERM_KEY_NONE: Key = 0;
pub const VTERM_KEY_ENTER: Key = 1;
pub const VTERM_KEY_TAB: Key = 2;
pub const VTERM_KEY_BACKSPACE: Key = 3;
pub const VTERM_KEY_ESCAPE: Key = 4;
pub const VTERM_KEY_UP: Key = 5;
pub const VTERM_KEY_DOWN: Key = 6;
pub const VTERM_KEY_LEFT: Key = 7;
pub const VTERM_KEY_RIGHT: Key = 8;
pub const VTERM_KEY_INS: Key = 9;
pub const VTERM_KEY_DEL: Key = 10;
pub const VTERM_KEY_HOME: Key = 11;
pub const VTERM_KEY_END: Key = 12;
pub const VTERM_KEY_PAGEUP: Key = 13;
pub const VTERM_KEY_PAGEDOWN: Key = 14;
pub const VTERM_KEY_LEFT_SHIFT: Key = 15;
pub const VTERM_KEY_RIGHT_SHIFT: Key = 16;
pub const VTERM_KEY_LEFT_CTRL: Key = 17;
pub const VTERM_KEY_RIGHT_CTRL: Key = 18;
pub const VTERM_KEY_LEFT_ALT: Key = 19;
pub const VTERM_KEY_RIGHT_ALT: Key = 20;
pub const VTERM_KEY_LEFT_SUPER: Key = 21;
pub const VTERM_KEY_RIGHT_SUPER: Key = 22;
pub const VTERM_KEY_F1: Key = 23;
pub const VTERM_KEY_F2: Key = 24;
pub const VTERM_KEY_F3: Key = 25;
pub const VTERM_KEY_F4: Key = 26;
pub const VTERM_KEY_F5: Key = 27;
pub const VTERM_KEY_F6: Key = 28;
pub const VTERM_KEY_F7: Key = 29;
pub const VTERM_KEY_F8: Key = 30;
pub const VTERM_KEY_F9: Key = 31;
pub const VTERM_KEY_F10: Key = 32;
pub const VTERM_KEY_F11: Key = 33;
pub const VTERM_KEY_F12: Key = 34;

pub const VTERM_MOD_NONE: Modifier = 0;
pub const VTERM_MOD_SHIFT: Modifier = 1;
pub const VTERM_MOD_ALT: Modifier = 2;
pub const VTERM_MOD_CTRL: Modifier = 4;
