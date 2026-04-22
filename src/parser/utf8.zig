//! Responsibility: decode UTF-8 byte streams into codepoints.
//! Ownership: parser UTF-8 primitive.
//! Reason: centralize UTF-8 state handling for parser stream consumers.

const std = @import("std");

/// Result of feeding one byte into the UTF-8 decoder state machine.
pub const Utf8Result = union(enum) {
    codepoint: u21,
    incomplete,
    invalid,
};

/// Stateful UTF-8 decoder used by parser stream classification.
pub const Utf8Decoder = struct {
    buf: [4]u8 = undefined,
    len: u8 = 0,
    needed: u8 = 0,

    /// Reset decoder state to byte-aligned ground.
    pub fn reset(self: *Utf8Decoder) void {
        self.len = 0;
        self.needed = 0;
    }

    /// Feed one byte and emit a decoded codepoint, `.incomplete`, or `.invalid`.
    /// `byte` is treated as the next sequential byte in the current stream.
    pub fn feed(self: *Utf8Decoder, byte: u8) Utf8Result {
        if (self.needed == 0) {
            if (byte < 0x80) {
                return .{ .codepoint = @intCast(byte) };
            }
            const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch return .invalid;
            self.buf[0] = byte;
            self.len = 1;
            self.needed = @intCast(seq_len);
            if (self.needed == 1) {
                const cp = std.unicode.utf8Decode(self.buf[0..1]) catch {
                    self.reset();
                    return .invalid;
                };
                self.reset();
                return .{ .codepoint = @intCast(cp) };
            }
            return .incomplete;
        }

        // Continuation byte required
        if ((byte & 0xC0) != 0x80) {
            self.reset();
            return .invalid;
        }
        self.buf[self.len] = byte;
        self.len += 1;

        if (self.len < self.needed) return .incomplete;

        const cp = std.unicode.utf8Decode(self.buf[0..self.needed]) catch {
            self.reset();
            return .invalid;
        };
        self.reset();
        return .{ .codepoint = @intCast(cp) };
    }
};

test "UTF8 decoder: ASCII passthrough" {
    var decoder = Utf8Decoder{};
    const result = decoder.feed('A');
    try std.testing.expectEqual(@as(u21, 'A'), result.codepoint);
}

test "UTF8 decoder: multi-byte sequence (€ = U+20AC)" {
    var decoder = Utf8Decoder{};
    var result = decoder.feed(0xE2);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed(0x82);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed(0xAC);
    try std.testing.expectEqual(@as(u21, 0x20AC), result.codepoint);
}
