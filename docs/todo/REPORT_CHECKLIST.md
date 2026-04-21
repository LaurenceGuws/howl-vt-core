# Report Checklist

Before reporting work as complete, run these commands and verify results:

## Build & Test

```bash
zig build
zig build test
```

**Expected**: Both commands exit with code 0 (success).

## Commit Integrity

For each commit being reported, run:

```bash
git show --name-status <hash>
```

**Expected**: Output matches all files mentioned in the commit report.

## Code Quality Checks

### No ticket tags in Zig source:

```bash
rg -n "HT-[0-9]+|CZH-[0-9]+|JIRA|ticket" --glob '*.zig' src build.zig
```

**Expected**: Zero matches (no output).

### No forbidden imports in parser/tests:

```bash
rg "app_logger|session|publication|ffi|android|platform|editor|workspace" --glob '*.zig' src/terminal/parser src/terminal*_test.zig
```

**Expected**: Zero matches or only intentional comments like "No session/app coupling".

### No legacy brand strings or compat code:

```bash
rg "zide|ZIDE|compat[^ib]|fallback|stub|shim|workaround" --glob '*.zig' src build.zig
```

**Expected**: Zero matches.

## Report Format

When reporting completion, include:
1. Commit hash and message
2. Files changed (from `git show --name-status`)
3. 1-line claim → file mapping
4. Build/test validation results

This ensures all claims match actual diffs and all validation passed.
