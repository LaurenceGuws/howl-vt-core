//! Responsibility: define keyboard metadata carriers.
//! Ownership: input keyboard metadata authority.
//! Reason: isolate optional host keyboard metadata types.

pub const PhysicalKey = u32;

pub const KeyboardAlternateMetadata = struct {
    physical_key: ?PhysicalKey = null,
    produced_text_utf8: ?[]const u8 = null,
    base_codepoint: ?u32 = null,
    shifted_codepoint: ?u32 = null,
    alternate_layout_codepoint: ?u32 = null,
    text_is_composed: bool = false,
};
