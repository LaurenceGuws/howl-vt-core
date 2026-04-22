# Event Bridge Contract

`EVENT_BRIDGE_CONTRACT` — frozen as of HT-021. Authority for `Bridge` and `Event`.

## Event Variants

| Variant | Source callback | Payload meaning |
| --- | --- | --- |
| `text` | `onAsciiSlice` | Owned slice of contiguous printable ASCII bytes; bridge-allocated copy |
| `codepoint` | `onStreamEvent(.codepoint)` | Decoded Unicode scalar value (U+0080 and above) |
| `control` | `onStreamEvent(.control)` | Raw C0/C1 control byte |
| `style_change` | `onCsi` | CSI sequence: `final` byte, `params[16]i32`, `param_count` |
| `title_set` | `onOsc` | Full raw OSC payload as bridge-allocated copy; command prefix not parsed |
| `invalid_sequence` | `onStreamEvent(.invalid)` | Stream-level encoding error; no payload |

## Ownership and Lifetime

Payload slices in `text` and `title_set` are allocated by the bridge at event emission time (`allocator.dupe`). The ownership of each slice transfers to the bridge; callers must not free them. Their lifetime ends at `Bridge.deinit`. The parser may reuse its internal buffers immediately after the callback returns; bridge events do not alias parser-internal memory.

Variants `codepoint`, `control`, `style_change`, and `invalid_sequence` carry no heap allocation.

## Callback Mapping Policy

| Sink callback | Event emitted | Notes |
| --- | --- | --- |
| `onStreamEvent(.codepoint)` | `codepoint` | Direct |
| `onStreamEvent(.control)` | `control` | Direct |
| `onStreamEvent(.invalid)` | `invalid_sequence` | Direct |
| `onAsciiSlice` | `text` | Payload duplicated |
| `onCsi` | `style_change` | `CsiAction` fields copied inline |
| `onOsc` | `title_set` | Full raw payload duplicated; `OscTerminator` ignored; command prefix not parsed |
| `onApc` | _(none)_ | Explicitly dropped |
| `onDcs` | _(none)_ | Explicitly dropped |
| `onEscFinal` | _(none)_ | Explicitly dropped |

## Non-Goals

The following are intentionally not represented at this seam:

- OSC command number parsing (e.g., discriminating title-set from hyperlink or color queries)
- APC payload interpretation (e.g., Kitty graphics protocol)
- DCS payload interpretation (e.g., DECRQSS responses)
- ESC final-byte dispatch (e.g., character set designation)
- Cursor movement, mode-set, or erase operations (no semantic VT model at this layer)
- Host, session, PTY, or platform coupling of any kind

## Breaking Change Rule

A change is breaking if:

1. A `Event` variant is added, removed, or renamed
2. A payload field type or name changes in `style_change`
3. Ownership semantics for `text` or `title_set` change
4. A previously dropped callback begins emitting events
5. A previously emitted event is dropped

## Breaking Change Approval

Required for any breaking change:

- Explicit mention in commit message ("BREAKING: ...") tagged as `breaking-change`
- Rationale explaining why the change is necessary
- Update to this document
- Update to `PARSER_API_CONTRACT.md` if the Sink interface changes
