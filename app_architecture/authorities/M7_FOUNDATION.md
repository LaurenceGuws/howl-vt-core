# M7 Performance and Memory Discipline Foundation

`M7_FOUNDATION` is architect-owned authority for `M7`.

`M7` is not an engineer execution lane yet. It is the doctrine phase for
deciding what "fast", "smooth", and "bounded" mean for `howl-terminal`, how
they will be measured, and which tradeoffs are acceptable before any
optimization campaign starts.

## Start Point (Locked Baseline)

`M7` starts from frozen `M1-M6` behavior:

- parser, event, screen, history, selection, input, runtime, and snapshot
  contracts are frozen.
- replay/parity evidence through `M6` is the correctness floor.
- current code is allowed to be suboptimal, but not ambiguous about behavior.

Current gap:

- the repo has no performance doctrine defining primary metrics, bounded memory
  rules, measurement protocol, or optimization review bar.

## End Point (M7 Done)

`M7` is done only when all are true:

- performance goals are explicit and ranked.
- bounded allocation rules are explicit for hot paths and long-lived surfaces.
- measurement protocol is reproducible and trusted.
- implementation changes are justified by doctrine and evidence, not intuition.
- performance work lands without reopening frozen `M1-M6` semantics.

## Product Doctrine

### Primary Goal Order

Optimization priority for `howl-terminal` is:

1. user-perceived responsiveness
2. deterministic smoothness under continuous updates
3. bounded memory and allocation discipline
4. sustained throughput under realistic terminal streams
5. CPU efficiency as a constraint, not an excuse for sluggish interaction

If two goals conflict, earlier items win unless `M7` authority explicitly says
otherwise.

### What "Fast" Means Here

`M7` does not optimize abstract benchmark scores in isolation.

The engine is considered fast only if it improves one or more of:

- feed-to-apply latency for interactive input-sized updates
- stability of frame-to-frame work under scroll/update pressure
- throughput for representative terminal byte streams
- allocation count and allocation volume on runtime-critical paths
- steady-state memory bounds for configured screen/history sizes

### What "Bounded" Means Here

`howl-terminal` is an embedded-style engine, not a "grow first, rationalize
later" runtime.

For `M7`, bounded means:

- ownership is explicit
- lifetime is explicit
- maximum retained memory is explainable from configuration
- hot paths avoid allocator traffic unless contractually justified
- no hidden queues, caches, or growth surfaces are introduced without authority

## Scope (Architect-Only)

`M7` currently includes:

- defining optimization philosophy and tradeoff order
- defining reproducible measurement protocol
- identifying hot paths and allocation surfaces worth caring about
- defining acceptance gates for future implementation work
- deciding which evidence is required before any engineer execution queue exists

`M7` currently excludes:

- implementation work delegated to engineers
- opportunistic micro-optimizations
- benchmark-only churn
- host-specific render loop policy
- speculative concurrency or buffering changes

## Required Measurement Surfaces

Any future `M7` implementation slice must tie back to one or more of these:

- parser throughput for representative ASCII, UTF-8 text, and CSI-heavy streams
- runtime `feed* -> apply` latency for small interactive updates
- scroll/update stability under history-producing streams
- snapshot overhead, including allocation and copy cost
- allocation count and bytes allocated along hot runtime paths
- configured memory footprint for screen, history, snapshot, and selection state

Measurement procedure, workload definitions, and reporting format are defined
in:

- `docs/review/m7/M7_MEASUREMENT_PROTOCOL.md`

## Evidence Standard

No optimization work is accepted on style or intuition alone.

Every future `M7` implementation proposal must state:

- which measurement surface it targets
- what the current cost is
- what the expected gain is
- what semantic surfaces must remain unchanged
- what new bound, if any, becomes stronger after the change

Evidence must be reproducible on local developer machines with repo-local tools
or simple documented commands. If evidence cannot be rerun, it is not authority.

## Doctrine Decisions (Current)

### D1: Queue Growth Is Allowed Between `feed*` and `apply`, But Must Be Measured

Current runtime contract remains two-phase: input is queued during `feed*`, and
state mutates on `apply`.

For `M7`, this means:

- no semantic shortcut that mutates screen state directly from `feed*`
- queue growth is currently allowed as a contract property
- memory and allocation pressure from queue growth must be explicitly measured
- if bounded queue semantics are later proposed, they require explicit contract
  review, not incidental optimization

### D2: Bridge Text Ownership Is A Primary Optimization Target

Per-event text duplication in the bridge is currently accepted behavior but is
treated as the first high-impact `M7` optimization target.

For `M7`, this means:

- changes may redesign internal ownership to reduce allocator traffic
- deterministic parser-to-semantic behavior must remain unchanged
- improvements are accepted only with runtime-mode evidence and parity safety

### D3: Snapshot Cost Is Explicitly Opt-In

Snapshot capture is allowed to be expensive because it is a deterministic,
owned-state diagnostic surface.

For `M7`, this means:

- snapshot performance is measured separately from hot-loop throughput
- snapshot optimization does not outrank interactive latency or queue/scroll
  pressure work

### D4: Queue Envelope Must Be Reported Explicitly

Queue growth remains contractually allowed between `feed*` and `apply`, but
`M7` now requires explicit queue-envelope reporting in baseline/evidence runs.

For `M7`, this means:

- queue-focused runs must report max queue depth and peak live bytes
- queue policy/mitigation changes are governed by `M7_F2_SPEC`
- no queue behavior change is accepted without `M7-BL-003` comparison evidence

### D5: Scroll Optimization Is Allowed Only With Full Observable Parity

Scroll-path improvements are in-scope for `M7`, but only if they preserve
visible output, history ordering, and snapshot parity.

For `M7`, this means:

- scroll optimization work is governed by `M7_F3_SPEC`
- internal representation changes are allowed
- contract-visible behavior changes are not allowed

## Non-Goals

`M7` is not:

- a renderer benchmark contest
- a host GUI latency project
- a justification for semantic shortcuts
- a place to add fallback code paths, compatibility branches, or hidden caches
- a permission slip for "temporary" allocation-heavy designs

## Stop Conditions

Stop and escalate if any occur:

- a proposed optimization changes frozen `M1-M6` behavior instead of preserving
  it
- the only way to improve a metric is to blur an existing contract boundary
- a benchmark result cannot be tied to a real product measurement surface
- measurement protocol depends on ad hoc local setup that others cannot repeat

## M7 Phases

### M7-A: Architect Doctrine Closure

- finalize success metric ordering
- define memory discipline vocabulary and rules
- define trusted benchmark and profiling protocol
- define what future engineer slices are allowed to touch

Exit check:

- one architect can hand the doctrine to another without oral context

### M7-B: Architect Audit

- inspect hot paths and allocation sites across parser, event, screen, runtime,
  and snapshot surfaces
- classify each as acceptable, suspicious, or must-fix
- rank work by user impact first, implementation neatness second

Exit check:

- audited findings exist with a reviewable shortlist of real targets

### M7-C: Implementation Queue Publication

- only after `M7-A` and `M7-B` are complete
- publish narrowly-scoped implementation tickets with explicit files, non-goals,
  validation, and stop conditions

Exit check:

- engineer work, if any, is bounded by doctrine and audit rather than discovery

### M7-D: Freeze

- freeze doctrine, findings, and accepted implementation evidence
- update milestone state for the next milestone handoff

Exit check:

- `M7` can be cited as stable authority for future host-readiness work

## Review Bar

`M7` review is stricter than normal feature review.

Changes under `M7` must be judged on:

- correctness preservation
- measurable effect on a declared target
- whether the new memory/ownership story is simpler, not merely faster
- whether the result makes the engine easier to reason about under load

## Validation Baseline

Every `M7` slice, including doctrine-only updates, must still pass:

- `zig build`
- `zig build test`
- `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src`
