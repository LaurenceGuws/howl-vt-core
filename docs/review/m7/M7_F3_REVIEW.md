# M7 F3 Review

Review ID: `M7-F3-REVIEW-001`

Scope reviewed:

- `src/screen/state.zig`
- `src/model/snapshot.zig`
- `src/test/relay.zig`
- `docs/review/m7/M7_BASELINE.md` (`M7-BL-005`)
- `M7-F3-SPEC-001` gates

## Outcome

`F3` implementation slice is accepted.

## Gate Check (`M7-F3-SPEC-001`)

1. `scroll_heavy_history0` latency improvement >=10%: `PASS`
2. `scroll_heavy_history1000` latency improvement >=10%: `PASS`
3. `queue_growth_scroll_chunked_16` latency improvement >=8%: `PASS`
4. Regression gates:
   - `ascii_heavy` throughput regression <=3%: `PASS` (improved)
   - `mixed_interactive` latency regression <=5%: `PASS`
5. Correctness gate (`zig build test`): `PASS`

## Architectural Notes

- The accepted approach replaced per-scroll full-buffer movement with logical
  row-origin rotation in screen storage.
- Observable parity is preserved by:
  - row-mapped read/write/erase operations in `ScreenState`
  - snapshot capture via logical `cellAt` order
  - parity test update avoiding raw backing-slice assumptions

## Residual Risk

- `snapshot_opt_in` cost increased due to logical-order copy path. This is
  acceptable under current doctrine (`D3`) because snapshot is opt-in, but
  should be tracked if snapshot throughput becomes a product requirement.

## Next Target

1. F2C (optional) for control-heavy queue-depth reductions, or
2. M7 freeze prep if no further performance slices are required this cycle.
