# Report Checklist

Before reporting work as complete, run this checklist.

## Human Rules Self-Check (Before and After Each Batch)

### Pre-plan check

1. Re-read the Human Rules listed below.
2. State intended batch scope in one line.
3. Confirm the planned scope does not violate any rule.

Human Rules:
- No compatibility/fallback/workaround/in-case code paths. Keep things KISS, DRY, and unambiguous.
- Naming conventions and docstrings are treated the same way: details live in markdown, and file/fn/folder/comment names stay simple, clean, and intentional.
- `///` and `//!` comment lines are architect/human owned unless explicitly authorized.
- `checkins/` is read-only for agents; use it only as context.

### Post-execution check

Run:

```bash
zig build
zig build test
rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src
git diff --name-only
```

Then verify:
1. Edited files match the planned batch intent.
2. No rule was violated during execution.
3. Any unavoidable scope drift is reported explicitly as a blocker.

## Build and Test

```bash
zig build
zig build test
```

Expected: both commands exit with code `0`.

## Commit Integrity

For each reported commit:

```bash
git show --name-status <hash>
```

Expected: output matches all files claimed in the report.

## Code Quality Checks

### No ticket tags in Zig source

```bash
rg -n "HT-[0-9]+|CZH-[0-9]+|JIRA|ticket" --glob '*.zig' src build.zig
```

Expected: zero matches.

### No forbidden imports in parser/event/screen/tests

```bash
rg "app_logger|session|publication|ffi|android|platform|editor|workspace" --glob '*.zig' src/parser src/event src/screen src/test src/root.zig
```

Expected: zero matches or intentional explanatory comments only.

### No legacy brand strings or compat code

```bash
rg "zide|ZIDE|compat[^ib]|fallback|shim|workaround" --glob '*.zig' src build.zig
```

Expected: zero matches.

## Report Format

Include:
1. Commit hash and message
2. Files changed (from `git show --name-status`)
3. One-line claim-to-file mapping
4. Build/test validation results
