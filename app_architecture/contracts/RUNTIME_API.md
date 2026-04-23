# Runtime API Contract

`RUNTIME_API_CONTRACT` — frozen as of M3 milestone completion.

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

**initWithCellsAndHistory(allocator, rows, cols, history_capacity) -> !Engine** (M3+)
- Creates an engine with owned cell storage and bounded history buffer.
- history_capacity: max rows retained when cells exist; 0 = no history.
- Breakage: changing parameters, return type, allocation ownership, or deinit requirements.

**deinit(self)**
- Releases engine-owned pipeline, screen, and history resources.
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

**historyRowAt(history_idx, col) -> u21** (M3+)
- Returns const cell value from history buffer at given history row index and column.
- `history_idx` is recency-ordered: `0` is most recent history row (`-1` in History Selection coordinate model), `1` is next older, etc.
- Returns 0 if history_idx >= historyCount or col >= cols.
- Breakage: changing return type, signature, or exposing mutable access.

**historyCount(self) -> u16** (M3+)
- Returns current number of rows in history buffer (0 to historyCapacity).
- Breakage: changing return type or count semantics.

**historyCapacity(self) -> u16** (M3+)
- Returns max history buffer capacity (0 if no history configured).
- Breakage: changing return type or capacity semantics.

**selectionState(self) -> ?TerminalSelection** (M3+)
- Returns current selection snapshot when active; null if inactive.
- Breakage: changing return type or selection state semantics.

**selectionStart(self, row, col)** (M3+)
- Begin new selection at (row, col) where row is i32 (viewport/history) and col is u16 (viewport).
- Breakage: changing parameter types or start semantics.

**selectionUpdate(self, row, col)** (M3+)
- Update selection end position while active.
- Breakage: changing parameter types or update semantics.

**selectionFinish(self)** (M3+)
- Mark active selection as finished; selection remains accessible until clear().
- Breakage: changing finish semantics.

**selectionClear(self)** (M3+)
- Clear current selection and mark inactive.
- Breakage: changing clear semantics.

## Input Encode Surface (M4+)

**encodeKey(self, key, mod) -> []const u8** (M4+)
- Encode logical key + modifier combination to control byte sequence.
- Returns slice of bytes that would be output to host for this key event.
- Slice is valid only until next call; caller must copy if persistence needed.
- Breakage: changing encoding output for covered key cases, returning mutable slice, adding context-dependent encoding.

**encodeMouse(self, event) -> []const u8** (M4+)
- Current M4 behavior: placeholder surface that returns an empty slice.
- Does not currently read mouse mode state or emit mouse-report sequences.
- Does NOT mutate event, screen, parser, history, or selection state.
- Deterministic: identical input returns identical empty output.
- Breakage: changing placeholder behavior without contract update, returning mutable slice, mutating state.

## Runtime Lifecycle Matrix (M5+)

Unambiguous mutation/read boundaries for all engine method families and interaction invariants.

### Method Groups and State Mutations

| Method Family | Mutates | Reads | Effect on Other Calls |
| --- | --- | --- | --- |
| **Input Feed** | parser, pipeline queue | bytes in | queues events; does not apply to screen |
| `feedByte(byte)` | parser state, bridge queue | single byte | advances parser state, appends event if complete |
| `feedSlice(bytes)` | parser state, bridge queue | byte slice | processes all bytes in sequence, may append multiple events |
| **Queue Management** | pipeline queue | current queue | allows selective event handling |
| `clear()` | bridge queue (empties) | — | drops pending events; screen and parser unchanged |
| **Parser Reset** | parser, pipeline queue | — | clears parser state and bridge queue; screen unchanged |
| `reset()` | parser state, bridge queue | — | resets parser to initial state; preserves screen visible state and modes (cursor_visible, auto_wrap) |
| **Screen Reset** | screen state (cells, cursor, wrap) | screen dimensions, history | clears visible cells and resets cursor to origin; parser and queue unchanged; does not truncate history |
| `resetScreen()` | cell buffer, cursor, wrap state | allocator (owner), history storage | restores screen defaults (cursor_visible=true, auto_wrap=true, origin cursor) |
| **Screen Read** | — | screen state snapshot | const reference; does not change anything |
| `screen()` | — | current ScreenState | returns *const ScreenState for safe inspection |
| **History Reads** | — | history buffer, dimensions | read-only accessors; deterministic and repeatable |
| `historyRowAt(idx, col)` | — | history buffer | returns codepoint or 0; does not mutate |
| `historyCount()` | — | history metadata | returns current rows in buffer (0 to capacity) |
| `historyCapacity()` | — | history metadata | returns max capacity (0 if no history) |
| **Selection Writes** | selection state | input coordinates | mutates SelectionState.active/selecting and endpoints |
| `selectionStart(row, col)` | selection.active, selection.start/end | input (row, col) | begins new selection; marks active=true |
| `selectionUpdate(row, col)` | selection.end | input (row, col) | updates end when active; no-op if inactive |
| `selectionFinish()` | selection.selecting | selection.active | marks selection complete; remains accessible until clear() |
| `selectionClear()` | selection.active, selection.selecting | — | marks selection inactive; endpoint values remain internal state only |
| **Selection Read** | — | selection state | const snapshot; does not change anything |
| `selectionState()` | — | SelectionState | returns ?TerminalSelection (null if inactive) |
| **Encode (Keyboard)** | encode_buf (internal) | key, mod, internal buffer | produces control byte sequence; does not mutate screen/parser/history |
| `encodeKey(key, mod)` | internal encode_buf | input key and modifier | returns slice; valid until next encode call |
| **Encode (Mouse)** | encode_buf (internal) | event, internal buffer | current M4 placeholder: returns empty slice |
| `encodeMouse(event)` | internal encode_buf | input event | returns empty slice until mouse reporting is implemented |

### Interaction Invariants

**Feed → Apply Cycle**
- `feedByte`/`feedSlice` queues events; `apply()` processes queue exactly once and drains it.
- Multiple `apply()` calls without intervening feed see empty queue and do not mutate screen.
- Split-feed chunking is transparent: same bytes fed in chunks or as one slice produce identical end state.

**Clear vs Reset**
- `clear()`: queued events discarded, parser and screen unchanged.
- `reset()`: parser reset to initial state, queued events discarded, screen modes preserved.
- `resetScreen()`: screen state cleared (cells, cursor), parser and queue unchanged.
- Call order: `clear()` + `reset()` + `resetScreen()` produces clean engine (empty parser, empty queue, empty screen).

**Reset Stability for Encode**
- `encodeKey()` and `encodeMouse()` output is independent of `reset()` or `resetScreen()`.
- Encoding before and after reset produces identical output for identical input.

**Selection and History**
- `apply()` may invalidate selection if history rows it references were evicted (M3+ bounded history).
- Selection reads are always const; no mutable selection escape hatch.
- History reads are const; mutations only by `apply()` events during feed/apply cycle.

**State Isolation**
- Input encode functions (`encodeKey`, `encodeMouse`) do not:
  - read or mutate screen/parser/history/selection state
  - call `reset()`, `resetScreen()`, `clear()`, or `apply()`
  - affect subsequent feed/apply/clear operations
- `encodeMouse()` currently returns an empty slice and is kept as a stable placeholder API.
- Selection operations do not affect feed/apply/reset cycles.
- History read does not affect selection or feed/apply state.

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
