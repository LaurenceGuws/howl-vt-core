//! Responsibility: export the input domain object surface.
//! Ownership: input package boundary.
//! Reason: keep one canonical owner for key, mouse, and codec behavior.

const keymap = @import("input/keymap.zig");
const mouse = @import("input/mouse.zig");
const codec = @import("input/codec.zig");

pub const Input = struct {
    pub const Key = keymap.Key;
    pub const Modifier = keymap.Modifier;

    pub const MouseButton = mouse.MouseButton;
    pub const MouseEventKind = mouse.MouseEventKind;
    pub const MouseEvent = mouse.MouseEvent;

    pub const Codec = codec.InputCodec;

    pub const mod_none: Modifier = keymap.VTERM_MOD_NONE;
    pub const mod_shift: Modifier = keymap.VTERM_MOD_SHIFT;
    pub const mod_alt: Modifier = keymap.VTERM_MOD_ALT;
    pub const mod_ctrl: Modifier = keymap.VTERM_MOD_CTRL;

    pub const key_enter: Key = keymap.VTERM_KEY_ENTER;
    pub const key_tab: Key = keymap.VTERM_KEY_TAB;
    pub const key_backspace: Key = keymap.VTERM_KEY_BACKSPACE;
    pub const key_escape: Key = keymap.VTERM_KEY_ESCAPE;
    pub const key_up: Key = keymap.VTERM_KEY_UP;
    pub const key_down: Key = keymap.VTERM_KEY_DOWN;
    pub const key_left: Key = keymap.VTERM_KEY_LEFT;
    pub const key_right: Key = keymap.VTERM_KEY_RIGHT;
    pub const key_insert: Key = keymap.VTERM_KEY_INS;
    pub const key_delete: Key = keymap.VTERM_KEY_DEL;
    pub const key_home: Key = keymap.VTERM_KEY_HOME;
    pub const key_end: Key = keymap.VTERM_KEY_END;
    pub const key_pageup: Key = keymap.VTERM_KEY_PAGEUP;
    pub const key_pagedown: Key = keymap.VTERM_KEY_PAGEDOWN;
    pub const key_f1: Key = keymap.VTERM_KEY_F1;
    pub const key_f2: Key = keymap.VTERM_KEY_F2;
    pub const key_f3: Key = keymap.VTERM_KEY_F3;
    pub const key_f4: Key = keymap.VTERM_KEY_F4;
    pub const key_f5: Key = keymap.VTERM_KEY_F5;
    pub const key_f6: Key = keymap.VTERM_KEY_F6;
    pub const key_f7: Key = keymap.VTERM_KEY_F7;
    pub const key_f8: Key = keymap.VTERM_KEY_F8;
    pub const key_f9: Key = keymap.VTERM_KEY_F9;
    pub const key_f10: Key = keymap.VTERM_KEY_F10;
    pub const key_f11: Key = keymap.VTERM_KEY_F11;
    pub const key_f12: Key = keymap.VTERM_KEY_F12;
};
