# Phase 3: Iceberg Tables - Research

**Researched:** 2026-03-05
**Domain:** AWS Athena Iceberg tables, OpenCSVSerDe, Open Images V7 CSV schemas
**Confidence:** HIGH

## Summary

This phase creates 7 Iceberg tables from raw CSV data already in S3 using Athena DDL and CTAS. The approach is a two-step process per table: (1) CREATE EXTERNAL TABLE over CSV in raw/ using OpenCSVSerDe, (2) CREATE TABLE AS SELECT with type casting into Iceberg format backed by Parquet in warehouse/. The Open Images V7 validation CSV files have well-documented schemas with specific column headers that must be mapped to snake_case Iceberg columns with correct types.

The critical technical detail is that OpenCSVSerDe treats ALL columns as STRING regardless of declared types. Type casting MUST happen in the CTAS SELECT statement. Iceberg tables in Athena require `table_type = 'ICEBERG'` in TBLPROPERTIES (DDL) or WITH clause (CTAS), and cannot use the EXTERNAL keyword. Athena engine v3 is already configured in the workgroup.

**Primary recommendation:** Use OpenCSVSerDe external tables with all STRING columns, then CTAS with explicit CAST expressions to create Iceberg tables with correct types. One SQL file per table, executed sequentially by a shell runner script.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- One SQL file per table in `queries/tables/` directory (e.g., 01-images.sql, 02-class-descriptions.sql)
- Shell runner script (`scripts/create-tables.sh`) executes all SQL files in order via `aws athena start-query-execution`
- Idempotent: each SQL file starts with DROP TABLE IF EXISTS, then CREATE
- Runner reports success/failure per table
- Column names in snake_case (ImageID -> image_id, LabelName -> label_name, XMin -> x_min)
- Boolean flag columns as native BOOLEAN type, cast from 0/1
- Coordinate columns as DOUBLE
- JSON-structured annotation data stored as VARCHAR, queried with json_extract()
- Confidence scores as DOUBLE
- Two-step process: CREATE EXTERNAL TABLE over CSV (OpenCSVSerDe), then CTAS with type casting into Iceberg
- External tables kept after CTAS (not dropped), named with `raw_` prefix
- Iceberg tables use clean names (images, labels, etc.)
- All tables in same `open_images` Glue database
- No partitioning (42K validation images is small)
- Label hierarchy JSON pre-processed to CSV via `scripts/lib/flatten-hierarchy.sh` using jq
- CSV format: direct parent-child edges only (parent_mid, child_mid)
- Flattener called by the runner script before creating the hierarchy table

### Claude's Discretion
- Exact OpenCSVSerDe configuration (skip headers, escape chars)
- SQL file numbering/ordering within queries/tables/
- Error handling in the runner script (continue on failure vs fail fast)
- Mask table JSON column structure details

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TBL-01 | Image metadata Iceberg table | CSV schema mapped: ImageID, Subset, OriginalURL, OriginalLandingURL, License, AuthorProfileURL, Author, Title, OriginalSize, OriginalMD5, Thumbnail300KURL, Rotation |
| TBL-02 | Class descriptions Iceberg table | CSV schema mapped: LabelName, DisplayName (2-column no-header CSV) |
| TBL-03 | Image labels Iceberg table | CSV schema mapped: ImageID, Source, LabelName, Confidence -- combines human + machine label CSVs |
| TBL-04 | Bounding boxes Iceberg table | CSV schema mapped: ImageID, Source, LabelName, Confidence, XMin-YMax, boolean flags, XClick columns |
| TBL-05 | Segmentation masks Iceberg table | CSV schema mapped: MaskPath, ImageID, LabelName, BoxID, coordinates, PredictedIoU, Clicks (semicolon-delimited string, stored as VARCHAR) |
| TBL-06 | Visual relationships Iceberg table | CSV schema mapped: ImageID, LabelName1, LabelName2, coordinates for both objects, RelationLabel |
| TBL-07 | Label hierarchy Iceberg table | JSON hierarchy flattened to parent_mid/child_mid CSV via jq script |
| TBL-08 | All tables via Athena DDL | CTAS syntax with `table_type = 'ICEBERG'` documented |
| TBL-09 | CSV to Iceberg/Parquet via CTAS with type casting | OpenCSVSerDe -> STRING -> CAST in SELECT documented |
| TBL-10 | JSON-typed string columns parseable by json_extract | Clicks column is NOT JSON (semicolon-delimited); VRD has no JSON. JSON columns may only apply if mask metadata is stored as JSON VARCHAR |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version/Config | Purpose | Why Standard |
|------|---------------|---------|--------------|
| Athena Engine v3 | Already configured in workgroup | SQL engine for DDL/CTAS | Required for Iceberg v2 support |
| OpenCSVSerDe | `org.apache.hadoop.hive.serde2.OpenCSVSerde` | Parse raw CSV files | Standard Athena CSV parser |
| Apache Iceberg v2 | Created by Athena Engine v3 | Table format | Managed by Athena, Parquet-backed |
| AWS CLI v2 | `aws athena start-query-execution` | Execute SQL from shell | Standard automation approach |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| jq | Parse hierarchy JSON, flatten to CSV | Pre-processing bbox_labels_600_hierarchy.json |
| bash/common.sh | Logging, bucket discovery, AWS profile | Runner script infrastructure |

## Architecture Patterns

### Project Structure
```
queries/
└── tables/
    ├── 01-images.sql
    ├── 02-class-descriptions.sql
    ├── 03-labels.sql
    ├── 04-bounding-boxes.sql
    ├── 05-masks.sql
    ├── 06-relationships.sql
    └── 07-label-hierarchy.sql
scripts/
├── create-tables.sh          # Runner script
└── lib/
    ├── common.sh              # Existing shared functions
    └── flatten-hierarchy.sh   # New: JSON -> CSV converter
```

### Pattern 1: Two-Step CSV-to-Iceberg (per SQL file)

**What:** Each SQL file contains multiple statements executed sequentially: DROP existing tables, CREATE EXTERNAL TABLE over CSV, then CTAS into Iceberg.
**When to use:** Every table follows this pattern.

**Important:** Athena `start-query-execution` only supports ONE statement per call. Each SQL file must be split into individual statements by the runner, or the file must contain only one statement and multiple files used per table.

**Recommended approach:** Each SQL file contains a single logical table's DDL but the runner must extract and execute statements individually. Alternatively, use separate files per statement (01a-raw-images.sql, 01b-images.sql).

**External table example:**
```sql
-- Source: AWS Athena OpenCSVSerDe docs
CREATE EXTERNAL TABLE open_images.raw_images (
    image_id        string,
    subset          string,
    original_url    string,
    original_landing_url string,
    license         string,
    author_profile_url string,
    author          string,
    title           string,
    original_size   string,
    original_md5    string,
    thumbnail_300k_url string,
    rotation        string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://BUCKET/raw/metadata/'
TBLPROPERTIES ('skip.header.line.count' = '1')
```

**CTAS Iceberg example:**
```sql
-- Source: AWS Athena CTAS + Iceberg docs
CREATE TABLE open_images.images
WITH (
    table_type = 'ICEBERG',
    location = 's3://BUCKET/warehouse/images/',
    is_external = false,
    format = 'PARQUET',
    write_compression = 'SNAPPY'
) AS
SELECT
    image_id,
    subset,
    original_url,
    original_landing_url,
    license,
    author_profile_url,
    author,
    title,
    CAST(original_size AS int) AS original_size,
    original_md5,
    thumbnail_300k_url,
    CAST(rotation AS int) AS rotation
FROM open_images.raw_images
```

### Pattern 2: Runner Script with Polling

**What:** Shell script that executes SQL via `aws athena start-query-execution`, polls with `get-query-execution`, reports results.
**When to use:** The `scripts/create-tables.sh` runner.

```bash
# Execute a single SQL statement and wait for completion
run_athena_query() {
    local sql="$1"
    local description="$2"

    local query_id
    query_id=$(aws athena start-query-execution \
        --query-string "$sql" \
        --work-group "open-images" \
        --query-execution-context "Database=open_images,Catalog=AwsDataCatalog" \
        --profile "$AWS_PROFILE" \
        --output text \
        --query 'QueryExecutionId')

    log_info "Started: $description (ID: $query_id)"

    # Poll until complete
    local status="RUNNING"
    while [[ "$status" == "RUNNING" || "$status" == "QUEUED" ]]; do
        sleep 2
        status=$(aws athena get-query-execution \
            --query-execution-id "$query_id" \
            --profile "$AWS_PROFILE" \
            --output text \
            --query 'QueryExecution.Status.State')
    done

    if [[ "$status" == "SUCCEEDED" ]]; then
        log_info "Succeeded: $description"
        return 0
    else
        local reason
        reason=$(aws athena get-query-execution \
            --query-execution-id "$query_id" \
            --profile "$AWS_PROFILE" \
            --output text \
            --query 'QueryExecution.Status.StateChangeReason')
        log_error "Failed: $description -- $reason"
        return 1
    fi
}
```

### Pattern 3: Hierarchy JSON Flattening

**What:** Use jq to extract parent-child edges from the nested hierarchy JSON.
**Structure of bbox_labels_600_hierarchy.json:**
```json
{
  "LabelName": "/m/0bl9f",
  "Subcategory": [
    {
      "LabelName": "/m/0242l",
      "Subcategory": [
        { "LabelName": "/m/0167gd" },
        { "LabelName": "/m/01j51" }
      ]
    }
  ]
}
```

Each node has `LabelName` (string), optional `Subcategory` (array), and optional `Part` (array). The flattener must recursively walk the tree and emit `parent_mid,child_mid` rows for both Subcategory and Part relationships.

**jq approach:**
```bash
# Recursive descent extracting parent->child edges
jq -r '
  def edges:
    .LabelName as $parent |
    ((.Subcategory // [])[] | "\($parent),\(.LabelName)", edges),
    ((.Part // [])[] | "\($parent),\(.LabelName)", edges);
  edges
' bbox_labels_600_hierarchy.json > label_hierarchy.csv
```

### Anti-Patterns to Avoid
- **Declaring typed columns in OpenCSVSerDe tables:** OpenCSVSerDe treats ALL values as STRING regardless of column type declaration. Declaring `int` or `double` in the external table gives false confidence -- values remain strings. Always declare STRING and CAST in CTAS.
- **Using CREATE EXTERNAL TABLE for Iceberg:** Athena rejects `EXTERNAL` keyword for Iceberg tables. Use CTAS with `is_external = false`.
- **Multi-statement SQL in start-query-execution:** Athena only allows ONE statement per execution. The runner must split or use separate files.
- **Using LOCATION in external table pointing to a file:** LOCATION must point to the S3 PREFIX (directory), not a specific file. Multiple CSV files in the same prefix will all be read.
- **Forgetting skip.header.line.count:** Without this TBLPROPERTY, the CSV header row will be ingested as data.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV parsing | Custom Lambda/script to parse CSV | OpenCSVSerDe + Athena | Handles quoting, escaping, edge cases |
| Parquet conversion | Custom Spark/pandas job | Athena CTAS | Automatic Parquet + Iceberg metadata generation |
| Query polling | Ad-hoc sleep/check | Structured poll loop with status checks | Need to handle QUEUED, RUNNING, SUCCEEDED, FAILED, CANCELLED |
| JSON hierarchy walking | Python/Node script | jq recursive descent | Already a project dependency, single expression |

## Common Pitfalls

### Pitfall 1: OpenCSVSerDe Treats Everything as STRING
**What goes wrong:** Columns declared as INT or DOUBLE in the external table still return strings. Queries on the external table that expect numeric comparison fail silently.
**Why it happens:** OpenCSVSerDe ignores column type declarations and returns all values as STRING.
**How to avoid:** Declare ALL external table columns as STRING. Perform ALL type casting in the CTAS SELECT statement.
**Warning signs:** Unexpected query results, string comparison instead of numeric comparison.

### Pitfall 2: LOCATION Must Be a Directory Prefix
**What goes wrong:** External table returns zero rows.
**Why it happens:** LOCATION pointed to a specific file instead of the S3 prefix/directory.
**How to avoid:** Always use trailing slash in LOCATION: `s3://bucket/raw/annotations/` not `s3://bucket/raw/annotations/file.csv`. If multiple CSVs exist in the same prefix, they ALL get read.
**Warning signs:** Zero rows returned, or unexpected rows from other CSV files in the same prefix.

### Pitfall 3: Multiple CSVs in Same S3 Prefix
**What goes wrong:** The annotations/ prefix contains ALL annotation CSVs (human labels, machine labels, bboxes, segmentation, VRD). Pointing an external table LOCATION to `s3://bucket/raw/annotations/` reads ALL of them together.
**Why it happens:** Athena reads all files under the LOCATION prefix.
**How to avoid:** Each external table must point to a LOCATION that contains ONLY its source file. Options: (a) use specific subdirectories, or (b) partition the external table, or (c) move/copy files to table-specific prefixes, or (d) use a different approach entirely. **Best option for this project:** Since the files are already uploaded, create the external table pointing to the full annotations/ prefix but use a WHERE clause or restructure. Actually, the simplest approach: create external tables that point to the full prefix but since each CSV has different column counts, OpenCSVSerDe will just fill extra columns with NULL or truncate. This is FRAGILE. **Recommended:** Use S3 prefix per table or accept that you need to re-organize raw files.
**Warning signs:** Wrong data, column misalignment, mixed file formats.

### Pitfall 4: Class Descriptions CSV Has No Header
**What goes wrong:** First row of actual data gets skipped.
**Why it happens:** `oidv7-class-descriptions.csv` may not have a header row (it's just `LabelName,DisplayName` with no header). Setting `skip.header.line.count=1` on a headerless file loses the first data row.
**How to avoid:** Verify whether each CSV has a header before setting skip.header.line.count. The class descriptions file format varies by source -- check the actual file.

### Pitfall 5: Iceberg CTAS Fails if Table Already Exists
**What goes wrong:** Re-running CTAS fails because the Iceberg table already exists.
**Why it happens:** CTAS does not support IF NOT EXISTS for Iceberg tables.
**How to avoid:** Each SQL execution must DROP TABLE IF EXISTS before the CTAS. Since the runner executes statements one at a time, the sequence is: (1) DROP TABLE IF EXISTS iceberg_table, (2) DROP TABLE IF EXISTS raw_table, (3) CREATE EXTERNAL TABLE raw_table, (4) CTAS iceberg_table.

### Pitfall 6: S3 Location Prefix Collision Between Tables
**What goes wrong:** Two Iceberg tables pointing to overlapping warehouse/ locations corrupt each other's data.
**Why it happens:** Iceberg writes metadata and data files under the LOCATION prefix.
**How to avoid:** Each Iceberg table gets its own unique prefix: `s3://bucket/warehouse/images/`, `s3://bucket/warehouse/labels/`, etc.

### Pitfall 7: Boolean Casting from String "0"/"1"
**What goes wrong:** CAST('0' AS BOOLEAN) may not work as expected in Athena.
**Why it happens:** Athena CAST to BOOLEAN expects 'true'/'false' strings, not '0'/'1'.
**How to avoid:** Use a CASE expression: `CASE WHEN is_occluded = '1' THEN true ELSE false END`.

## Code Examples

### Complete External Table: Bounding Boxes
```sql
-- Source: Open Images V7 validation-annotations-bbox.csv headers
CREATE EXTERNAL TABLE open_images.raw_bounding_boxes (
    image_id      string,
    source        string,
    label_name    string,
    confidence    string,
    x_min         string,
    x_max         string,
    y_min         string,
    y_max         string,
    is_occluded   string,
    is_truncated  string,
    is_group_of   string,
    is_depiction  string,
    is_inside     string,
    x_click_1x    string,
    x_click_2x    string,
    x_click_3x    string,
    x_click_4x    string,
    x_click_1y    string,
    x_click_2y    string,
    x_click_3y    string,
    x_click_4y    string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://BUCKET/raw/annotations/bbox/'
TBLPROPERTIES ('skip.header.line.count' = '1')
```

### Complete CTAS: Bounding Boxes to Iceberg
```sql
CREATE TABLE open_images.bounding_boxes
WITH (
    table_type = 'ICEBERG',
    location = 's3://BUCKET/warehouse/bounding_boxes/',
    is_external = false,
    format = 'PARQUET',
    write_compression = 'SNAPPY'
) AS
SELECT
    image_id,
    source,
    label_name,
    CAST(confidence AS double) AS confidence,
    CAST(x_min AS double) AS x_min,
    CAST(x_max AS double) AS x_max,
    CAST(y_min AS double) AS y_min,
    CAST(y_max AS double) AS y_max,
    CASE WHEN is_occluded = '1' THEN true ELSE false END AS is_occluded,
    CASE WHEN is_truncated = '1' THEN true ELSE false END AS is_truncated,
    CASE WHEN is_group_of = '1' THEN true ELSE false END AS is_group_of,
    CASE WHEN is_depiction = '1' THEN true ELSE false END AS is_depiction,
    CASE WHEN is_inside = '1' THEN true ELSE false END AS is_inside
FROM open_images.raw_bounding_boxes
```

### Boolean Casting Pattern
```sql
-- Athena CAST('0' AS BOOLEAN) does NOT work for 0/1 integers-as-strings
-- Use CASE expression instead:
CASE WHEN column_name = '1' THEN true ELSE false END AS column_name
```

### Runner Script: Athena Query Execution with Polling
```bash
# See Architecture Patterns > Pattern 2 for full implementation
# Key: aws athena start-query-execution returns QueryExecutionId
# Poll with: aws athena get-query-execution --query-execution-id ID
# Status values: QUEUED | RUNNING | SUCCEEDED | FAILED | CANCELLED
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Athena Engine v2 + Iceberg v1 | Engine v3 + Iceberg v2 | 2023 | Better performance, merge-on-read |
| Glue ETL for CSV->Parquet | Athena CTAS | Always available | No EMR/Glue ETL needed for small data |
| LazySimpleSerDe for CSV | OpenCSVSerDe | N/A | Better handling of quoted fields |

## Open Questions

1. **S3 prefix per CSV file for external tables**
   - What we know: Raw CSVs are uploaded to `s3://bucket/raw/annotations/` and `s3://bucket/raw/metadata/`. Multiple CSV files with different schemas share these prefixes.
   - What's unclear: Whether external tables can filter to specific files within a prefix, or if files need to be reorganized.
   - Recommendation: The runner script should copy/move each CSV to a table-specific sub-prefix before creating external tables (e.g., `raw/annotations/bbox/validation-annotations-bbox.csv`). Alternatively, use S3 Select or a different SerDe that can handle this. **Simplest: the runner script creates symlinks via `aws s3 cp` to table-specific prefixes before table creation.**

2. **Class descriptions CSV header presence**
   - What we know: The format is LabelName,DisplayName but the download page does not clarify if there is a header row.
   - What's unclear: Whether `skip.header.line.count=1` should be set.
   - Recommendation: Check the actual file in S3 or download a sample. Most Open Images CSVs DO have headers.

3. **TBL-10 JSON columns -- what exactly needs json_extract?**
   - What we know: The Clicks column in segmentation masks is semicolon-delimited (NOT JSON). The VRD CSV has no JSON columns. The requirement says "JSON-typed string columns parseable by json_extract."
   - What's unclear: Which actual columns contain JSON. This may refer to storing the Clicks data AS JSON VARCHAR after transformation, or to mask metadata added in Phase 4 (MASK-01).
   - Recommendation: Store Clicks as-is (VARCHAR). If json_extract support is needed for Phase 4/5, the mask enrichment phase (MASK-01) will add JSON columns. For Phase 3, ensure VARCHAR columns are used where future JSON storage is anticipated.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell script + Athena SQL queries |
| Config file | None -- tests are embedded in runner verification |
| Quick run command | `aws athena start-query-execution --query-string "SELECT COUNT(*) FROM open_images.images" --work-group open-images` |
| Full suite command | `scripts/create-tables.sh` (idempotent, re-creates all tables) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TBL-01 | images table exists with correct schema | smoke | `SELECT * FROM open_images.images LIMIT 1` via Athena | No -- Wave 0 |
| TBL-02 | class_descriptions table exists | smoke | `SELECT * FROM open_images.class_descriptions LIMIT 1` | No -- Wave 0 |
| TBL-03 | labels table exists with combined data | smoke | `SELECT * FROM open_images.labels LIMIT 1` | No -- Wave 0 |
| TBL-04 | bounding_boxes table with correct types | smoke | `SELECT typeof(x_min), typeof(is_occluded) FROM open_images.bounding_boxes LIMIT 1` | No -- Wave 0 |
| TBL-05 | masks table exists | smoke | `SELECT * FROM open_images.masks LIMIT 1` | No -- Wave 0 |
| TBL-06 | relationships table exists | smoke | `SELECT * FROM open_images.relationships LIMIT 1` | No -- Wave 0 |
| TBL-07 | label_hierarchy table exists | smoke | `SELECT * FROM open_images.label_hierarchy LIMIT 1` | No -- Wave 0 |
| TBL-08 | Tables created via Athena DDL | manual-only | Verify via Glue catalog that table_type=ICEBERG | No |
| TBL-09 | Correct type casting | smoke | `SELECT typeof(confidence) FROM open_images.bounding_boxes LIMIT 1` (should be 'double') | No -- Wave 0 |
| TBL-10 | JSON columns parseable | smoke | `SELECT json_extract(clicks_json, '$.x') FROM open_images.masks LIMIT 1` if applicable | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** Run SELECT LIMIT 1 against newly created table
- **Per wave merge:** Re-run full `scripts/create-tables.sh` + SELECT from each table
- **Phase gate:** All 7 tables queryable, types verified via typeof()

### Wave 0 Gaps
- [ ] `scripts/verify-tables.sh` -- smoke test script that runs SELECT against all 7 tables and checks row counts > 0 and column types
- [ ] `queries/tables/` directory -- does not exist yet, needs creation

## Sources

### Primary (HIGH confidence)
- [AWS Athena - Create Iceberg tables](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-creating-tables.html) -- CREATE TABLE syntax, TBLPROPERTIES, CTAS for Iceberg
- [AWS Athena - OpenCSVSerDe](https://docs.aws.amazon.com/athena/latest/ug/csv-serde.html) -- SerDe configuration, STRING-only behavior, skip.header.line.count
- [AWS Athena - CTAS](https://docs.aws.amazon.com/athena/latest/ug/create-table-as.html) -- CTAS WITH clause for Iceberg, required properties
- [AWS Athena - Iceberg data types](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-supported-data-types.html) -- Supported types: boolean, int, long/bigint, double, float, string, date, timestamp
- [Open Images V7 download page](https://storage.googleapis.com/openimages/web/download_v7.html) -- CSV column headers for all annotation files

### Secondary (MEDIUM confidence)
- [AWS CLI - start-query-execution](https://docs.aws.amazon.com/cli/latest/reference/athena/start-query-execution.html) -- CLI syntax for query execution
- [Open Images hierarchy JSON](https://storage.googleapis.com/openimages/2018_04/bbox_labels_600_hierarchy.json) -- Actual JSON structure: LabelName, Subcategory[], Part[]

### Tertiary (LOW confidence)
- Boolean CAST behavior with '0'/'1' strings -- verified pattern from multiple community sources, but should be validated against actual Athena engine v3 behavior

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- AWS official docs verified, all syntax confirmed
- Architecture: HIGH -- two-step CSV->Iceberg pattern well-documented, project conventions established
- Pitfalls: HIGH -- OpenCSVSerDe STRING behavior, EXTERNAL keyword prohibition for Iceberg confirmed in official docs
- CSV schemas: HIGH -- column headers verified from Open Images download page
- S3 prefix handling: MEDIUM -- multiple CSVs sharing prefixes needs resolution at implementation time

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (stable AWS service, stable dataset)
