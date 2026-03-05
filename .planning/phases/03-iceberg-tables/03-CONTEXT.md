# Phase 3: Iceberg Tables - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Create and populate 7 Iceberg tables from raw CSV data in S3 using Athena DDL/CTAS. Tables: images, class_descriptions, labels, bounding_boxes, masks, relationships, label_hierarchy. All tables backed by Parquet in the warehouse/ zone. No views or enrichment -- just base tables with correct schemas and types.

</domain>

<decisions>
## Implementation Decisions

### SQL script organization
- One SQL file per table in `queries/tables/` directory (e.g., 01-images.sql, 02-class-descriptions.sql)
- Shell runner script (`scripts/create-tables.sh`) executes all SQL files in order via `aws athena start-query-execution`
- Idempotent: each SQL file starts with DROP TABLE IF EXISTS, then CREATE
- Runner reports success/failure per table

### Schema design
- Column names in snake_case (ImageID -> image_id, LabelName -> label_name, XMin -> x_min)
- Boolean flag columns (IsOccluded, IsTruncated, IsGroupOf, IsDepiction, IsInside) as native BOOLEAN type, cast from 0/1
- Coordinate columns (XMin, XMax, YMin, YMax) as DOUBLE
- JSON-structured annotation data stored as VARCHAR, queried with Athena json_extract() (TBL-10)
- Confidence scores as DOUBLE

### CTAS execution approach
- Two-step process: CREATE EXTERNAL TABLE over CSV in raw/ (OpenCSVSerDe), then CREATE TABLE ... AS SELECT with type casting into Iceberg in warehouse/
- External tables kept after CTAS (not dropped) -- useful for debugging, re-running, and Phase 5 row count validation
- External tables named with `raw_` prefix (raw_images, raw_labels, etc.), Iceberg tables use clean names (images, labels, etc.)
- All tables in same `open_images` Glue database
- No partitioning -- 42K validation images is small; partitioning deferred to v2 (SCALE-02)

### Label hierarchy ingestion
- Open Images hierarchy JSON pre-processed to CSV via shell + jq script in `scripts/lib/flatten-hierarchy.sh`
- CSV format: direct parent-child edges only (parent_mid, child_mid) -- no transitive closure
- Transitive hierarchy queries use recursive CTEs (Phase 4/5 concern)
- Flattener called by the table runner script before creating the hierarchy table

### Claude's Discretion
- Exact OpenCSVSerDe configuration (skip headers, escape chars)
- SQL file numbering/ordering within queries/tables/
- Error handling in the runner script (continue on failure vs fail fast)
- Mask table JSON column structure details

</decisions>

<specifics>
## Specific Ideas

- Consistent with Phase 2's idempotency pattern -- re-running the pipeline should be safe
- Runner script follows existing `scripts/` conventions (sources common.sh, uses discover_bucket, same AWS profile)
- The `queries/` directory was decided in Phase 1 context as the location for SQL files

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/lib/common.sh`: Logging (log_info/warn/error), prerequisites check, bucket discovery from CloudFormation, AWS profile (`ze-kasher-dev`), upload_to_s3 helper
- CDK stack outputs: BucketName, DatabaseName (open_images), WorkgroupName (open-images)
- Download scripts in `scripts/lib/` establish the pattern for new scripts

### Established Patterns
- Shell scripts source common.sh for shared functions
- AWS profile stored as `readonly AWS_PROFILE` in common.sh
- Bucket discovered from CloudFormation stack outputs
- Scripts are idempotent (safe to re-run)
- Project layout: infra/ (CDK), scripts/ (shell pipeline), queries/ (SQL)

### Integration Points
- Raw CSVs in S3: `s3://{bucket}/raw/annotations/` and `s3://{bucket}/raw/metadata/`
- Iceberg tables write to: `s3://{bucket}/warehouse/`
- Glue database: `open_images` (configured in CDK with warehouse/ locationUri)
- Athena workgroup: `open-images` (10GB scan limit, engine v3)
- Athena results: `s3://{bucket}/athena-results/`
- Source CSV files: oidv7-val-annotations-human-imagelabels.csv, oidv7-val-annotations-machine-imagelabels.csv, validation-annotations-bbox.csv, validation-annotations-object-segmentation.csv, oidv6-validation-annotations-vrd.csv, oidv7-class-descriptions.csv, validation-images-with-rotation.csv

</code_context>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 03-iceberg-tables*
*Context gathered: 2026-03-05*
