---
phase: 03-iceberg-tables
plan: 01
subsystem: infra
tags: [athena, iceberg, shell, aws-cli, jq, s3]

# Dependency graph
requires:
  - phase: 02-data-acquisition
    provides: Raw CSVs uploaded to S3 raw/ prefixes
provides:
  - Shell runner for Athena SQL execution with polling
  - S3 reorganization of raw CSVs into per-table prefixes
  - Label hierarchy JSON flattener (jq-based)
  - Table verification script with row count and type checks
affects: [03-iceberg-tables]

# Tech tracking
tech-stack:
  added: []
  patterns: [athena-query-polling, s3-prefix-per-table, semicolon-split-sql]

key-files:
  created:
    - scripts/create-tables.sh
    - scripts/lib/reorganize-raw.sh
    - scripts/lib/flatten-hierarchy.sh
    - scripts/verify-tables.sh
  modified: []

key-decisions:
  - "Runner continues on failure and reports all errors at end (not fail-fast)"
  - "S3 reorganization uses cp (not mv) to keep originals for safety"
  - "Hierarchy flattener always regenerates (fast operation, no staleness check)"
  - "Verify script supports --quick mode for fast feedback during development"

patterns-established:
  - "Athena polling pattern: start-query-execution -> poll get-query-execution every 2s -> check SUCCEEDED/FAILED"
  - "SQL file processing: read file, substitute __BUCKET__ placeholder, split on semicolons, execute each statement"
  - "run_athena_query_with_result pattern for queries that return data (verify script)"

requirements-completed: [TBL-08, TBL-09]

# Metrics
duration: 3min
completed: 2026-03-05
---

# Phase 3 Plan 1: Table Creation Shell Infrastructure Summary

**Athena table runner with SQL polling, S3 reorganization helper, hierarchy JSON flattener, and verification script**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-05T22:31:20Z
- **Completed:** 2026-03-05T22:34:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Runner script (`create-tables.sh`) reads SQL files from `queries/tables/`, substitutes `__BUCKET__` placeholder, splits on semicolons, and executes each statement via Athena CLI with 2-second polling
- Reorganization helper copies 7 raw CSVs from shared S3 prefixes into per-table sub-prefixes under `raw/tables/`
- Hierarchy flattener downloads JSON, extracts parent-child edges via jq recursive descent, uploads CSV to S3
- Verification script queries all 7 expected tables for row count > 0 and validates column types (double, boolean)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create runner script and S3 reorganization helper** - `07eb336` (feat)
2. **Task 2: Create hierarchy flattener and verification script** - `ad9b540` (feat)

## Files Created/Modified
- `scripts/create-tables.sh` - Main runner: sources libs, reorganizes S3, flattens hierarchy, executes SQL files with Athena polling
- `scripts/lib/reorganize-raw.sh` - Copies raw CSVs to per-table S3 sub-prefixes (idempotent)
- `scripts/lib/flatten-hierarchy.sh` - Downloads hierarchy JSON, flattens to parent_mid/child_mid CSV via jq
- `scripts/verify-tables.sh` - Smoke tests all 7 Iceberg tables for row counts and column types

## Decisions Made
- Runner continues on failure and reports all errors at end (user can see all broken tables at once)
- S3 reorganization uses `aws s3 cp` (not mv) to keep originals intact
- Hierarchy flattener always regenerates since it's fast (~600 edges)
- Added `--dry-run`, `--skip-reorg`, `--skip-hierarchy` flags to runner for flexibility
- Verify script has `--quick` mode that only checks row counts (skips type validation)

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Shell infrastructure ready for Plan 02 to create SQL files in `queries/tables/`
- `queries/tables/` directory created (empty, awaiting SQL files)
- All scripts source common.sh and follow established project conventions

---
*Phase: 03-iceberg-tables*
*Completed: 2026-03-05*
