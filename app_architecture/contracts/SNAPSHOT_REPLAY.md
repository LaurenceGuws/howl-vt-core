# Snapshot and Replay Contract

`SNAPSHOT_REPLAY_CONTRACT` — active authority for M6 snapshot/replay semantics.

Authority for snapshot capture, replay framing, and deterministic parity between
snapshots obtained from direct byte streams and runtime engine state.

## Core Definitions

### Snapshot

A snapshot is a deterministic, read-only capture of engine observable state at a
point in time. Snapshots are host-neutral and do not encode persistence format,
file layout, or cross-version compatibility.

**Snapshot Payload:**

A snapshot captures the following observable engine state:

- **Screen cells**: visible cell buffer (same as `Engine.screen()` cell contents).
- **Cursor position**: (row, col) in viewport coordinates (same as `Engine.screen().cursor_row` and `Engine.screen().cursor_col`).
- **Cursor visibility**: `cursor_visible` mode state.
- **Auto-wrap mode**: `auto_wrap` mode state.
- **History buffer**: all retained history rows in recency order (most recent first, matching `historyRowAt(0)` semantics).
- **History count**: current number of rows in history buffer (same as `Engine.historyCount()`).
- **Selection state**: active selection or null if inactive; endpoints use signed row/column coordinate model.

**Snapshot NOT Captured:**

- Parser internal state (CSI/escape sequence parse state, parameter buffers).
- Queued bridge events (Engine.queuedEventCount() state).
- Encode buffer state (encodeKey/encodeMouse internal buffers).
- Persistence format or file encoding (snapshots are opaque data structures).

### Replay

Replay is the process of reconstructing an engine snapshot by feeding a byte
sequence into an engine initialized to a known start state, then applying queued
events to screen, and capturing the final observable state.

**Replay Framing:**

A replay operation consists of ordered phases:

1. **Engine init**: create Engine with known dimensions (rows, cols), optionally with history capacity.
2. **Feed phase**: feed zero or more bytes via `feedByte()` or `feedSlice()`.
3. **Apply phase**: call `apply()` exactly once to process all queued events.
4. **Snapshot capture**: capture final engine observable state via snapshot API.

Each replay operation completes one complete feed/apply cycle. Multiple feed calls
may be made in the feed phase before a single apply call.

**Split-Feed Invariant:**

If a sequence of bytes B is split into chunks B1, B2, ..., Bn, then:

```
feed(B1); feed(B2); ... feed(Bn); apply();
```

produces an identical final snapshot to:

```
feed(B); apply();
```

This invariant holds regardless of chunk boundaries or chunk count. Split-feed
chunking is transparent to observable end state.

## Snapshot Capture Determinism

**Determinism Claim:**

Given an engine state after a complete feed/apply cycle, a snapshot captured at
that point is deterministic: identical observable state always produces identical
snapshot contents.

**Implications:**

- Two engines with identical visible cells, cursor, modes, history, and selection
  state produce identical snapshots.
- Snapshots depend only on observable state, not on parse state, queued events, or
  prior history of engine operations.
- A snapshot is reproducible: replaying the same byte sequence produces a snapshot
  with identical observable contents.

## Replay Parity Invariants

**Direct vs Runtime Parity:**

For any byte sequence B and starting dimensions:

```
snapshot_direct = DirectPipeline.feed(B).screen_snapshot
snapshot_runtime = Engine.init().feed(B).apply().snapshot()
```

The observable screen state (cells, cursor, modes) in both snapshots is identical.
Explicit test coverage validates this parity across representative byte sequences.

**History and Selection Parity:**

When history is enabled:

- Replaying the same byte sequence via Engine produces identical history buffer
  contents (same row count and cell values in recency order).
- Selection state parity is validated where selection inputs are explicitly driven
  through equivalent harness actions; direct parser/pipeline byte replay alone does
  not imply selection lifecycle parity.

**Chunked Replay Parity:**

Feeding the same bytes in different chunk sizes produces identical final snapshots.
Explicit test coverage validates this for:

- Single-byte feeds vs multi-byte feeds
- Split CSI sequences vs complete CSI sequences
- History-producing sequences (scrollback) fed in various chunk patterns

## Reset and Clear Boundaries

**Snapshot-relevant Reset Behavior:**

- `clear()`: discards queued events but does not change visible screen, cursor, modes, history, or selection. Snapshot before and after clear() is identical.
- `reset()`: clears parser and queued events, preserves screen visible state and modes. Snapshot before and after reset() contains identical visible cells, cursor, and mode state.
- `resetScreen()`: clears visible cells and cursor, resets modes to defaults (cursor_visible=true, auto_wrap=true, origin cursor). Does not change history or parser. Snapshot after resetScreen() reflects cleared cells and reset cursor/modes but preserves history.

**Snapshot Boundary Rules:**

After a reset sequence (clear → reset → resetScreen), the resulting snapshot reflects:
- Clean screen state (cells cleared, cursor at origin)
- Clean parser state (no pending parse operations)
- Clean queue (no queued events)
- Preserved history (reset operations do not truncate history)
- Preserved selection across reset operations; selection is invalidated to inactive
  state when history eviction removes referenced rows (per M3 contract).

## Coordinate Semantics in Snapshots

Snapshots use the coordinate system defined in HISTORY_SELECTION.md:

- **Viewport row**: non-negative (0 to rows-1), references visible screen row.
- **History row**: negative (-1, -2, ..., -(historyCount)), references history in
  recency order.
- **Column**: unsigned (0 to cols-1).

Selection endpoints captured in snapshot use this signed row coordinate model.
Snapshot API must not reinterpret or transform coordinates.

## Non-Goals

Snapshot/replay contract does NOT cover:

- **Persistence format**: JSON, binary, protobuf encoding of snapshots is out of
  scope; contract is about observable contents, not wire format.
- **Cross-version compatibility**: snapshots from one version of howl-terminal
  are not guaranteed to replay identically in another version.
- **Snapshot restore/mutation**: no API to restore screen from snapshot or mutate
  snapshot contents. M6 provides snapshot capture only.
- **Host/platform integration**: no snapshot transport, storage, serialization,
  network protocol, file format, or rendering integration. Snapshots are
  host-neutral data structures.
- **Performance optimization**: no snapshot streaming, incremental capture, or
  delta encoding. M6 captures full observable state per snapshot request.

## Breakage Rules

A change breaks the snapshot/replay contract if any of:

1. **Snapshot payload semantic change**: observable screen state, cursor position,
   modes, history, or selection semantics diverge from runtime observable state.
2. **Replay parity violation**: identical byte sequences fed to Engine and direct
   pipeline produce different observable end states.
3. **Split-feed invariant violation**: chunked vs atomic feed produces different
   observable end states.
4. **Coordinate reinterpretation**: snapshot/replay changes row coordinate
   semantics (signed vs unsigned, history ordering, boundary handling).
5. **History/selection snapshot loss**: snapshot no longer captures history rows,
   selection state, or mode state.

## Relationship to M1-M5 Contracts

M6 snapshot/replay contract is an additive read-only layer over M1-M5 behavior:

- **M1 parser/pipeline**: snapshot capture does not modify parser/pipeline
  semantics; frozen M1-M2 visible screen determinism is unchanged.
- **M3 history/selection**: snapshot captures M3 history and selection as
  observable state; frozen M3 semantics are unchanged.
- **M4 input/control**: snapshot does not encode input state; input encode
  determinism (frozen M4) is unchanged.
- **M5 runtime lifecycle**: snapshot is consistent with M5 runtime mutation
  boundaries; engine lifecycle (clear/reset/resetScreen) is unchanged.

No snapshot/replay requirement forces modification of M1-M5 frozen semantics.
