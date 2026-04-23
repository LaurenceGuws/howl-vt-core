# Runtime API Contract

Authority for `src/runtime/engine.zig` and the root `runtime` export.

## Stable Exported Symbols

### Root Module

**runtime**
- Responsibility: expose the host-neutral runtime facade module from `src/root.zig`.
- Breakage: removing or renaming the root export.

### Runtime Module

**Engine**
- Responsibility: compose `Pipeline` and `ScreenState` behind a small host-facing facade.
- Ownership: portable terminal runtime surface for M1 parser-to-screen behavior.
- Breakage: removing or renaming the type; adding host/platform policy; changing public method signatures.

## Stable Engine Methods

**init(allocator, rows, cols) -> !Engine**
- Creates an engine with cursor-only `ScreenState`.
- Breakage: changing parameters, return type, or ownership expectations.

**initWithCells(allocator, rows, cols) -> !Engine**
- Creates an engine with owned cell storage.
- Breakage: changing parameters, return type, allocation ownership, or deinit requirements.

**deinit(self)**
- Releases engine-owned pipeline and screen resources.
- Breakage: changing allocator ownership or resource lifetime behavior.

**feedByte(self, byte)** and **feedSlice(self, bytes)**
- Feed bytes into the underlying parser/pipeline.
- Breakage: changing feed ordering, buffering behavior, or byte interpretation relative to direct `Pipeline` use.

**apply(self)**
- Applies queued events to the owned screen and drains the queue.
- Breakage: not draining, applying more than once per queued event, or changing semantic behavior relative to direct `Pipeline.applyToScreen`.

**clear(self)**
- Drops queued bridge events without applying them to screen.
- Breakage: mutating screen or parser state.

**reset(self)**
- Clears queued events and resets parser state.
- Breakage: preserving partial parser state or mutating screen state.

**resetScreen(self)**
- Resets owned screen state to origin and clears owned cells without changing parser state or queued events.
- Breakage: clearing parser state, dropping queued events, or preserving visible cells/cursor state.

**screen(self) -> *const ScreenState**
- Returns read-only access to current screen state (M1-M2 visible viewport).
- Breakage: returning mutable state, changing lifetime, or returning another state representation.

**queuedEventCount(self) -> usize**
- Returns pending bridge event count.
- Breakage: changing count semantics away from `Pipeline.len`.

**history() const methods (M3)**
- M3 adds const read-only history accessors through `Engine`.
- History read surfaces are defined in `app_architecture/contracts/HISTORY_SELECTION.md`.
- Breakage: exposing mutable history access; changing const lifetime; breaking history API contract.

## Behavioral Guarantees

- `Engine` is a transparent facade over `Pipeline` plus `ScreenState`.
- For equivalent byte streams, direct `Pipeline+ScreenState` and `Engine` produce identical cursor, cell, and queue end states.
- Split-feed chunking does not change final behavior relative to feeding the same bytes as one slice.
- If a split CSI is interrupted by a new escape sequence before its final byte, runtime behavior remains deterministic and stream-order dependent (no retroactive reinterpretation of the interrupted CSI bytes).
- This interruption rule is verified across tabulation CSI (`I`/`Z`), DEC private mode CSI (`?25`/`?7`), absolute-position CSI (`G`/`d`), line-position CSI (`E`/`F`), and relative cursor CSI (`B`/`C`) in replay, parity, and runtime integration tests.
- Alias finals (`e`, `a`, `` ` ``) follow their mapped base-final behavior (`B`, `C`, `G`).
- Ignored-event paths do not mutate screen state through `Engine`.
- Zero-dimension behavior matches `ScreenState` and `Pipeline` contracts.
- `reset()` and `resetScreen()` are intentionally separate: parser/queue reset does not clear screen, and screen reset does not clear parser/queue state.
- `reset()` preserves current screen mode state (`cursor_visible`, `auto_wrap`) while clearing parser and queued events.
- `resetScreen()` restores screen defaults (`cursor_visible=true`, `auto_wrap=true`, origin cursor, cleared owned cells) without clearing parser/queue state.
- `screen()` returns a const reference; M1 does not expose mutable screen access through the runtime facade.

## Non-Goals

- No host GUI, platform, Android, JNI, renderer, process, or app lifecycle ownership.
- No style/color expansion beyond behavior already represented by parser/pipeline/screen contracts.
- No compatibility aliases for alternate method names.
- No mutable screen accessor in M1.

## Breaking Change Rule

A change is breaking if:
1. The root `runtime` export is removed or renamed.
2. `Engine` is removed or renamed.
3. Any stable method is removed, renamed, or changes parameters/return type.
4. Runtime behavior diverges from direct `Pipeline+ScreenState` behavior for the same byte stream.
5. `screen()` exposes mutable state.
6. `clear`, `reset`, `resetScreen`, or `apply` queue/screen semantics change.

## Breaking Change Approval

Required for any breaking change:
- Explicit mention in commit message (`BREAKING: ...`).
- Rationale explaining why the break is necessary.
- Update this contract document.
- Update root API tests and affected replay parity tests.
