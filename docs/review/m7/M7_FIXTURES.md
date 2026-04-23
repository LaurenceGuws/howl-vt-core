# M7 Benchmark Fixtures

This document defines canonical byte-stream fixtures for `M7` measurements.

These fixtures exist so baseline and post-change measurements use identical
inputs and cannot drift across sessions.

## Fixture Rules

- fixtures are terminal input bytes only
- fixtures must be deterministic and seed-free
- fixtures must be reusable from both runtime and direct modes
- fixture content may evolve only through explicit architect update

## F_ASCII_HEAVY_V1

Purpose:

- measure text-dominant throughput and allocation pressure in parser/bridge/apply

Shape:

- 10,000 lines
- each line: 64 printable ASCII bytes + `\r\n`
- no CSI escapes

Representative line pattern:

```text
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
```

## F_CSI_HEAVY_V1

Purpose:

- measure control/CSI parsing and semantic apply overhead under style/cursor load

Shape:

- repeat 2,000 blocks
- each block includes cursor movement, erase, and style toggles

Representative block pattern:

```text
\x1b[H\x1b[2J\x1b[31mHELLO\x1b[0m\x1b[5C\x1b[2K\x1b[1;1H
```

## F_SCROLL_HEAVY_V1

Purpose:

- measure scroll-path cost with and without history enabled

Shape:

- 20,000 newline-producing writes sized to overflow viewport repeatedly
- line body kept short to emphasize scroll frequency

Representative pattern:

```text
X\r\n
```

Measurement requirement:

- run once with history capacity `0`
- run once with history capacity `>0` (recommended `1000`)

## F_MIXED_INTERACTIVE_V1

Purpose:

- measure feed/apply latency for small interactive bursts

Shape:

- 5,000 iterations
- each iteration feeds one short chunk then applies immediately
- mix plain text and cursor/control bytes

Representative burst sequence:

```text
abc
\x1b[D
\x1b[C
\r
```

## F_SNAPSHOT_OPT_IN_V1

Purpose:

- measure snapshot capture cost separately from steady-state runtime loop

Shape:

- preload viewport + history using `F_SCROLL_HEAVY_V1`
- call snapshot at fixed intervals (e.g., every 100 apply cycles)

Measurement requirement:

- report snapshot latency and allocation deltas independently
- do not combine with hot-loop throughput score

## F_QUEUE_GROWTH_V1

Purpose:

- characterize queue-depth and peak-live memory pressure before `apply`
- provide stable stress fixtures for `F2` policy and implementation work

Shape:

- `queue_growth_ascii_chunked_64`: `F_ASCII_HEAVY_V1` fed in 64-byte chunks,
  with a single `apply` at the end
- `queue_growth_scroll_chunked_16`: `F_SCROLL_HEAVY_V1` fed in 16-byte chunks,
  with a single `apply` at the end

Measurement requirement:

- report `median_max_queue_depth`
- report `median_peak_live_bytes`
- report existing latency/allocation/throughput metrics for context

## Versioning Rule

Fixture IDs are versioned (`*_V1`, `*_V2`, ...).

If fixture content changes:

- publish new fixture ID
- keep old IDs for historical comparison
- never relabel new content with an existing ID
