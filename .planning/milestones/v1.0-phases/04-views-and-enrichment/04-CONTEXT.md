# Phase 4: Views and Enrichment - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Create 4 Athena convenience views joining images with human-readable labels for each annotation type (labels, bounding boxes, masks, relationships), plus an enriched masks view with pre-computed geometry metadata. All views are virtual (CREATE OR REPLACE VIEW) -- no materialized tables or data movement.

</domain>

<decisions>
## Implementation Decisions

### View SQL organization
- View SQL files live in `queries/views/` directory (parallel to `queries/tables/`)
- Numbered files: 01-labeled-images.sql, 02-labeled-boxes.sql, etc. (consistent with tables pattern)
- New `scripts/create-views.sh` runner script sources common.sh, executes all view SQL files via Athena
- Idempotent via CREATE OR REPLACE VIEW (no DROP needed, unlike tables)

### View join design
- Full denormalization: each view includes image metadata (url, dimensions, license) + human-readable display_name + all annotation columns
- Labeled images view (VIEW-01) combines human AND machine labels in one view (labels table already has source column for filtering)
- Relationships view joins class_descriptions twice: label_name_1 -> display_name_1, label_name_2 -> display_name_2
- Views include computed convenience columns where useful (e.g., box_area, aspect_ratio, center coordinates for bounding boxes)

### Mask enrichment approach
- Athena SQL only -- no external processing or shell scripts for mask geometry
- Implemented as a view (not materialized table) -- fine at 42K validation set scale
- Computed geometry fields from bounding box coordinates: box_area, box_center_x, box_center_y, box_width, box_height
- Parse clicks JSON column using json_extract to expose key fields as named columns

### Execution strategy
- Fully autonomous -- no human checkpoint needed (views are safe, no cost, no data mutation)
- New `scripts/verify-views.sh` checks each view returns rows and has expected columns (consistent with verify-tables.sh pattern)
- Runs after create-views.sh

### Claude's Discretion
- Exact computed column formulas and naming
- Which clicks JSON fields to extract (based on actual data inspection)
- View column ordering and aliasing
- Verification script check details

</decisions>

<specifics>
## Specific Ideas

- Follow existing script conventions: source common.sh, discover_bucket, same AWS profile pattern
- Runner script should report success/failure per view (consistent with create-tables.sh)
- Views serve the downstream MCP server team -- full denormalization means they can query one view per annotation type without joins

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/lib/common.sh`: Logging, prerequisites check, bucket discovery, AWS profile
- `scripts/create-tables.sh`: Runner pattern for executing SQL files via Athena CLI (model for create-views.sh)
- `scripts/verify-tables.sh`: Verification pattern for checking table existence and row counts (model for verify-views.sh)
- 7 Iceberg tables in `open_images` database: images, class_descriptions, labels, bounding_boxes, masks, relationships, label_hierarchy

### Established Patterns
- SQL files numbered sequentially in queries/ subdirectories
- Shell scripts source common.sh, use discover_bucket for S3 paths
- Athena queries run via `aws athena start-query-execution` with polling
- Idempotent operations (safe to re-run)

### Integration Points
- Views read from Iceberg tables created in Phase 3 (open_images database)
- Athena workgroup: open-images (10GB scan limit, engine v3)
- Views will be queried by Phase 5 example queries and downstream MCP server
- Masks table clicks column is VARCHAR with JSON data -- json_extract compatible

</code_context>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 04-views-and-enrichment*
*Context gathered: 2026-03-06*
