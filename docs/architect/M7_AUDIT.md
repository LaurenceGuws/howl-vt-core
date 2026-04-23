# M7 Architect Audit

This document records the initial architect audit for `M7`.

It is not an implementation queue. It defines where performance and memory
pressure actually live in the current codebase so future `M7` work can be
measured and scoped against reality.

## Audit Baseline

Audited surfaces:

- `src/parser/parser.zig`
- `src/parser/stream.zig`
- `src/parser/csi.zig`
- `src/event/bridge.zig`
- `src/event/pipeline.zig`
- `src/screen/state.zig`
- `src/runtime/engine.zig`
- `src/model/snapshot.zig`

Frozen contract floor:

- `M1-M6` semantics remain unchanged.
- `M7` may improve cost, allocation behavior, and measurement clarity.
- `M7` may not change observable behavior to win benchmarks.

## Findings

### F1: Bridge text ownership is the highest obvious hot-path allocation source

Relevant code:

- [bridge.zig](/home/home/personal/projects/howl/howl-terminal/src/event/bridge.zig:98)
- [bridge.zig](/home/home/personal/projects/howl/howl-terminal/src/event/bridge.zig:100)
- [bridge.zig](/home/home/personal/projects/howl/howl-terminal/src/event/bridge.zig:101)

Current behavior:

- every ASCII slice emitted by the parser is duplicated with `allocator.dupe`
  before being queued as a bridge event.
- that duplicated slice is later freed in `clear()`.

Why it matters:

- this turns ordinary text throughput into allocator traffic.
- cost grows with event count before `apply()`, not just with visible state size.
- it attacks both throughput and latency because allocation sits directly on the
  parser-to-queue path.

Architect assessment:

- this is the first-place candidate for `M7` implementation work.
- any redesign here must preserve deterministic event boundaries or replace them
  with an equally explicit contract.

### F2: Queue growth before apply is bounded only by input behavior, not by an explicit contract

Relevant code:

- [pipeline.zig](/home/home/personal/projects/howl/howl-terminal/src/event/pipeline.zig:67)
- [bridge.zig](/home/home/personal/projects/howl/howl-terminal/src/event/bridge.zig:31)
- [bridge.zig](/home/home/personal/projects/howl/howl-terminal/src/event/bridge.zig:95)

Current behavior:

- `feedByte` and `feedSlice` append events into a retained `ArrayList`.
- the queue is drained only by `apply()` or discarded by `clear()` / `reset()`.

Why it matters:

- this is structurally safe but not yet governed by a memory-discipline rule.
- a host that batches large feeds before `apply()` can grow the queue far beyond
  the visible screen footprint.

Architect assessment:

- `M7` needs an explicit doctrine answer here: either this remains accepted with
  documented ownership/bounds assumptions, or the runtime path gains stronger
  boundedness rules.
- this is a policy and measurement problem before it is a code problem.

### F3: Scroll cost is deterministic but linear in visible screen size per bottom-row scroll

Relevant code:

- [state.zig](/home/home/personal/projects/howl/howl-terminal/src/screen/state.zig:311)
- [state.zig](/home/home/personal/projects/howl/howl-terminal/src/screen/state.zig:317)
- [state.zig](/home/home/personal/projects/howl/howl-terminal/src/screen/state.zig:325)

Current behavior:

- bottom-row scroll copies the outgoing top row into history.
- then shifts the entire visible cell buffer upward with `copyForwards`.
- then clears the final row.

Why it matters:

- this is simple and correct, but it makes scroll-heavy workloads scale with
  `rows * cols`.
- it is likely to dominate throughput for history-producing streams once parser
  and queue costs are reduced.

Architect assessment:

- this is a valid `M7` target, but it is second-wave work.
- any optimization here must preserve the visible buffer contract, history
  semantics, and selection invalidation behavior.

### F4: Snapshot capture is explicitly expensive and should stay opt-in

Relevant code:

- [snapshot.zig](/home/home/personal/projects/howl/howl-terminal/src/model/snapshot.zig:97)
- [snapshot.zig](/home/home/personal/projects/howl/howl-terminal/src/model/snapshot.zig:108)
- [engine.zig](/home/home/personal/projects/howl/howl-terminal/src/runtime/engine.zig:533)

Current behavior:

- `snapshot()` allocates and copies the full visible cell buffer and full
  history buffer.

Why it matters:

- this is not a hot interactive path unless a host abuses it.
- it is intentionally expensive because the contract promises an owned,
  deterministic snapshot.

Architect assessment:

- snapshot cost should be measured and documented, not prematurely optimized.
- `M7` should treat snapshot as an explicit diagnostic/read surface, not as a
  throughput primitive.

### F5: Parser CSI and stream logic are already allocation-free on the main path

Relevant code:

- [stream.zig](/home/home/personal/projects/howl/howl-terminal/src/parser/stream.zig:20)
- [csi.zig](/home/home/personal/projects/howl/howl-terminal/src/parser/csi.zig:27)
- [parser.zig](/home/home/personal/projects/howl/howl-terminal/src/parser/parser.zig:167)

Current behavior:

- stream classification is stack/state based.
- CSI parsing uses fixed arrays and no allocator traffic per parsed sequence.

Why it matters:

- this means parser-core performance pressure is less urgent than queue and
  buffer-ownership pressure for ordinary workloads.
- it also means M7 should not waste time "optimizing the parser" before
  measuring queue/screen costs.

Architect assessment:

- parser-core is not the first bottleneck candidate from static inspection.
- prove otherwise with measurements before spending M7 budget there.

### F6: OSC/APC/DCS buffers retain capacity and are bounded only by input shape

Relevant code:

- [parser.zig](/home/home/personal/projects/howl/howl-terminal/src/parser/parser.zig:124)
- [parser.zig](/home/home/personal/projects/howl/howl-terminal/src/parser/parser.zig:312)
- [parser.zig](/home/home/personal/projects/howl/howl-terminal/src/parser/parser.zig:351)
- [parser.zig](/home/home/personal/projects/howl/howl-terminal/src/parser/parser.zig:383)

Current behavior:

- parser allocates side-channel buffers with initial capacity `256`.
- those buffers grow with incoming payload size and are cleared with retained
  capacity on reset/reuse.

Why it matters:

- this is not likely the dominant ordinary-terminal cost.
- it is still a memory-discipline issue because one large payload can ratchet
  retained capacity upward.

Architect assessment:

- this belongs in the M7 memory audit.
- it is likely lower priority than bridge text duplication and queue behavior,
  but it needs an explicit doctrine answer.

## Ranked Priority Order

Current architect ranking:

1. bridge text duplication and queue ownership cost
2. queue growth policy before `apply()`
3. scroll-path visible buffer movement cost
4. retained side-channel parser buffer capacity
5. snapshot cost characterization
6. parser-core micro-optimization only if measurements justify it

## Measurement Surfaces To Build Next

Before any optimization slice, `M7` should add reproducible measurements for:

- bytes fed per second through parser + bridge with rendering/application active
- latency of `feedSlice -> apply` for small interactive text/control payloads
- allocation count and total allocated bytes for representative text-heavy feeds
- allocation count and total allocated bytes for CSI-heavy feeds
- scroll-heavy workload cost with history enabled vs disabled
- snapshot call cost as a separate, opt-in measurement

## Implementation Gate For Future M7 Code

No implementation ticket should be published until it names:

- the exact finding it addresses (`F1`, `F2`, etc.)
- the exact files it may touch
- which measurement surface will prove success
- which `M1-M6` contracts must remain frozen

## Current Recommendation

Do not publish an engineer queue yet.

Next architect work should be:

1. define the local measurement protocol and benchmark fixtures
2. decide the doctrine for acceptable queue growth before `apply()`
3. decide whether bridge text ownership should remain per-event duplication or
   be replaced by a more bounded representation
