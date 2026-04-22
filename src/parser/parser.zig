//! Responsibility: parse terminal byte streams into parser-layer events.
//! Ownership: terminal parser module; no host/session/runtime policy.
//! Reason: keep escape-sequence parsing isolated behind callback dispatch.

const std = @import("std");
const stream_mod = @import("stream.zig");
const csi_mod = @import("csi.zig");

/// Top-level parser control states outside OSC/APC/DCS substates.
pub const EscState = enum {
    ground,
    esc,
    csi,
    charset,
};

/// OSC parser substate used while accumulating OSC payload bytes.
pub const OscState = enum {
    idle,
    osc,
    osc_esc,
};

/// APC parser substate used while accumulating APC payload bytes.
pub const ApcState = enum {
    idle,
    apc,
    apc_esc,
};

/// DCS parser substate used while accumulating DCS payload bytes.
pub const DcsState = enum {
    idle,
    dcs,
    dcs_esc,
};

/// Terminator variant used when emitting completed OSC payloads.
pub const OscTerminator = enum {
    bel,
    st,
};

/// Supported designated character set identity for GL mapping.
pub const Charset = enum {
    ascii,
    dec_special,
};

/// Active charset designation target used by ESC '(' and ')'.
pub const CharsetTarget = enum {
    g0,
    g1,
};

/// Callback sink interface receiving parser-decoded events.
pub const Sink = struct {
    ptr: *anyopaque,
    onStreamEventFn: *const fn (*anyopaque, stream_mod.StreamEvent) void,
    onAsciiSliceFn: *const fn (*anyopaque, []const u8) void,
    onCsiFn: *const fn (*anyopaque, csi_mod.CsiAction) void,
    onOscFn: *const fn (*anyopaque, []const u8, OscTerminator) void,
    onApcFn: *const fn (*anyopaque, []const u8) void,
    onDcsFn: *const fn (*anyopaque, []const u8) void,
    onEscFinalFn: *const fn (*anyopaque, u8) void,

    /// Forward a decoded stream event to sink implementation.
    pub fn onStreamEvent(self: Sink, event: stream_mod.StreamEvent) void {
        self.onStreamEventFn(self.ptr, event);
    }

    /// Forward an ASCII slice event to sink implementation.
    pub fn onAsciiSlice(self: Sink, bytes: []const u8) void {
        self.onAsciiSliceFn(self.ptr, bytes);
    }

    /// Forward a completed CSI action to sink implementation.
    pub fn onCsi(self: Sink, action: csi_mod.CsiAction) void {
        self.onCsiFn(self.ptr, action);
    }

    /// Forward a completed OSC payload and terminator to sink implementation.
    pub fn onOsc(self: Sink, data: []const u8, terminator: OscTerminator) void {
        self.onOscFn(self.ptr, data, terminator);
    }

    /// Forward a completed APC payload to sink implementation.
    pub fn onApc(self: Sink, data: []const u8) void {
        self.onApcFn(self.ptr, data);
    }

    /// Forward a completed DCS payload to sink implementation.
    pub fn onDcs(self: Sink, data: []const u8) void {
        self.onDcsFn(self.ptr, data);
    }

    /// Forward a non-CSI ESC final byte to sink implementation.
    pub fn onEscFinal(self: Sink, byte: u8) void {
        self.onEscFinalFn(self.ptr, byte);
    }
};

/// Stateful terminal parser handling ESC/CSI/OSC/APC/DCS byte streams.
pub const Parser = struct {
    allocator: std.mem.Allocator,
    sink: Sink,
    stream: stream_mod.Stream,
    esc_state: EscState,
    csi: csi_mod.CsiParser,
    osc_state: OscState,
    osc_terminator: OscTerminator,
    osc_buffer: std.ArrayList(u8),
    apc_state: ApcState,
    apc_buffer: std.ArrayList(u8),
    dcs_state: DcsState,
    dcs_buffer: std.ArrayList(u8),
    g0_charset: Charset,
    g1_charset: Charset,
    gl_charset: Charset,
    charset_target: CharsetTarget,

    /// Initialize parser state and payload buffers for OSC/APC/DCS handling.
    /// Caller owns the returned parser and must call `deinit`.
    pub fn init(allocator: std.mem.Allocator, sink: Sink) !Parser {
        var osc_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer osc_buffer.deinit(allocator);

        var apc_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer apc_buffer.deinit(allocator);

        var dcs_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer dcs_buffer.deinit(allocator);

        return .{
            .allocator = allocator,
            .sink = sink,
            .stream = .{},
            .esc_state = .ground,
            .csi = .{},
            .osc_state = .idle,
            .osc_terminator = .st,
            .osc_buffer = osc_buffer,
            .apc_state = .idle,
            .apc_buffer = apc_buffer,
            .dcs_state = .idle,
            .dcs_buffer = dcs_buffer,
            .g0_charset = .ascii,
            .g1_charset = .ascii,
            .gl_charset = .ascii,
            .charset_target = .g0,
        };
    }

    /// Release parser-owned buffers allocated during `init`.
    pub fn deinit(self: *Parser) void {
        self.osc_buffer.deinit(self.allocator);
        self.apc_buffer.deinit(self.allocator);
        self.dcs_buffer.deinit(self.allocator);
    }

    /// Reset parser runtime state while retaining allocated buffer capacity.
    pub fn reset(self: *Parser) void {
        self.stream.reset();
        self.csi.reset();
        self.esc_state = .ground;
        self.osc_state = .idle;
        self.osc_terminator = .st;
        self.apc_state = .idle;
        self.dcs_state = .idle;
        self.g0_charset = .ascii;
        self.g1_charset = .ascii;
        self.gl_charset = .ascii;
        self.charset_target = .g0;
        self.osc_buffer.clearRetainingCapacity();
        self.apc_buffer.clearRetainingCapacity();
        self.dcs_buffer.clearRetainingCapacity();
    }

    /// Parse a single byte and dispatch any resulting parser event to `sink`.
    pub fn handleByte(self: *Parser, byte: u8) void {
        if (self.osc_state != .idle) {
            self.handleOscByte(byte);
            return;
        }
        if (self.apc_state != .idle) {
            self.handleApcByte(byte);
            return;
        }
        if (self.dcs_state != .idle) {
            self.handleDcsByte(byte);
            return;
        }
        switch (self.esc_state) {
            .ground => {
                if (byte == 0x1B) {
                    self.esc_state = .esc;
                    self.stream.reset();
                    self.csi.reset();
                    self.osc_state = .idle;
                    return;
                }
                if (self.stream.feed(byte)) |event| {
                    self.sink.onStreamEvent(event);
                }
            },
            .esc => {
                if (byte == '[') {
                    self.esc_state = .csi;
                    self.csi.reset();
                } else if (byte == ']') {
                    self.esc_state = .ground;
                    self.osc_state = .osc;
                    self.osc_buffer.clearRetainingCapacity();
                    return;
                } else if (byte == 'P') {
                    self.esc_state = .ground;
                    self.dcs_state = .dcs;
                    self.dcs_buffer.clearRetainingCapacity();
                    return;
                } else if (byte == '_') {
                    self.esc_state = .ground;
                    self.apc_state = .apc;
                    self.apc_buffer.clearRetainingCapacity();
                    return;
                } else if (byte == '(') {
                    self.charset_target = .g0;
                    self.esc_state = .charset;
                } else if (byte == ')') {
                    self.charset_target = .g1;
                    self.esc_state = .charset;
                } else {
                    self.sink.onEscFinal(byte);
                    self.esc_state = .ground;
                }
            },
            .charset => {
                const charset: Charset = switch (byte) {
                    '0' => .dec_special,
                    'B' => .ascii,
                    else => .ascii,
                };
                switch (self.charset_target) {
                    .g0 => self.g0_charset = charset,
                    .g1 => self.g1_charset = charset,
                }
                if (self.charset_target == .g0) {
                    self.gl_charset = self.g0_charset;
                }
                self.esc_state = .ground;
            },
            .csi => {
                if (self.csi.feed(byte)) |action| {
                    self.sink.onCsi(action);
                    self.esc_state = .ground;
                }
            },
        }
    }

    /// Parse a byte slice, using ASCII fast-path dispatch when applicable.
    pub fn handleSlice(self: *Parser, bytes: []const u8) void {
        var i: usize = 0;
        while (i < bytes.len) {
            if (self.osc_state != .idle) {
                self.handleOscByte(bytes[i]);
                i += 1;
                continue;
            }
            if (self.apc_state != .idle) {
                self.handleApcByte(bytes[i]);
                i += 1;
                continue;
            }
            if (self.dcs_state != .idle) {
                self.handleDcsByte(bytes[i]);
                i += 1;
                continue;
            }

            if (self.esc_state == .ground and self.stream.decoder.needed == 0) {
                const start = i;
                while (i < bytes.len) {
                    const b = bytes[i];
                    if (b < 0x20 or b == 0x7f or b == 0x1b or b >= 0x80) break;
                    i += 1;
                }
                if (i > start) {
                    self.sink.onAsciiSlice(bytes[start..i]);
                    continue;
                }
            }

            self.handleByte(bytes[i]);
            i += 1;
        }
    }

    fn handleOscByte(self: *Parser, byte: u8) void {
        switch (self.osc_state) {
            .idle => return,
            .osc => {
                if (byte == 0x07) {
                    self.osc_terminator = .bel;
                    self.finishOsc();
                    return;
                }
                if (byte == 0x1B) {
                    self.osc_state = .osc_esc;
                    return;
                }
                if (self.osc_buffer.items.len < 4096) {
                    self.osc_buffer.append(self.allocator, byte) catch {};
                }
            },
            .osc_esc => {
                if (byte == '\\') {
                    self.osc_terminator = .st;
                    self.finishOsc();
                    return;
                }
                // Stray ESC marker is dropped; keep the following byte as payload data.
                self.osc_state = .osc;
                if (self.osc_buffer.items.len < 4096) {
                    self.osc_buffer.append(self.allocator, byte) catch {};
                }
            },
        }
    }

    fn finishOsc(self: *Parser) void {
        self.sink.onOsc(self.osc_buffer.items, self.osc_terminator);
        self.osc_buffer.clearRetainingCapacity();
        self.osc_state = .idle;
    }

    fn handleApcByte(self: *Parser, byte: u8) void {
        const apc_max_len: usize = 1024 * 1024;
        switch (self.apc_state) {
            .idle => return,
            .apc => {
                if (byte == 0x07) {
                    self.finishApc();
                    return;
                }
                if (byte == 0x1B) {
                    self.apc_state = .apc_esc;
                    return;
                }
                if (self.apc_buffer.items.len < apc_max_len) {
                    self.apc_buffer.append(self.allocator, byte) catch {};
                }
            },
            .apc_esc => {
                if (byte == '\\') {
                    self.finishApc();
                    return;
                }
                // Stray ESC marker is dropped; keep the following byte as payload data.
                self.apc_state = .apc;
                if (self.apc_buffer.items.len < apc_max_len) {
                    self.apc_buffer.append(self.allocator, byte) catch {};
                }
            },
        }
    }

    fn finishApc(self: *Parser) void {
        self.sink.onApc(self.apc_buffer.items);
        self.apc_buffer.clearRetainingCapacity();
        self.apc_state = .idle;
    }

    fn handleDcsByte(self: *Parser, byte: u8) void {
        switch (self.dcs_state) {
            .idle => return,
            .dcs => {
                if (byte == 0x1B) {
                    self.dcs_state = .dcs_esc;
                    return;
                }
                if (self.dcs_buffer.items.len < 4096) {
                    self.dcs_buffer.append(self.allocator, byte) catch {};
                }
            },
            .dcs_esc => {
                if (byte == '\\') {
                    self.finishDcs();
                    return;
                }
                // Stray ESC marker is dropped; keep the following byte as payload data.
                self.dcs_state = .dcs;
                if (self.dcs_buffer.items.len < 4096) {
                    self.dcs_buffer.append(self.allocator, byte) catch {};
                }
            },
        }
    }

    fn finishDcs(self: *Parser) void {
        self.sink.onDcs(self.dcs_buffer.items);
        self.dcs_buffer.clearRetainingCapacity();
        self.dcs_state = .idle;
    }
};
