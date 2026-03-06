# Phase 4: Views and Enrichment - Research

**Researched:** 2026-03-05
**Domain:** AWS Athena SQL views, JSON extraction, Open Images V7 schema
**Confidence:** HIGH

## Summary

This phase creates 4 Athena convenience views (labeled images, labeled bounding boxes, labeled masks, labeled relationships) and enriches the masks view with pre-computed geometry metadata. All views use `CREATE OR REPLACE VIEW` -- no data movement, no cost beyond query time, fully idempotent.

The existing codebase has a well-established pattern: numbered SQL files in `queries/`, shell runner scripts sourcing `scripts/lib/common.sh` and `scripts/lib/athena.sh`, and verification scripts. This phase follows the same pattern with `queries/views/` and `scripts/create-views.sh` / `scripts/verify-views.sh`.

**Critical finding:** The masks `clicks` column is NOT JSON. It uses a semicolon-delimited format (`X1 Y1 T1;X2 Y2 T2;...`) where each click is space-separated coordinates and type. The CONTEXT.md mentions `json_extract` for clicks, but this will not work. Instead, use Athena string functions (`split`, `element_at`, `transform`) or simply expose the raw clicks column and add computed geometry from the bounding box coordinates (which ARE numeric doubles).

**Primary recommendation:** Create 4 view SQL files + 2 shell scripts, following the exact conventions of `create-tables.sh` / `verify-tables.sh`. Focus mask enrichment on bounding box geometry (box_area, box_width, box_height, box_center) since those are already numeric columns. For clicks, expose a `click_count` derived via string splitting rather than attempting JSON extraction.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- View SQL files live in `queries/views/` directory (parallel to `queries/tables/`)
- Numbered files: 01-labeled-images.sql, 02-labeled-boxes.sql, etc. (consistent with tables pattern)
- New `scripts/create-views.sh` runner script sources common.sh, executes all view SQL files via Athena
- Idempotent via CREATE OR REPLACE VIEW (no DROP needed, unlike tables)
- Full denormalization: each view includes image metadata (url, dimensions, license) + human-readable display_name + all annotation columns
- Labeled images view (VIEW-01) combines human AND machine labels in one view (labels table already has source column for filtering)
- Relationships view joins class_descriptions twice: label_name_1 -> display_name_1, label_name_2 -> display_name_2
- Views include computed convenience columns where useful (e.g., box_area, aspect_ratio, center coordinates for bounding boxes)
- Athena SQL only -- no external processing or shell scripts for mask geometry
- Implemented as a view (not materialized table) -- fine at 42K validation set scale
- Computed geometry fields from bounding box coordinates: box_area, box_center_x, box_center_y, box_width, box_height
- Parse clicks JSON column using json_extract to expose key fields as named columns
- Fully autonomous -- no human checkpoint needed
- New `scripts/verify-views.sh` checks each view returns rows and has expected columns
- Runs after create-views.sh

### Claude's Discretion
- Exact computed column formulas and naming
- Which clicks JSON fields to extract (based on actual data inspection)
- View column ordering and aliasing
- Verification script check details

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VIEW-01 | Athena view joining images with human-readable labels (images + labels + class descriptions) | Labeled images view: 3-way JOIN of labels + images + class_descriptions; includes source column for human/machine filtering |
| VIEW-02 | Athena view joining images with bounding boxes and label names | Labeled boxes view: 3-way JOIN of bounding_boxes + images + class_descriptions; add computed box_area, box_width, box_height, aspect_ratio, center coords |
| VIEW-03 | Athena view joining images with segmentation masks and label names | Labeled masks view: 3-way JOIN of masks + images + class_descriptions; add computed geometry from box coordinates + click_count |
| VIEW-04 | Athena view joining images with visual relationships and label names | Labeled relationships view: JOIN relationships + images + class_descriptions TWICE (for label_name_1 and label_name_2) |
| MASK-01 | Pre-computed mask metadata (area, bounding polygon) stored alongside raw RLE data for SQL-queryable mask geometry | Mask enrichment via computed columns in VIEW-03: box_area, box_width, box_height, box_center_x, box_center_y, click_count |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AWS Athena Engine v3 | Trino-based | SQL engine for views | Already deployed in workgroup `open-images` |
| Athena DDL | CREATE OR REPLACE VIEW | View creation | Standard SQL, idempotent, no cost |
| Bash/AWS CLI | v2 | Runner and verification scripts | Consistent with existing scripts |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| scripts/lib/common.sh | existing | Logging, prerequisites, bucket discovery | All scripts |
| scripts/lib/athena.sh | existing | Query execution, polling, scalar results | Runner and verification |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Views | Materialized tables (CTAS) | Views are zero-cost, zero-storage; materialized would duplicate data. At 42K rows, views perform fine |
| String parsing for clicks | json_extract | Clicks column is NOT JSON format -- it is semicolon-delimited `X Y T;X Y T;...`. String functions required |

## Architecture Patterns

### Recommended Project Structure
```
queries/
  tables/           # existing -- 7 Iceberg table DDL files
  views/            # NEW -- 4 view SQL files
    01-labeled-images.sql
    02-labeled-boxes.sql
    03-labeled-masks.sql
    04-labeled-relationships.sql
scripts/
  lib/
    common.sh       # existing -- shared functions
    athena.sh        # existing -- Athena query execution
  create-views.sh   # NEW -- runner (simpler than create-tables.sh, no reorg/hierarchy steps)
  verify-views.sh   # NEW -- verification (similar to verify-tables.sh)
```

### Pattern 1: View SQL with CREATE OR REPLACE
**What:** Each SQL file contains a single `CREATE OR REPLACE VIEW` statement
**When to use:** All 4 view files
**Key difference from tables:** No DROP needed, no semicolon-splitting needed (single statement per file), no `__BUCKET__` placeholder (views reference tables, not S3 locations). Still needs `__DATABASE__` placeholder.
```sql
-- Source: https://docs.aws.amazon.com/athena/latest/ug/create-view.html
CREATE OR REPLACE VIEW __DATABASE__.labeled_images AS
SELECT
  i.image_id,
  i.original_url,
  -- ... image columns
  cd.display_name,
  l.label_name,
  l.confidence,
  l.source
FROM __DATABASE__.labels l
JOIN __DATABASE__.images i ON l.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd ON l.label_name = cd.label_name;
```

### Pattern 2: Double-Join for Relationships
**What:** Relationships reference two different class labels; join class_descriptions twice with aliases
**When to use:** VIEW-04 (labeled_relationships)
```sql
CREATE OR REPLACE VIEW __DATABASE__.labeled_relationships AS
SELECT
  r.*,
  i.original_url,
  -- ... image columns
  cd1.display_name AS display_name_1,
  cd2.display_name AS display_name_2
FROM __DATABASE__.relationships r
JOIN __DATABASE__.images i ON r.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd1 ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2 ON r.label_name_2 = cd2.label_name;
```

### Pattern 3: Computed Geometry Columns
**What:** Derive spatial metadata from existing bounding box coordinates (normalized 0-1)
**When to use:** VIEW-02 (bounding boxes) and VIEW-03 (masks)
```sql
-- Bounding box geometry (coordinates are normalized 0.0-1.0)
(x_max - x_min) * (y_max - y_min)         AS box_area,
(x_max - x_min)                            AS box_width,
(y_max - y_min)                            AS box_height,
(x_min + x_max) / 2.0                      AS box_center_x,
(y_min + y_max) / 2.0                      AS box_center_y,
CASE WHEN (y_max - y_min) > 0
  THEN (x_max - x_min) / (y_max - y_min)
  ELSE NULL END                             AS aspect_ratio
```

### Pattern 4: Clicks Column Parsing (String, NOT JSON)
**What:** The clicks column format is `X1 Y1 T1;X2 Y2 T2;...` (semicolon-delimited, space-separated triples). NOT JSON.
**When to use:** VIEW-03 (masks enrichment for MASK-01)
```sql
-- Count the number of annotation clicks
-- Each click is separated by semicolons, so count semicolons + 1
-- Handle NULL/empty clicks gracefully
CASE
  WHEN clicks IS NULL OR clicks = '' THEN 0
  ELSE cardinality(split(clicks, ';'))
END AS click_count
```

### Pattern 5: Simplified Runner Script
**What:** create-views.sh is simpler than create-tables.sh -- no S3 reorg, no hierarchy flattening, no multi-statement splitting
**When to use:** The runner script
**Key simplification:** Views are single SQL statements, so no semicolon splitting needed. Each file = one `CREATE OR REPLACE VIEW` statement. Also, no `__BUCKET__` substitution needed since views reference database tables, not S3 paths.

### Anti-Patterns to Avoid
- **Using json_extract on clicks column:** The clicks data is NOT JSON. It is semicolon-delimited `X Y T` triples. Using json_extract will fail at runtime.
- **Using DROP VIEW before CREATE:** `CREATE OR REPLACE VIEW` is atomic and idempotent. Adding DROP VIEW creates a window where the view does not exist.
- **Materializing views as tables:** At 42K rows, views perform instantly. Materializing adds storage cost and staleness risk for zero benefit.
- **Omitting LEFT JOIN consideration:** If any labels/masks/boxes reference a label_name not in class_descriptions, an INNER JOIN would silently drop those rows. Use INNER JOIN per user decision (full denormalization implies all MIDs have descriptions), but the verification script should confirm row counts match.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Query execution + polling | Custom AWS CLI wrapper | Existing `athena.sh` library | Already handles start-query-execution, polling, error reporting |
| Bucket discovery | Hardcoded bucket names | Existing `discover_bucket` in common.sh | Already reads from CloudFormation outputs |
| Logging | Custom echo statements | Existing `log_info`/`log_error`/`log_warn` | Consistent timestamp format across all scripts |

## Common Pitfalls

### Pitfall 1: Clicks Column Is Not JSON
**What goes wrong:** Using `json_extract(clicks, '$.x')` fails because clicks is `X Y T;X Y T;...` format
**Why it happens:** CONTEXT.md says "Parse clicks JSON column using json_extract" based on column name suggesting JSON
**How to avoid:** Use Athena string functions: `split(clicks, ';')` to get array of click triples, `cardinality()` for count
**Warning signs:** Athena error "Not valid JSON" or NULL results from json_extract

### Pitfall 2: Missing Class Descriptions for Some MIDs
**What goes wrong:** INNER JOIN with class_descriptions drops rows where label_name has no matching display_name
**Why it happens:** Some annotation MIDs might not be in the class descriptions file
**How to avoid:** Verify with a quick query: `SELECT COUNT(*) FROM labels WHERE label_name NOT IN (SELECT label_name FROM class_descriptions)`. If > 0, consider LEFT JOIN. The verification script should compare view row counts to base table row counts.
**Warning signs:** View row count significantly less than base table row count

### Pitfall 3: Database Placeholder in View SQL
**What goes wrong:** Views reference `open_images.table_name` but the database name is in a variable
**Why it happens:** Table SQL files use `__DATABASE__` placeholder, views must do the same
**How to avoid:** Use `__DATABASE__` consistently in all view SQL files. The runner script substitutes it just like create-tables.sh does.

### Pitfall 4: Null Bounding Box Coordinates in Masks
**What goes wrong:** Computed geometry (box_area, etc.) produces NULL for masks with NULL box coordinates
**Why it happens:** Some mask rows might have NULL bounding box values
**How to avoid:** Use COALESCE or CASE WHEN for computed columns, or document that NULL geometry = no bounding box available

### Pitfall 5: Images Table Missing Dimension Columns
**What goes wrong:** CONTEXT.md says "image metadata (url, dimensions, license)" but the images table has `original_size` (file size in bytes, INT) and no separate width/height columns
**Why it happens:** Open Images metadata CSV has original_size as file size, not pixel dimensions
**How to avoid:** Include `original_size` (file size) and `rotation` but do NOT pretend they are width/height. The "dimensions" in denormalization refers to available metadata, not pixel dimensions.

## Code Examples

### View 1: Labeled Images (VIEW-01)
```sql
-- 01-labeled-images.sql
-- View: labeled_images
-- Joins: labels + images + class_descriptions
-- Combines human AND machine labels (filter via source column)
-- Requirement: VIEW-01

CREATE OR REPLACE VIEW __DATABASE__.labeled_images AS
SELECT
  l.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.title,
  i.original_size,
  i.thumbnail_300k_url,
  i.rotation,
  l.source,
  l.label_name,
  cd.display_name,
  l.confidence
FROM __DATABASE__.labels l
JOIN __DATABASE__.images i
  ON l.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd
  ON l.label_name = cd.label_name;
```

### View 2: Labeled Boxes (VIEW-02)
```sql
-- 02-labeled-boxes.sql
-- View: labeled_boxes
-- Joins: bounding_boxes + images + class_descriptions
-- Includes computed geometry columns
-- Requirement: VIEW-02

CREATE OR REPLACE VIEW __DATABASE__.labeled_boxes AS
SELECT
  bb.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.original_size,
  i.thumbnail_300k_url,
  bb.source,
  bb.label_name,
  cd.display_name,
  bb.confidence,
  bb.x_min,
  bb.x_max,
  bb.y_min,
  bb.y_max,
  bb.is_occluded,
  bb.is_truncated,
  bb.is_group_of,
  bb.is_depiction,
  bb.is_inside,
  -- Computed geometry (normalized coordinates, 0.0-1.0 range)
  (bb.x_max - bb.x_min) * (bb.y_max - bb.y_min) AS box_area,
  (bb.x_max - bb.x_min)                          AS box_width,
  (bb.y_max - bb.y_min)                          AS box_height,
  (bb.x_min + bb.x_max) / 2.0                    AS box_center_x,
  (bb.y_min + bb.y_max) / 2.0                    AS box_center_y,
  CASE WHEN (bb.y_max - bb.y_min) > 0
    THEN (bb.x_max - bb.x_min) / (bb.y_max - bb.y_min)
    ELSE NULL
  END                                             AS aspect_ratio
FROM __DATABASE__.bounding_boxes bb
JOIN __DATABASE__.images i
  ON bb.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd
  ON bb.label_name = cd.label_name;
```

### View 3: Labeled Masks with Enrichment (VIEW-03 + MASK-01)
```sql
-- 03-labeled-masks.sql
-- View: labeled_masks
-- Joins: masks + images + class_descriptions
-- Includes mask enrichment: computed geometry from box coords + click count
-- Requirements: VIEW-03, MASK-01

CREATE OR REPLACE VIEW __DATABASE__.labeled_masks AS
SELECT
  m.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.original_size,
  i.thumbnail_300k_url,
  m.label_name,
  cd.display_name,
  m.mask_path,
  m.box_id,
  m.box_x_min,
  m.box_x_max,
  m.box_y_min,
  m.box_y_max,
  m.predicted_iou,
  m.clicks,
  -- Computed mask geometry from bounding box coordinates
  (m.box_x_max - m.box_x_min) * (m.box_y_max - m.box_y_min) AS box_area,
  (m.box_x_max - m.box_x_min)                                AS box_width,
  (m.box_y_max - m.box_y_min)                                AS box_height,
  (m.box_x_min + m.box_x_max) / 2.0                          AS box_center_x,
  (m.box_y_min + m.box_y_max) / 2.0                          AS box_center_y,
  -- Click count from semicolon-delimited clicks column
  CASE
    WHEN m.clicks IS NULL OR m.clicks = '' THEN 0
    ELSE cardinality(split(m.clicks, ';'))
  END AS click_count
FROM __DATABASE__.masks m
JOIN __DATABASE__.images i
  ON m.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd
  ON m.label_name = cd.label_name;
```

### View 4: Labeled Relationships (VIEW-04)
```sql
-- 04-labeled-relationships.sql
-- View: labeled_relationships
-- Joins: relationships + images + class_descriptions (twice, for both labels)
-- Requirement: VIEW-04

CREATE OR REPLACE VIEW __DATABASE__.labeled_relationships AS
SELECT
  r.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.original_size,
  i.thumbnail_300k_url,
  r.label_name_1,
  cd1.display_name AS display_name_1,
  r.label_name_2,
  cd2.display_name AS display_name_2,
  r.relationship_label,
  r.x_min_1, r.x_max_1, r.y_min_1, r.y_max_1,
  r.x_min_2, r.x_max_2, r.y_min_2, r.y_max_2
FROM __DATABASE__.relationships r
JOIN __DATABASE__.images i
  ON r.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd1
  ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2
  ON r.label_name_2 = cd2.label_name;
```

### Runner Script Pattern (create-views.sh)
```bash
#!/usr/bin/env bash
set -euo pipefail
# Simplified version of create-tables.sh:
# - No S3 reorganization step
# - No hierarchy flattening step
# - Single statement per SQL file (no semicolon splitting)
# - Only __DATABASE__ substitution (no __BUCKET__ needed)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/athena.sh"

# Find SQL files in queries/views/, substitute __DATABASE__, execute via athena_execute_and_wait
```

### Verification Script Pattern (verify-views.sh)
```bash
# For each expected view:
# 1. SELECT 1 FROM view LIMIT 1 -- confirms view exists and returns rows
# 2. Compare row count to base table -- confirms JOIN did not drop rows unexpectedly
# 3. Check specific computed columns are non-null (e.g., display_name, box_area)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Presto SQL engine | Trino (Athena v3) | 2023 | Athena v3 has better string functions, `split()`, `cardinality()`, `transform()` |
| DROP VIEW + CREATE VIEW | CREATE OR REPLACE VIEW | Always available in Athena | Atomic, no downtime window |

## Open Questions

1. **Are all label_name MIDs present in class_descriptions?**
   - What we know: The class_descriptions table maps MID to display_name. Labels, boxes, masks, and relationships all use label_name (MID format like `/m/01g317`).
   - What's unclear: Whether every MID in annotations has a corresponding entry in class_descriptions.
   - Recommendation: Use INNER JOIN (per user decision for full denormalization), but verify-views.sh should compare view row counts to base table row counts and warn if they differ.

2. **Clicks column parsing -- semicolons vs JSON**
   - What we know: Official Open Images docs confirm clicks format is `X Y T;X Y T;...` (semicolon-delimited, NOT JSON).
   - What's unclear: Whether any mask rows have empty/NULL clicks or malformed data.
   - Recommendation: Use `split(clicks, ';')` for click_count. CASE WHEN for NULL/empty handling. Do NOT use json_extract. Document this discrepancy from the CONTEXT.md assumption.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash scripts + Athena SQL queries |
| Config file | scripts/lib/athena.sh (Athena config) |
| Quick run command | `bash scripts/verify-views.sh --quick` |
| Full suite command | `bash scripts/verify-views.sh` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VIEW-01 | labeled_images view returns rows with display_name | smoke | `bash scripts/verify-views.sh` (checks existence + columns) | Wave 0 |
| VIEW-02 | labeled_boxes view returns rows with display_name + computed geometry | smoke | `bash scripts/verify-views.sh` (checks existence + columns) | Wave 0 |
| VIEW-03 | labeled_masks view returns rows with display_name + mask geometry | smoke | `bash scripts/verify-views.sh` (checks existence + columns) | Wave 0 |
| VIEW-04 | labeled_relationships view returns rows with display_name_1, display_name_2 | smoke | `bash scripts/verify-views.sh` (checks existence + columns) | Wave 0 |
| MASK-01 | Mask enrichment columns (box_area, click_count) are queryable and non-null | smoke | `bash scripts/verify-views.sh` (checks computed columns) | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash scripts/verify-views.sh --quick`
- **Per wave merge:** `bash scripts/verify-views.sh`
- **Phase gate:** Full verification green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `queries/views/` directory -- does not exist yet, needs creation
- [ ] `scripts/create-views.sh` -- runner script
- [ ] `scripts/verify-views.sh` -- verification script
- [ ] All 4 SQL view files

## Sources

### Primary (HIGH confidence)
- [AWS Athena CREATE VIEW docs](https://docs.aws.amazon.com/athena/latest/ug/create-view.html) -- CREATE OR REPLACE VIEW syntax confirmed
- [AWS Athena JSON extraction docs](https://docs.aws.amazon.com/athena/latest/ug/extracting-data-from-JSON.html) -- json_extract/json_extract_scalar function signatures
- [Open Images V7 download page](https://storage.googleapis.com/openimages/web/download_v7.html) -- Clicks column format confirmed as `X Y T;X Y T;...` (NOT JSON)
- Existing codebase: `scripts/create-tables.sh`, `scripts/verify-tables.sh`, `scripts/lib/athena.sh`, `scripts/lib/common.sh` -- established patterns
- Existing table SQL: `queries/tables/05-masks.sql`, `queries/tables/06-relationships.sql` -- exact column names and types

### Secondary (MEDIUM confidence)
- [Athena engine v3 reference](https://docs.aws.amazon.com/athena/latest/ug/engine-versions-reference-0003.html) -- Trino-based, string function availability

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - using existing project infrastructure, no new tools
- Architecture: HIGH - follows established codebase patterns exactly, all table schemas verified from SQL files
- Pitfalls: HIGH - clicks column format verified against official Open Images documentation; join semantics understood from table schemas
- Mask enrichment: HIGH for box geometry (numeric columns confirmed in 05-masks.sql), MEDIUM for click_count (format confirmed but edge cases unknown)

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (stable -- Athena SQL syntax and Open Images V7 schema are static)
