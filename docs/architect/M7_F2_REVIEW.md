# M7 F2 Review

Review ID: `M7-F2-REVIEW-001`

Scope reviewed:

- `docs/architect/M7_F2_SPEC.md`
- `docs/architect/M7_BASELINE.md` (`M7-BL-003`)
- `tools/m7_baseline.zig` queue-envelope metrics

## Outcome

`F2` policy phase is accepted (`Outcome A` from `M7-F2-SPEC-001`).

## Outcome A Gate Check

1. queue-depth and peak-live metrics published and stable for review: `PASS`
2. doctrine text documents queue-envelope reporting requirements: `PASS`
3. no major regressions in existing M7 baseline surfaces: `PASS`

## Policy State After F2

- Queue growth between `feed*` and `apply` remains contractually allowed.
- Queue-envelope reporting is now mandatory for queue-focused work:
  - `median_max_queue_depth`
  - `median_peak_live_bytes`
- `M7-BL-003` is now the reference envelope baseline for queue policy changes.

## Next Target Options

1. `F2B` implementation slice:
   introduce bounded queue-management mechanics and prove measurable
   queue-envelope improvement vs `M7-BL-003` with no contract regressions.
2. `F3` preparation:
   open scroll-path optimization spec using current queue-envelope baseline as
   a stabilized upstream reference.
