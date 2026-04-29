//! Responsibility: expose the package public module surface.
//! Ownership: root API export boundary.
//! Reason: provide stable import paths for parser/model lanes.

const std = @import("std");

/// Parser module export.
pub const parser = @import("parser/parser.zig");

/// Event pipeline module export.
pub const pipeline = @import("event/pipeline.zig");

/// Semantic mapping module export.
pub const semantic = @import("event/semantic.zig");

/// Screen state module export.
pub const screen = @import("screen/state.zig");

/// Shared model module export.
pub const model = @import("model.zig");

/// Engine module export.
pub const engine = @import("runtime/engine.zig");
pub const VtCore = engine.Engine;
pub const Engine = VtCore;

pub const ControlSignal = enum {
    hangup,
    interrupt,
    terminate,
    resize_notify,
};

pub const Key = model.Key;
pub const Modifier = model.Modifier;

pub const mod_none: Modifier = model.VTERM_MOD_NONE;
pub const mod_shift: Modifier = model.VTERM_MOD_SHIFT;
pub const mod_alt: Modifier = model.VTERM_MOD_ALT;
pub const mod_ctrl: Modifier = model.VTERM_MOD_CTRL;

pub const key_enter: Key = model.VTERM_KEY_ENTER;
pub const key_tab: Key = model.VTERM_KEY_TAB;
pub const key_backspace: Key = model.VTERM_KEY_BACKSPACE;
pub const key_escape: Key = model.VTERM_KEY_ESCAPE;
pub const key_up: Key = model.VTERM_KEY_UP;
pub const key_down: Key = model.VTERM_KEY_DOWN;
pub const key_left: Key = model.VTERM_KEY_LEFT;
pub const key_right: Key = model.VTERM_KEY_RIGHT;
pub const key_insert: Key = model.VTERM_KEY_INS;
pub const key_delete: Key = model.VTERM_KEY_DEL;
pub const key_home: Key = model.VTERM_KEY_HOME;
pub const key_end: Key = model.VTERM_KEY_END;
pub const key_pageup: Key = model.VTERM_KEY_PAGEUP;
pub const key_pagedown: Key = model.VTERM_KEY_PAGEDOWN;
pub const key_f1: Key = model.VTERM_KEY_F1;
pub const key_f2: Key = model.VTERM_KEY_F2;
pub const key_f3: Key = model.VTERM_KEY_F3;
pub const key_f4: Key = model.VTERM_KEY_F4;
pub const key_f5: Key = model.VTERM_KEY_F5;
pub const key_f6: Key = model.VTERM_KEY_F6;
pub const key_f7: Key = model.VTERM_KEY_F7;
pub const key_f8: Key = model.VTERM_KEY_F8;
pub const key_f9: Key = model.VTERM_KEY_F9;
pub const key_f10: Key = model.VTERM_KEY_F10;
pub const key_f11: Key = model.VTERM_KEY_F11;
pub const key_f12: Key = model.VTERM_KEY_F12;

pub fn parseKeyToken(name: []const u8) ?Key {
    if (std.mem.eql(u8, name, "KEYCODE_ENTER")) return key_enter;
    if (std.mem.eql(u8, name, "KEYCODE_TAB")) return key_tab;
    if (std.mem.eql(u8, name, "KEYCODE_DEL")) return key_backspace;
    if (std.mem.eql(u8, name, "KEYCODE_ESCAPE")) return key_escape;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_UP")) return key_up;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_DOWN")) return key_down;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_LEFT")) return key_left;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_RIGHT")) return key_right;
    if (std.mem.eql(u8, name, "KEYCODE_INSERT")) return key_insert;
    if (std.mem.eql(u8, name, "KEYCODE_FORWARD_DEL")) return key_delete;
    if (std.mem.eql(u8, name, "KEYCODE_MOVE_HOME")) return key_home;
    if (std.mem.eql(u8, name, "KEYCODE_MOVE_END")) return key_end;
    if (std.mem.eql(u8, name, "KEYCODE_PAGE_UP")) return key_pageup;
    if (std.mem.eql(u8, name, "KEYCODE_PAGE_DOWN")) return key_pagedown;
    if (std.mem.eql(u8, name, "KEYCODE_F1")) return key_f1;
    if (std.mem.eql(u8, name, "KEYCODE_F2")) return key_f2;
    if (std.mem.eql(u8, name, "KEYCODE_F3")) return key_f3;
    if (std.mem.eql(u8, name, "KEYCODE_F4")) return key_f4;
    if (std.mem.eql(u8, name, "KEYCODE_F5")) return key_f5;
    if (std.mem.eql(u8, name, "KEYCODE_F6")) return key_f6;
    if (std.mem.eql(u8, name, "KEYCODE_F7")) return key_f7;
    if (std.mem.eql(u8, name, "KEYCODE_F8")) return key_f8;
    if (std.mem.eql(u8, name, "KEYCODE_F9")) return key_f9;
    if (std.mem.eql(u8, name, "KEYCODE_F10")) return key_f10;
    if (std.mem.eql(u8, name, "KEYCODE_F11")) return key_f11;
    if (std.mem.eql(u8, name, "KEYCODE_F12")) return key_f12;
    return null;
}

pub fn parseModifierBits(mods: i32) Modifier {
    var out: Modifier = mod_none;
    if ((mods & 0x01) != 0) out |= mod_ctrl;
    if ((mods & 0x02) != 0) out |= mod_alt;
    if ((mods & 0x04) != 0) out |= mod_shift;
    return out;
}

pub fn parseControlToken(name: []const u8) ?ControlSignal {
    if (std.mem.eql(u8, name, "interrupt")) return .interrupt;
    if (std.mem.eql(u8, name, "terminate")) return .terminate;
    return null;
}

comptime {
    _ = @import("test/relay.zig");
    _ = @import("test/api_api.zig");
}

test "root: exposes host-neutral module surface" {
    try std.testing.expect(@hasDecl(@This(), "parser"));
    try std.testing.expect(@hasDecl(@This(), "pipeline"));
    try std.testing.expect(@hasDecl(@This(), "semantic"));
    try std.testing.expect(@hasDecl(@This(), "screen"));
    try std.testing.expect(@hasDecl(@This(), "model"));
    try std.testing.expect(@hasDecl(@This(), "engine"));
}
