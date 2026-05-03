//! Responsibility: export the parser domain object surface.
//! Ownership: parser package boundary.
//! Reason: keep one canonical owner for stream decoding and parser state machines.

const parser = @import("parser/parser.zig");
const stream = @import("parser/stream.zig");
const csi = @import("parser/csi.zig");

pub const ParserApi = struct {
    pub const Parser = parser.Parser;
    pub const Sink = parser.Sink;
    pub const OscTerminator = parser.OscTerminator;

    pub const Stream = stream.Stream;
    pub const StreamEvent = stream.StreamEvent;

    pub const CsiAction = csi.CsiAction;
    pub const CsiParser = csi.CsiParser;
    pub const max_params = csi.max_params;
    pub const max_intermediates = csi.max_intermediates;
};
