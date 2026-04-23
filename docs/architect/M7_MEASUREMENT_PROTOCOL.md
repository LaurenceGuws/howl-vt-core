# M7 Measurement Protocol

This protocol defines how `M7` performance and memory evidence is produced.

It exists to prevent benchmark theater and ensure every claimed win is
reproducible, comparable, and tied to a real `howl-terminal` cost surface.

## Scope

This protocol applies to all `M7` performance/memory claims, including:

- architect audit measurements
- optimization proposal baselines
- post-change evidence for acceptance

## Metric Classes

All `M7` evidence must use at least one of these classes:

1. latency: time from `feed*` to completed `apply`
2. throughput: bytes processed per second for representative streams
3. allocation pressure: allocation count and allocated bytes in hot paths
4. retained memory: owned state size at steady state for configured dimensions

## Workload Families

Each measured change must run against one or more workload families:

- `ascii_heavy`: mostly printable ASCII text with line feeds
- `csi_heavy`: cursor/style/control dense streams
- `scroll_heavy`: sustained bottom-row scrolling with history enabled
- `mixed_interactive`: short bursts of text/control with frequent `apply`
- `snapshot_opt_in`: explicit snapshot capture cost (not part of hot-loop score)

Canonical fixture definitions are in:

- `docs/architect/M7_FIXTURES.md`

## Measurement Modes

Two measurement modes are allowed:

- `runtime_mode`: measure through `runtime.Engine` (`feed*`, `apply`, reads)
- `direct_mode`: measure direct parser/pipeline/screen flow for parity insight

`runtime_mode` is required for acceptance. `direct_mode` is optional diagnostic
support when isolating hotspots.

## Run Discipline

Every reported result must follow this discipline:

1. same machine for baseline and post-change runs
2. no debug logging or extra probes beyond the measurement instrumentation
3. warm-up phase before timed phase
4. at least 10 timed iterations per workload
5. report median and p95, not only best run
6. report bytes processed and event count alongside timing numbers

If run-to-run variance exceeds 10% for median latency or throughput, evidence is
not acceptable until variance is reduced or explained.

## Required Output Per Claim

Each optimization claim must report:

- workload family
- mode (`runtime_mode` or `direct_mode`)
- configured dimensions (`rows`, `cols`, `history_capacity`)
- baseline median + p95
- post-change median + p95
- percent delta
- allocation count delta
- allocated-bytes delta
- retained-memory delta (if applicable)

## Memory Accounting Rules

Memory reporting must distinguish:

- configured retained memory (cells/history/snapshot ownership)
- transient allocation traffic during workload execution
- peak retained memory after workload completes

Claims that mix retained and transient memory in one number are invalid.

## Acceptance Rules

A change is `M7`-acceptable only if all are true:

- preserves frozen `M1-M6` behavior
- improves at least one declared metric class on at least one declared workload
- does not cause a major regression (>5%) in higher-priority doctrine goals
- does not weaken ownership or boundedness clarity

If a change improves throughput but worsens latency or memory bounds beyond the
threshold above, it is rejected unless doctrine is explicitly amended.

## Anti-Gaming Rules

The following are invalid evidence patterns:

- suppressing real apply behavior to inflate parser-only throughput while
  claiming end-to-end wins
- changing workload definitions between baseline and post-change runs
- reporting only best-case runs
- omitting allocation deltas for allocation-targeted work
- claiming wins from semantic behavior changes

## Reporting Template

Every M7 performance section should use this shape:

```text
Target finding: F*
Workload: <family>
Mode: <runtime_mode|direct_mode>
Config: rows=<r>, cols=<c>, history=<h>
Baseline: median=<x>, p95=<y>, bytes/s=<z>, allocs=<a>, alloc_bytes=<b>
Post-change: median=<x2>, p95=<y2>, bytes/s=<z2>, allocs=<a2>, alloc_bytes=<b2>
Delta: latency=<..%>, throughput=<..%>, allocs=<..%>, alloc_bytes=<..%>
Behavior check: M1-M6 parity/tests unchanged (yes/no)
```

## Current M7 Baseline Requirement

Before publishing any engineer implementation queue for `M7`, architect work
must publish at least one reproducible baseline for:

- `ascii_heavy` in `runtime_mode`
- `csi_heavy` in `runtime_mode`
- `scroll_heavy` in `runtime_mode` with history enabled
- allocation pressure for bridge/event queue path

Until those baselines exist, `M7` remains architect-only.
