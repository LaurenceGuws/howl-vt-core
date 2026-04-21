//! Responsibility: expose parser primitives and parser state machine APIs.
//! Ownership: terminal parser module boundary.
//! Reason: keep parser imports stable while internals evolve.

pub const stream = @import("parser/stream.zig");
pub const utf8 = @import("parser/utf8.zig");
pub const csi = @import("parser/csi.zig");
pub const parser = @import("parser/parser.zig");

pub const Stream = stream.Stream;
pub const StreamEvent = stream.StreamEvent;
pub const Utf8Decoder = utf8.Utf8Decoder;
pub const Utf8Result = utf8.Utf8Result;
pub const CsiParser = csi.CsiParser;
pub const CsiAction = csi.CsiAction;

pub const Parser = parser.Parser;
pub const Sink = parser.Sink;
pub const EscState = parser.EscState;
pub const OscState = parser.OscState;
pub const ApcState = parser.ApcState;
pub const DcsState = parser.DcsState;
pub const OscTerminator = parser.OscTerminator;
pub const Charset = parser.Charset;
pub const CharsetTarget = parser.CharsetTarget;
