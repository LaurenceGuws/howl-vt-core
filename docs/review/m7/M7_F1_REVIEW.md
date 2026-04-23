# M7 F1 Review

Review ID: `M7-F1-REVIEW-001`

Scope reviewed:

- `src/event/bridge.zig`
- `docs/review/m7/M7_BASELINE.md` (`M7-BL-002`)
- `M7-F1-SPEC-001` gate outcomes

## Outcome

`F1` is accepted with one explicit waiver.

## Gate Results

1. Allocation reduction (`ascii_heavy` alloc count >=25% reduction): `PASS`
2. Allocation bytes (`ascii_heavy` alloc bytes >=20% reduction): `FAIL`
3. Stability (`mixed_interactive` latency regression <=5%): `PASS`
4. Throughput (`ascii_heavy` throughput regression <=3%): `PASS`
5. Correctness (`zig build test`): `PASS`

## Waiver Decision

Waived gate: `#2` allocation bytes reduction.

Rationale:

- `F1` targeted per-event allocation churn and queue ownership overhead.
- The implemented arena-backed bridge ownership removes allocator call volume
  and significantly improves latency/throughput.
- Allocated bytes did not materially decrease because payload bytes are still
  materialized by design for deterministic queued ownership.

Constraint on waiver:

- This waiver applies only to `F1`.
- Future memory-volume reductions remain in scope under `F1R`/`F2` follow-up
  work and must be measured against `M7` protocol.

## Next Target

Next target should be `F2` policy hardening:

- define explicit queue-growth envelope and measurement-driven thresholds
- decide whether queue-size bounding belongs to runtime contract or remains a
  host responsibility with documented limits
