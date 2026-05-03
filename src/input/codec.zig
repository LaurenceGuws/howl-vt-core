//! Responsibility: encode host input and parse host-facing input tokens.
//! Ownership: input codec authority.
//! Reason: keep terminal key/mouse encoding and token parsing out of vt_core orchestration.

const std = @import("std");
const keymap = @import("keymap.zig");
const mouse = @import("mouse.zig");

pub const InputCodec = struct {
    pub fn encodeKey(buf: []u8, key: keymap.Key, mod: keymap.Modifier) []const u8 {
        var len: usize = 0;
        const shift_active = (mod & keymap.VTERM_MOD_SHIFT) != 0;

        switch (key) {
            keymap.VTERM_KEY_ENTER => {
                buf[0] = '\r';
                len = 1;
            },
            keymap.VTERM_KEY_TAB => {
                if (shift_active) {
                    buf[0] = '\x1b';
                    buf[1] = '[';
                    buf[2] = 'Z';
                    len = 3;
                } else {
                    buf[0] = '\t';
                    len = 1;
                }
            },
            keymap.VTERM_KEY_BACKSPACE => {
                buf[0] = '\x7f';
                len = 1;
            },
            keymap.VTERM_KEY_ESCAPE => {
                buf[0] = '\x1b';
                len = 1;
            },
            keymap.VTERM_KEY_UP => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'A';
                    len = 6;
                } else {
                    buf[2] = 'A';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_DOWN => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'B';
                    len = 6;
                } else {
                    buf[2] = 'B';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_RIGHT => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'C';
                    len = 6;
                } else {
                    buf[2] = 'C';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_LEFT => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'D';
                    len = 6;
                } else {
                    buf[2] = 'D';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_HOME => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'H';
                    len = 6;
                } else {
                    buf[2] = 'H';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_END => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'F';
                    len = 6;
                } else {
                    buf[2] = 'F';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_INS => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_DEL => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '3';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_PAGEUP => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '5';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_PAGEDOWN => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '6';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_F1 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'P';
                    len = 6;
                } else {
                    buf[2] = 'P';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_F2 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'Q';
                    len = 6;
                } else {
                    buf[2] = 'Q';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_F3 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'R';
                    len = 6;
                } else {
                    buf[2] = 'R';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_F4 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[2] = '1';
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = 'S';
                    len = 6;
                } else {
                    buf[2] = 'S';
                    len = 3;
                }
            },
            keymap.VTERM_KEY_F5 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '5';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F6 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '7';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F7 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '8';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F8 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '9';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F9 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '0';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F10 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '1';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F11 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '3';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F12 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '4';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            else => {
                if (key > 31 and key < 127) {
                    buf[0] = @intCast(key);
                    len = 1;
                } else if (key > 127) {
                    len = std.unicode.utf8Encode(@intCast(key), buf[0..]) catch 0;
                }
            },
        }

        return buf[0..len];
    }

    pub fn encodeMouse(buf: []u8, event: mouse.MouseEvent) []const u8 {
        _ = event;
        return buf[0..0];
    }

    pub fn parseKeyToken(name: []const u8) ?keymap.Key {
        if (std.mem.eql(u8, name, "KEYCODE_ENTER")) return keymap.VTERM_KEY_ENTER;
        if (std.mem.eql(u8, name, "KEYCODE_TAB")) return keymap.VTERM_KEY_TAB;
        if (std.mem.eql(u8, name, "KEYCODE_DEL")) return keymap.VTERM_KEY_BACKSPACE;
        if (std.mem.eql(u8, name, "KEYCODE_ESCAPE")) return keymap.VTERM_KEY_ESCAPE;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_UP")) return keymap.VTERM_KEY_UP;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_DOWN")) return keymap.VTERM_KEY_DOWN;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_LEFT")) return keymap.VTERM_KEY_LEFT;
        if (std.mem.eql(u8, name, "KEYCODE_DPAD_RIGHT")) return keymap.VTERM_KEY_RIGHT;
        if (std.mem.eql(u8, name, "KEYCODE_INSERT")) return keymap.VTERM_KEY_INS;
        if (std.mem.eql(u8, name, "KEYCODE_FORWARD_DEL")) return keymap.VTERM_KEY_DEL;
        if (std.mem.eql(u8, name, "KEYCODE_MOVE_HOME")) return keymap.VTERM_KEY_HOME;
        if (std.mem.eql(u8, name, "KEYCODE_MOVE_END")) return keymap.VTERM_KEY_END;
        if (std.mem.eql(u8, name, "KEYCODE_PAGE_UP")) return keymap.VTERM_KEY_PAGEUP;
        if (std.mem.eql(u8, name, "KEYCODE_PAGE_DOWN")) return keymap.VTERM_KEY_PAGEDOWN;
        if (std.mem.eql(u8, name, "KEYCODE_F1")) return keymap.VTERM_KEY_F1;
        if (std.mem.eql(u8, name, "KEYCODE_F2")) return keymap.VTERM_KEY_F2;
        if (std.mem.eql(u8, name, "KEYCODE_F3")) return keymap.VTERM_KEY_F3;
        if (std.mem.eql(u8, name, "KEYCODE_F4")) return keymap.VTERM_KEY_F4;
        if (std.mem.eql(u8, name, "KEYCODE_F5")) return keymap.VTERM_KEY_F5;
        if (std.mem.eql(u8, name, "KEYCODE_F6")) return keymap.VTERM_KEY_F6;
        if (std.mem.eql(u8, name, "KEYCODE_F7")) return keymap.VTERM_KEY_F7;
        if (std.mem.eql(u8, name, "KEYCODE_F8")) return keymap.VTERM_KEY_F8;
        if (std.mem.eql(u8, name, "KEYCODE_F9")) return keymap.VTERM_KEY_F9;
        if (std.mem.eql(u8, name, "KEYCODE_F10")) return keymap.VTERM_KEY_F10;
        if (std.mem.eql(u8, name, "KEYCODE_F11")) return keymap.VTERM_KEY_F11;
        if (std.mem.eql(u8, name, "KEYCODE_F12")) return keymap.VTERM_KEY_F12;
        return null;
    }

    pub fn parseModifierBits(mods: i32) keymap.Modifier {
        var out: keymap.Modifier = keymap.VTERM_MOD_NONE;
        if ((mods & 0x01) != 0) out |= keymap.VTERM_MOD_CTRL;
        if ((mods & 0x02) != 0) out |= keymap.VTERM_MOD_ALT;
        if ((mods & 0x04) != 0) out |= keymap.VTERM_MOD_SHIFT;
        return out;
    }
};
