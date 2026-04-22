# Howl Terminal Parser API Contract

Frozen as of HT-019. Authority locks consumer planning.

## Stable Exported Symbols

### Parser Module

**Parser** (struct)
- Responsibility: state machine for ANSI/DEC escape sequence parsing
- Ownership: terminal parser layer; no runtime/session policy
- Breakage: init, deinit, handleByte, handleSlice, reset signature changes; state field changes

**Sink** (struct)
- Responsibility: callback interface for parser events
- Ownership: contract between parser and event consumer
- Breakage: adding/removing callbacks; changing callback signatures

**OscTerminator** (enum)
- Responsibility: OSC termination type (BEL vs ST)
- Ownership: parser contract
- Breakage: adding/removing variants

**EscState, OscState, ApcState, DcsState** (enums)
- Responsibility: parser internal state types
- Ownership: parser layer
- Breakage: adding/removing variants
- Use: minimal; prefer opaque Parser interface

**Charset, CharsetTarget** (enums)
- Responsibility: character set identity
- Ownership: parser layer
- Breakage: adding/removing variants

### Parser Primitives

**Stream** (struct)
- Responsibility: UTF-8 decoder and byte-level event classifier
- Ownership: stream layer
- Breakage: feed() contract or StreamEvent variant changes

**Utf8Decoder** (struct)
- Responsibility: stateful UTF-8 reassembly
- Ownership: stream/UTF-8 primitives
- Breakage: decoder state or output contract changes
- Use: internal to stream layer

**CsiParser** (struct)
- Responsibility: stateful CSI parameter and final-byte parsing
- Ownership: parser CSI layer
- Breakage: parameter array size (currently 16) or param semantics changes
- Entrypoint: feed(byte) -> ?CsiAction

**CsiAction** (struct)
- Responsibility: completed CSI sequence with final byte and parameters
- Ownership: parser CSI contract
- Breakage: param representation or count semantics changes
- Fields: final: u8, params: [16]i32, count: u8

### Model Types

**CursorPos** (struct)
- Fields: row: usize, col: usize
- Responsibility: cursor position representation
- Breakage: field type or name changes

**Cell, CellAttrs, Color** (structs)
- Responsibility: terminal cell and style representation
- Ownership: model type definitions
- Breakage: field type or layout changes

**CursorShape, CursorStyle** (enum, struct)
- Responsibility: cursor appearance
- Breakage: enum variant or struct field changes

## Breaking Change Rule

A change is breaking if:
1. Public symbol is removed
2. Public field, parameter, or return type changes
3. Enum variant is added or removed
4. Callback signature changes
5. Semantics of existing behavior change (e.g., parameter order, terminator detection, charset switching)

## Breaking Change Approval

Required for any breaking change:
- Explicit mention in commit message ("BREAKING: ...")
- Rationale explaining why breaking change is necessary
- Update to this contract document
- Migration path for existing consumers

## Non-Breaking Additions

Allowed without architecture review:
- New exported public types (distinct from existing)
- New methods on existing structs
- New model types in types.zig
- Internal refactors preserving public contract
