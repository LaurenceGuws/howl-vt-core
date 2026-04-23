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

- Protocol: `docs/architect/M7_MEASUREMENT_PROTOCOL.md`
- Fixtures: `docs/architect/M7_FIXTURES.md`
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
