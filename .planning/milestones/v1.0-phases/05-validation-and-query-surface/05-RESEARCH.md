# Phase 5: Validation and Query Surface - Research

**Researched:** 2026-03-05
**Domain:** Bash scripting (Athena validation), Athena/Trino SQL, Markdown documentation
**Confidence:** HIGH

## Summary

Phase 5 is a validation and documentation phase -- no new infrastructure, tables, or views are created. The work divides into two streams: (1) a validation script that compares raw external table row counts against Iceberg table counts and performs spot-check queries, and (2) two documentation files (example SQL queries and schema documentation) targeting the downstream MCP server team.

The project has well-established patterns for shell scripts (sourcing common.sh + athena.sh, phased verification with pass/fail/warn reporting, --quick and --help flags). The validation script follows these patterns directly. The documentation is hand-written Markdown derived from the existing SQL files in queries/tables/ and queries/views/.

**Primary recommendation:** Follow the existing verify-tables.sh/verify-views.sh patterns exactly for the validation script. For documentation, use the SQL DDL files as the single source of truth for column names, types, and source CSV mappings.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- New `scripts/validate-data.sh` script (separate from verify-tables.sh which checks structure)
- Row count validation (VAL-01): queries raw_* external tables and Iceberg tables, compares counts
- Tolerance allowed for count mismatches (small percentage, e.g., <1%) -- some rows may be filtered during CTAS type casting
- Spot-check validation (VAL-02): picks values from live data, verifies specific ImageIDs have non-null columns within valid ranges (not hardcoded known values)
- Script sources common.sh + athena.sh, follows established runner pattern
- Single markdown file: `docs/examples.md` for example queries
- Grouped by query pattern: single-table queries, cross-table joins, JSON/string field parsing
- Each query has title, description, and SQL block (no sample output)
- Examples use both base tables and convenience views
- Must cover 8-12 queries total across all annotation types (QUERY-01, QUERY-02, QUERY-03)
- Single markdown file: `docs/SCHEMA.md` for schema documentation
- Hand-written from SQL files (not auto-generated) -- includes semantic context
- Full detail per table/view: column name, type, description, source CSV column mapping, nullable, example domain
- Views section includes which tables each view joins and explains computed columns
- Source CSV mapping traces each column back to its original CSV file and column name (QUERY-04)
- Fully autonomous -- validation script runs only SELECT queries (read-only, minimal cost)
- Example queries verified against live Athena to confirm they actually work

### Claude's Discretion
- Specific ImageIDs used for spot-checks (discovered from live data)
- Exact tolerance threshold for row count mismatches
- Which 8-12 example queries to write (covering all annotation types and patterns)
- Schema description wording and column semantics

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VAL-01 | Row count validation comparing source CSVs to Iceberg table counts | Use `SELECT COUNT(*) FROM raw_*` vs `SELECT COUNT(*) FROM <table>` pattern. 7 Iceberg tables to validate. Labels table combines two raw tables (raw_labels_human + raw_labels_machine). Tolerance-based comparison. |
| VAL-02 | Spot-check validation of known values across tables | Query live data for a sample ImageID, verify non-null columns and value ranges (e.g., coordinates in 0.0-1.0, confidence in 0.0-1.0, booleans are true/false). |
| QUERY-01 | 8-12 example SQL queries covering single-table queries for each annotation type | One query per base table (images, class_descriptions, labels, bounding_boxes, masks, relationships, label_hierarchy) = 7 single-table examples. |
| QUERY-02 | Example SQL queries demonstrating cross-table joins | Use convenience views or manual JOINs. E.g., find images labeled "Dog" with bounding boxes, or images with both labels and masks. |
| QUERY-03 | Example SQL queries demonstrating JSON field parsing for mask and relationship data | Clicks column is semicolon-delimited (not JSON) -- demonstrate split() and cardinality(). Show string parsing patterns. |
| QUERY-04 | Schema documentation with column names, types, semantics, and source CSV mapping for every table | Derive from 7 table SQL files + 4 view SQL files. Document raw CSV column name -> Iceberg column name mapping, type transformations. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2+ (macOS default) | Validation script | All project scripts use bash |
| AWS CLI v2 | 2.x | Athena query execution | Already a prerequisite in common.sh |
| jq | 1.x | JSON parsing of AWS responses | Already a prerequisite in common.sh |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| common.sh | Logging, prerequisites, bucket discovery | Sourced by validate-data.sh |
| athena.sh | athena_query_scalar, athena_execute_and_wait | All Athena queries in validation |

### Alternatives Considered
None -- the stack is fully established by prior phases. No new tools needed.

## Architecture Patterns

### Recommended Project Structure
```
scripts/
  validate-data.sh          # NEW: Data quality validation (VAL-01, VAL-02)
  lib/
    common.sh               # Existing: shared functions
    athena.sh               # Existing: Athena helpers
docs/
  examples.md               # NEW: 8-12 example SQL queries (QUERY-01..03)
  SCHEMA.md                 # NEW: Schema documentation (QUERY-04)
```

### Pattern 1: Validation Script Structure
**What:** Follow verify-tables.sh phased approach with pass/fail/warn reporting
**When to use:** For validate-data.sh

The script should follow this structure (derived from verify-tables.sh and verify-views.sh):
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/athena.sh"

# Argument parsing (--quick, --help, --bucket)
# main() function with:
#   Phase 1: Row count validation (raw_* vs Iceberg)
#   Phase 2: Spot-check validation (non-null, value ranges)
#   Summary report with pass/fail/warn counts
```

Key conventions from existing scripts:
- `readonly` arrays for table lists and check definitions
- `log_info`, `log_warn`, `log_error` for output
- `athena_query_scalar` for single-value queries
- Pass/fail counters with summary at end
- `--quick` flag to skip expensive checks
- `--help` flag using sed extraction from header comment
- Timer with elapsed time reporting
- Non-zero exit on any failures

### Pattern 2: Row Count Comparison with Tolerance
**What:** Compare raw_* external table counts to Iceberg table counts with a tolerance threshold
**When to use:** VAL-01 validation

Important details:
- 7 Iceberg tables but the raw-to-Iceberg mapping is not always 1:1
- `labels` table is a UNION ALL of `raw_labels_human` and `raw_labels_machine` -- must sum both raw counts
- All other tables map to a single raw_* table
- Tolerance should handle rows filtered during CTAS type casting (e.g., empty string -> NULL -> row still included, so counts should be very close or exact)
- A warn (not fail) for small mismatches; fail only for large discrepancies

Table-to-raw mapping:
| Iceberg Table | Raw Table(s) | Notes |
|---------------|-------------|-------|
| images | raw_images | 1:1 |
| class_descriptions | raw_class_descriptions | 1:1 |
| labels | raw_labels_human + raw_labels_machine | UNION ALL, sum both |
| bounding_boxes | raw_bounding_boxes | 1:1 |
| masks | raw_masks | 1:1 |
| relationships | raw_relationships | 1:1 |
| label_hierarchy | raw_label_hierarchy | 1:1 |

### Pattern 3: Spot-Check Validation
**What:** Pick an ImageID from live data, verify columns are non-null and within expected ranges
**When to use:** VAL-02 validation

Approach:
1. Query a sample ImageID from each table: `SELECT image_id FROM <table> LIMIT 1`
2. For that ImageID, verify key columns are non-null and within valid ranges
3. Coordinate columns (x_min, x_max, y_min, y_max): should be DOUBLE in 0.0-1.0 range
4. Confidence columns: should be DOUBLE in 0.0-1.0 range
5. Boolean columns (is_occluded, etc.): should be true or false
6. String columns (image_id, label_name): should be non-empty

This is a sanity check, not exhaustive testing. 2-3 spot-checks across different tables is sufficient.

### Pattern 4: Example Query Document Structure
**What:** Markdown file with SQL examples grouped by pattern
**When to use:** QUERY-01, QUERY-02, QUERY-03

```markdown
# Example SQL Queries

## Single-Table Queries
### [Title]
[Description of what this demonstrates]
\```sql
SELECT ...
\```

## Cross-Table Joins
### [Title]
[Description]
\```sql
SELECT ...
\```

## String Field Parsing
### [Title]
[Description]
\```sql
SELECT ...
\```
```

### Anti-Patterns to Avoid
- **Hardcoded spot-check values:** Do not hardcode expected ImageIDs or values -- they come from live data and may change if tables are rebuilt
- **SELECT * in examples:** Always use explicit column lists in example queries to be instructive
- **COUNT(*) without database prefix:** Always use `{ATHENA_DATABASE}.tablename` in validation script SQL
- **Auto-generating schema docs:** Hand-write with semantic context; auto-generated docs miss the "why" and domain meaning

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Athena query execution | Custom AWS API calls | athena_query_scalar / athena_execute_and_wait from athena.sh | Handles polling, error reporting, result extraction |
| Bucket discovery | Hardcoded bucket names | discover_bucket from common.sh | CloudFormation lookup with override support |
| Logging | echo statements | log_info/log_warn/log_error from common.sh | Consistent formatting with timestamps |
| CSV line counting | wc -l on local files | COUNT(*) on raw_* external tables | Files are in S3, not local; raw tables already exist |

**Key insight:** All infrastructure for querying Athena is already in athena.sh. The validation script only needs to compose SQL strings and call athena_query_scalar.

## Common Pitfalls

### Pitfall 1: Labels Table Has Two Raw Sources
**What goes wrong:** Comparing `COUNT(*) FROM labels` against `COUNT(*) FROM raw_labels` -- but raw_labels doesn't exist.
**Why it happens:** Labels is a UNION ALL of raw_labels_human and raw_labels_machine.
**How to avoid:** Sum counts from both raw tables: `SELECT (SELECT COUNT(*) FROM raw_labels_human) + (SELECT COUNT(*) FROM raw_labels_machine)`
**Warning signs:** "Table not found" error on raw_labels.

### Pitfall 2: Clicks Column Is Not JSON
**What goes wrong:** Using json_extract() on the clicks column in masks table.
**Why it happens:** QUERY-03 says "JSON field parsing" but clicks is semicolon-delimited, not JSON.
**How to avoid:** Use `split(clicks, ';')` and `cardinality()` for click parsing. This was established in Phase 4 (labeled_masks view).
**Warning signs:** json_extract returns NULL on all rows.

### Pitfall 3: Relationships View Drops Rows (Expected)
**What goes wrong:** Row count mismatch between relationships table and labeled_relationships view flagged as error.
**Why it happens:** INNER JOIN drops ~886 rows (3.3%) where label MIDs don't match class_descriptions. This is documented and accepted.
**How to avoid:** The validation script compares raw_* to Iceberg tables (not views). View count differences are already handled by verify-views.sh.
**Warning signs:** False alarm on relationships count.

### Pitfall 4: Athena Query Cost
**What goes wrong:** Running expensive full-table scans repeatedly during validation.
**Why it happens:** COUNT(*) on Iceberg tables is metadata-only (free), but on raw external tables it requires scanning.
**How to avoid:** Validation queries are all SELECT/COUNT -- minimal cost. The workgroup has per-query scan limits. This is acceptable per user decision (read-only, minimal cost).

### Pitfall 5: docs/ Directory Doesn't Exist Yet
**What goes wrong:** Script or process assumes docs/ already exists.
**Why it happens:** This is the first phase creating user-facing documentation.
**How to avoid:** Create docs/ directory as first step. The documentation files are manually authored, not generated by scripts.

## Code Examples

### Row Count Query Pattern
```bash
# Source: Established pattern from verify-views.sh lines 143-165
iceberg_count=$(athena_query_scalar \
  "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.images" \
  "count(images)")

raw_count=$(athena_query_scalar \
  "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.raw_images" \
  "count(raw_images)")

# For labels (special case: two raw tables)
raw_labels_count=$(athena_query_scalar \
  "SELECT (SELECT COUNT(*) FROM ${ATHENA_DATABASE}.raw_labels_human) + (SELECT COUNT(*) FROM ${ATHENA_DATABASE}.raw_labels_machine)" \
  "count(raw_labels)")
```

### Tolerance Comparison Pattern
```bash
# Compare with tolerance (e.g., 1% threshold)
local diff=$((iceberg_count - raw_count))
local abs_diff=${diff#-}  # absolute value
local threshold=$((raw_count / 100))  # 1%

if [[ $abs_diff -eq 0 ]]; then
  log_info "PASS: $table counts match exactly ($iceberg_count)"
elif [[ $abs_diff -le $threshold ]]; then
  log_warn "WARN: $table counts differ by $abs_diff (iceberg=$iceberg_count, raw=$raw_count) -- within ${threshold} tolerance"
else
  log_error "FAIL: $table counts differ by $abs_diff (iceberg=$iceberg_count, raw=$raw_count) -- exceeds tolerance"
fi
```

### Spot-Check Query Pattern
```bash
# Get a sample ImageID from the table
local sample_id
sample_id=$(athena_query_scalar \
  "SELECT image_id FROM ${ATHENA_DATABASE}.bounding_boxes LIMIT 1" \
  "sample(bounding_boxes)")

# Verify coordinate ranges
local check_sql="SELECT CASE
  WHEN x_min BETWEEN 0.0 AND 1.0
   AND x_max BETWEEN 0.0 AND 1.0
   AND y_min BETWEEN 0.0 AND 1.0
   AND y_max BETWEEN 0.0 AND 1.0
  THEN 'VALID' ELSE 'INVALID'
  END
FROM ${ATHENA_DATABASE}.bounding_boxes
WHERE image_id = '${sample_id}' LIMIT 1"
```

### Athena String Parsing (for examples.md)
```sql
-- Parse semicolon-delimited clicks column
-- Source: labeled_masks view (queries/views/03-labeled-masks.sql)
SELECT
  image_id,
  display_name,
  clicks,
  cardinality(split(clicks, ';')) AS click_count,
  split(clicks, ';') AS click_array
FROM open_images.labeled_masks
WHERE clicks IS NOT NULL AND clicks <> ''
LIMIT 10;
```

### Cross-Table Join Example (for examples.md)
```sql
-- Find images that have both a "Dog" label and bounding boxes
SELECT DISTINCT
  lb.image_id,
  lb.display_name,
  lb.x_min, lb.y_min, lb.x_max, lb.y_max,
  lb.box_area
FROM open_images.labeled_boxes lb
WHERE lb.display_name = 'Dog'
ORDER BY lb.box_area DESC
LIMIT 10;
```

### Label Hierarchy Query (for examples.md)
```sql
-- Find all child classes of a given parent (e.g., Animal)
SELECT
  h.parent_mid,
  p.display_name AS parent_name,
  h.child_mid,
  c.display_name AS child_name
FROM open_images.label_hierarchy h
JOIN open_images.class_descriptions p ON h.parent_mid = p.label_name
JOIN open_images.class_descriptions c ON h.child_mid = c.label_name
WHERE p.display_name = 'Animal';
```

## State of the Art

| Aspect | Current Approach | Notes |
|--------|------------------|-------|
| Athena SQL engine | Engine v3 (Trino-based) | split(), cardinality(), CASE expressions all supported |
| Iceberg COUNT(*) | Metadata-only operation | No data scanning required for row counts on Iceberg tables |
| External table COUNT(*) | Full scan required | Costs proportional to raw CSV size; acceptable for validation set (~500MB) |

## Open Questions

1. **Exact tolerance threshold for row count mismatches**
   - What we know: User said "small percentage, e.g., <1%". CTAS type casting shouldn't drop rows (NULL handling preserves them).
   - What's unclear: Whether counts will actually match exactly or differ slightly.
   - Recommendation: Use 1% threshold. Exact matches get PASS, small differences get WARN, large differences get FAIL.

2. **Which specific example queries to include**
   - What we know: Need 8-12 covering single-table, cross-table joins, and string parsing. Must cover all annotation types.
   - Recommendation: 7 single-table queries (one per table) + 3 cross-table join queries + 2 string parsing queries = 12 total.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash script with pass/fail assertions (no formal test framework) |
| Config file | N/A -- validation is the script itself |
| Quick run command | `bash scripts/validate-data.sh --quick` |
| Full suite command | `bash scripts/validate-data.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAL-01 | Row counts match between raw and Iceberg tables | integration (live Athena) | `bash scripts/validate-data.sh --quick` | No -- Wave 0 |
| VAL-02 | Spot-check values are valid | integration (live Athena) | `bash scripts/validate-data.sh` | No -- Wave 0 |
| QUERY-01 | 8-12 example queries exist in docs/examples.md | manual review | File existence check | No -- Wave 0 |
| QUERY-02 | Cross-table join examples exist | manual review | Grep for JOIN in docs/examples.md | No -- Wave 0 |
| QUERY-03 | String parsing examples exist | manual review | Grep for split in docs/examples.md | No -- Wave 0 |
| QUERY-04 | Schema documentation exists with full detail | manual review | File existence + completeness check | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** Verify file exists and has expected structure
- **Per wave merge:** Run `bash scripts/validate-data.sh` against live Athena
- **Phase gate:** All validation passes + both doc files complete

### Wave 0 Gaps
- [ ] `scripts/validate-data.sh` -- covers VAL-01, VAL-02
- [ ] `docs/examples.md` -- covers QUERY-01, QUERY-02, QUERY-03
- [ ] `docs/SCHEMA.md` -- covers QUERY-04
- [ ] `docs/` directory creation -- first documentation artifacts outside .planning/

## Sources

### Primary (HIGH confidence)
- Project codebase: scripts/verify-tables.sh, scripts/verify-views.sh -- established patterns
- Project codebase: scripts/lib/common.sh, scripts/lib/athena.sh -- shared library functions
- Project codebase: queries/tables/*.sql -- 7 table DDL files with column definitions and source CSV mappings
- Project codebase: queries/views/*.sql -- 4 view definitions with join logic and computed columns
- [AWS Athena Engine v3 docs](https://docs.aws.amazon.com/athena/latest/ug/engine-versions-reference-0003.html) -- Trino-based SQL functions
- [AWS Athena functions reference](https://docs.aws.amazon.com/athena/latest/ug/functions-env3.html) -- split, cardinality, etc.

### Secondary (MEDIUM confidence)
- Phase 4 STATE.md decisions -- INNER JOIN behavior, clicks parsing approach, row drop acceptance

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - fully established by prior phases, no new tools needed
- Architecture: HIGH - follows existing verify-tables.sh/verify-views.sh patterns exactly
- Pitfalls: HIGH - derived from actual codebase analysis (labels UNION ALL, clicks format, relationships row drop)

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (stable -- no fast-moving dependencies)
