//! Responsibility: define terminal mouse event vocabulary.
//! Ownership: input mouse data authority.
//! Reason: keep pointer-event semantics local to input layer.

const keymap = @import("keymap.zig");

pub const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
};

pub const MouseEventKind = enum(u8) {
    press,
    release,
    move,
    wheel,
};

pub const MouseEvent = struct {
    kind: MouseEventKind,
    button: MouseButton,
    row: i32,
    col: u16,
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
    mod: keymap.Modifier,
    buttons_down: u8,
};
