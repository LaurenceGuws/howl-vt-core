# M7 Baseline Evidence

Baseline ID: `M7-BL-001`

This document records the first protocol-aligned `M7` baseline run.

## Environment

- Timestamp (UTC): `2026-04-23 18:33:17Z`
- OS: `Linux 6.19.12-arch1-1 x86_64 GNU/Linux`
- CPU: `AMD Ryzen 5 8400F 6-Core Processor`
- Zig: `0.15.2`
- Command: `zig build m7-baseline`

## Protocol and Fixture Anchors

- Protocol: `docs/review/m7/M7_MEASUREMENT_PROTOCOL.md`
- Fixtures: `docs/review/m7/M7_FIXTURES.md`
- Mode: runtime mode (`runtime.Engine`)
- Config: `rows=40`, `cols=120`, `runs=10`

## Results

| Workload | Bytes/Run | Median (ms) | P95 (ms) | Throughput (MiB/s) | Median alloc count | Median alloc bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ascii_heavy` | 660000 | 123.498 | 126.427 | 5.10 | 10000 | 3294160 |
| `csi_heavy` | 70000 | 35.214 | 35.741 | 1.90 | 2000 | 1778560 |
| `scroll_heavy_history0` | 60000 | 207.411 | 210.436 | 0.28 | 20000 | 5995200 |
| `scroll_heavy_history1000` | 60000 | 212.906 | 220.249 | 0.27 | 20000 | 5995200 |
| `mixed_interactive` | 50000 | 32.999 | 40.376 | 1.45 | 5000 | 15000 |
| `snapshot_opt_in` | 200 snapshots | 36.131 | 36.663 | n/a | 400 | 99840000 |

## Initial Interpretation

- `ascii_heavy`, `csi_heavy`, and both `scroll_heavy` variants confirm high
  allocation/event pressure in runtime hot loop, consistent with audit finding
  `F1` (bridge text duplication and queue ownership cost).
- `scroll_heavy_history1000` is slightly slower than `history0`, but both remain
  dominated by large event/scroll volume; history-enabled overhead exists but is
  not the primary pressure source from this baseline alone.
- `snapshot_opt_in` shows high allocation bytes by design and remains an
  explicitly opt-in measurement surface (`D3`).

## Next Architect Action

Use `M7-BL-001` as the frozen pre-change baseline for the first M7 optimization
proposal targeting `F1` (bridge ownership/allocation pressure), with no semantic
changes to frozen `M1-M6` behavior.

---

## M7-BL-002 (Post-F1)

Baseline ID: `M7-BL-002`

Timestamp (UTC): `2026-04-23 18:53:18Z`

Command:

- `zig build m7-baseline`

### Results

| Workload | Bytes/Run | Median (ms) | P95 (ms) | Throughput (MiB/s) | Median alloc count | Median alloc bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ascii_heavy` | 660000 | 72.504 | 75.000 | 8.68 | 1 | 3294176 |
| `csi_heavy` | 70000 | 24.632 | 25.075 | 2.71 | 1 | 1778576 |
| `scroll_heavy_history0` | 60000 | 106.334 | 108.785 | 0.54 | 1 | 5995216 |
| `scroll_heavy_history1000` | 60000 | 116.801 | 121.516 | 0.49 | 4 | 6024374 |
| `mixed_interactive` | 50000 | 6.481 | 7.077 | 7.36 | 1 | 54 |
| `snapshot_opt_in` | 200 snapshots | 36.437 | 38.231 | n/a | 400 | 99840000 |

### Delta vs M7-BL-001

| Workload | Median latency delta | Throughput delta | Alloc count delta | Alloc bytes delta |
| --- | ---: | ---: | ---: | ---: |
| `ascii_heavy` | -41.29% | +70.20% | -99.99% | +0.00% |
| `csi_heavy` | -30.05% | +42.63% | -99.95% | +0.00% |
| `scroll_heavy_history0` | -48.73% | +92.86% | -100.00% | +0.00% |
| `scroll_heavy_history1000` | -45.14% | +81.48% | -99.98% | +0.49% |
| `mixed_interactive` | -80.36% | +407.59% | -99.98% | -99.64% |
| `snapshot_opt_in` | +0.85% | n/a | +0.00% | +0.00% |

### F1 Spec Gate Evaluation (`M7-F1-SPEC-001`)

1. Allocation reduction (`ascii_heavy` alloc count >=25% reduction): `PASS`
2. Allocation bytes (`ascii_heavy` alloc bytes >=20% reduction): `FAIL`
3. Stability (`mixed_interactive` median latency regression <=5%): `PASS`
4. Throughput (`ascii_heavy` throughput regression <=3%): `PASS`
5. Correctness (`zig build test`): `PASS`

Architect note:

- F1 objective (allocator pressure reduction) succeeded strongly on allocation
  count and runtime latency/throughput.
- Allocation bytes remained effectively unchanged for text-heavy streams because
  payload byte volume is still materialized; ownership moved from per-event heap
  allocations to arena-backed allocations.
- To treat this slice as accepted, gate 2 requires explicit architect waiver or
  a follow-up `F1R` slice focused on reducing total allocated bytes rather than
  allocation count.

---

## M7-BL-003 (F2 Queue Envelope Baseline)

Baseline ID: `M7-BL-003`

Timestamp (UTC): `2026-04-23 19:35:25Z`

Command:

- `zig build m7-baseline`

### Results

| Workload | Median (ms) | P95 (ms) | Throughput (MiB/s) | Median alloc count | Median alloc bytes | Median peak live bytes | Median max queue depth |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `ascii_heavy` | 72.457 | 73.494 | 8.69 | 1 | 3294176 | 3294176 | 30000 |
| `csi_heavy` | 24.991 | 25.406 | 2.67 | 1 | 1778576 | 1778576 | 16000 |
| `scroll_heavy_history0` | 104.286 | 107.218 | 0.55 | 4 | 6024374 | 6003867 | 60000 |
| `scroll_heavy_history1000` | 103.900 | 104.822 | 0.55 | 4 | 6024374 | 6003867 | 60000 |
| `mixed_interactive` | 7.022 | 7.040 | 6.79 | 1 | 54 | 54 | 4 |
| `snapshot_opt_in` | 35.968 | 36.169 | n/a | 400 | 99840000 | 499200 | 0 |
| `queue_growth_ascii_chunked_64` | 77.135 | 78.115 | 8.16 | 8 | 5309084 | 4649824 | 39687 |
| `queue_growth_scroll_chunked_16` | 105.852 | 107.263 | 0.54 | 4 | 6024374 | 6003867 | 60000 |

### F2 Baseline Interpretation

- Queue depth is substantial in sustained pre-apply buffering scenarios.
- `queue_growth_ascii_chunked_64` shows queue-depth expansion beyond the single
  feed `ascii_heavy` shape (39,687 vs 30,000 median max queue depth), confirming
  chunking pattern affects queue profile.
- Scroll-heavy workloads naturally push queue depth to 60,000 under current
  fixture/load shape, establishing a high-water reference for F2 policy work.
- F2 can now be evaluated with explicit queue-depth and peak-live metrics,
  rather than only latency/throughput/allocation counts.

---

## M7-BL-004 (F2B Post-Implementation)

Baseline ID: `M7-BL-004`

Timestamp (UTC): `2026-04-23 19:50:29Z`

Command:

- `zig build m7-baseline`

### Results

| Workload | Median (ms) | P95 (ms) | Throughput (MiB/s) | Median alloc count | Median alloc bytes | Median peak live bytes | Median max queue depth |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `ascii_heavy` | 72.696 | 73.624 | 8.66 | 1 | 3294176 | 3294176 | 30000 |
| `csi_heavy` | 24.661 | 24.746 | 2.71 | 1 | 1778576 | 1778576 | 16000 |
| `scroll_heavy_history0` | 104.671 | 106.684 | 0.55 | 4 | 6024374 | 6003867 | 60000 |
| `scroll_heavy_history1000` | 104.872 | 104.977 | 0.55 | 4 | 6024374 | 6003867 | 60000 |
| `mixed_interactive` | 6.599 | 6.654 | 7.23 | 1 | 54 | 54 | 4 |
| `snapshot_opt_in` | 36.047 | 36.394 | n/a | 400 | 99840000 | 499200 | 0 |
| `queue_growth_ascii_chunked_64` | 77.999 | 78.769 | 8.07 | 1 | 3604400 | 3604400 | 30000 |
| `queue_growth_scroll_chunked_16` | 107.004 | 107.414 | 0.53 | 1 | 5995216 | 5995216 | 60000 |

### Delta vs M7-BL-003 (Key F2 Workloads)

| Workload | Median latency delta | Throughput delta | Alloc count delta | Alloc bytes delta | Peak live delta | Max queue depth delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `queue_growth_ascii_chunked_64` | +4.27% | -4.17% | -87.50% | -32.11% | -22.58% | -24.41% |
| `queue_growth_scroll_chunked_16` | +1.46% | -1.82% | -75.00% | -0.48% | -0.14% | +0.00% |

Architect note:

- F2B queue-envelope improvement is significant for chunked ASCII path:
  lower queue depth, lower alloc count, and lower peak live bytes.
- Scroll chunked workload queue depth remains unchanged, indicating next queue
  envelope wins (if pursued) should target control-heavy/event-heavy paths.

---

## M7-BL-005 (F3 Post-Implementation)

Baseline ID: `M7-BL-005`

Timestamp (UTC): `2026-04-23 20:00:26Z`

Command:

- `zig build m7-baseline`

### Results

| Workload | Median (ms) | P95 (ms) | Throughput (MiB/s) | Median alloc count | Median alloc bytes | Median peak live bytes | Median max queue depth |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `ascii_heavy` | 33.312 | 33.995 | 18.89 | 1 | 3294176 | 3294176 | 30000 |
| `csi_heavy` | 24.792 | 25.936 | 2.69 | 1 | 1778576 | 1778576 | 16000 |
| `scroll_heavy_history0` | 22.880 | 25.603 | 2.50 | 4 | 6024374 | 6003867 | 60000 |
| `scroll_heavy_history1000` | 23.484 | 23.576 | 2.44 | 4 | 6024374 | 6003867 | 60000 |
| `mixed_interactive` | 6.887 | 7.043 | 6.92 | 1 | 54 | 54 | 4 |
| `snapshot_opt_in` | 58.129 | 58.351 | n/a | 400 | 99840000 | 499200 | 0 |
| `queue_growth_ascii_chunked_64` | 38.715 | 40.119 | 16.26 | 1 | 3604400 | 3604400 | 30000 |
| `queue_growth_scroll_chunked_16` | 26.306 | 26.445 | 2.18 | 1 | 5995216 | 5995216 | 60000 |

### Delta vs M7-BL-004 (F3 Target Workloads)

| Workload | Median latency delta | Throughput delta |
| --- | ---: | ---: |
| `scroll_heavy_history0` | -78.14% | +354.55% |
| `scroll_heavy_history1000` | -77.61% | +343.64% |
| `queue_growth_scroll_chunked_16` | -75.42% | +311.32% |

### F3 Gate Preview (`M7-F3-SPEC-001`)

1. `scroll_heavy_history0` median latency improvement >=10%: `PASS`
2. `scroll_heavy_history1000` median latency improvement >=10%: `PASS`
3. `queue_growth_scroll_chunked_16` median latency improvement >=8%: `PASS`
4. Regression gates:
   - `ascii_heavy` throughput regression <=3%: `PASS` (improved)
   - `mixed_interactive` median latency regression <=5%: `PASS` (+4.36%)
5. `zig build test` correctness gate: `PASS`
