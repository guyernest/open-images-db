---
phase: 03-iceberg-tables
plan: 02
subsystem: database
tags: [athena, iceberg, sql, parquet, opencsvserde, ctas]

# Dependency graph
requires:
  - phase: 03-iceberg-tables
    provides: Shell runner, S3 reorganization, hierarchy flattener (Plan 01)
  - phase: 02-data-acquisition
    provides: Raw CSV files uploaded to S3
provides:
  - 7 SQL DDL files creating external tables over raw CSVs and CTAS into Iceberg tables
  - Type-cast schemas with DOUBLE coordinates, BOOLEAN flags, INT sizes
  - Combined human+machine labels table via UNION ALL
affects: [03-iceberg-tables, 04-views-enrichment, 05-validation-queries]

# Tech tracking
tech-stack:
  added: []
  patterns: [opencsvserde-external-table, iceberg-ctas, boolean-case-when-pattern, union-all-combine]

key-files:
  created:
    - queries/tables/01-images.sql
    - queries/tables/02-class-descriptions.sql
    - queries/tables/03-labels.sql
    - queries/tables/04-bounding-boxes.sql
    - queries/tables/05-masks.sql
    - queries/tables/06-relationships.sql
    - queries/tables/07-label-hierarchy.sql
  modified: []

key-decisions:
  - "Bounding boxes exclude x_click columns from Iceberg table (raw external table retains them)"
  - "Masks clicks column kept as VARCHAR for future json_extract compatibility (TBL-10)"
  - "Class descriptions assumes header row exists (skip.header.line.count=1) with comment noting assumption"

patterns-established:
  - "Two-step DDL: DROP iceberg, DROP raw, CREATE EXTERNAL (OpenCSVSerDe, all STRING), CTAS into Iceberg"
  - "Boolean casting: CASE WHEN col = '1' THEN true ELSE false END (never CAST for booleans)"
  - "__BUCKET__ placeholder in all S3 LOCATIONs for runner substitution"

requirements-completed: [TBL-01, TBL-02, TBL-03, TBL-04, TBL-05, TBL-06, TBL-07, TBL-10]

# Metrics
duration: 2min
completed: 2026-03-05
---

# Phase 3 Plan 2: Iceberg Table SQL DDL Summary

**7 Athena SQL files with OpenCSVSerDe external tables and Iceberg CTAS for images, labels, bounding boxes, masks, relationships, and hierarchy**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-05T22:35:56Z
- **Completed:** 2026-03-05T22:38:00Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Created all 7 SQL DDL files covering the complete Open Images V7 validation schema
- Labels table combines human and machine annotations via UNION ALL into a single Iceberg table
- Bounding boxes table casts 5 boolean flags via CASE WHEN pattern and 4 coordinates + confidence to DOUBLE
- All tables follow consistent two-step pattern: DROP + CREATE EXTERNAL + CTAS into Iceberg with PARQUET/SNAPPY

## Task Commits

Each task was committed atomically:

1. **Task 1: SQL files for images, class_descriptions, labels, and bounding_boxes** - `44db68c` (feat)
2. **Task 2: SQL files for masks, relationships, and label_hierarchy** - `20d2689` (feat)

## Files Created/Modified
- `queries/tables/01-images.sql` - External + Iceberg DDL for images (12 columns, INT original_size, DOUBLE rotation)
- `queries/tables/02-class-descriptions.sql` - External + Iceberg DDL for class_descriptions (2 VARCHAR columns)
- `queries/tables/03-labels.sql` - External + Iceberg DDL combining human+machine labels (UNION ALL, DOUBLE confidence)
- `queries/tables/04-bounding-boxes.sql` - External + Iceberg DDL for bounding boxes (DOUBLE coords, BOOLEAN flags via CASE WHEN)
- `queries/tables/05-masks.sql` - External + Iceberg DDL for masks (VARCHAR clicks for future json_extract)
- `queries/tables/06-relationships.sql` - External + Iceberg DDL for relationships (8 DOUBLE coordinates)
- `queries/tables/07-label-hierarchy.sql` - External + Iceberg DDL for label hierarchy (2 VARCHAR MID columns)

## Decisions Made
- Bounding boxes x_click columns excluded from Iceberg table (click annotation data not needed for bbox queries; raw external table retains all 21 columns as reference)
- Masks clicks column stored as VARCHAR rather than attempting JSON parsing at this stage (deferred to Phase 4 TBL-10 enrichment)
- Class descriptions CSV assumed to have a header row, with a SQL comment documenting the assumption and fix instructions

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 7 SQL files ready for execution by `scripts/create-tables.sh` runner
- Tables can be created by running the pipeline: reorganize S3 -> flatten hierarchy -> execute SQL files
- Phase 4 (Views + Enrichment) can build views on top of these Iceberg tables
- Phase 5 (Validation) can verify row counts by comparing raw external tables to Iceberg tables

---
*Phase: 03-iceberg-tables*
*Completed: 2026-03-05*
