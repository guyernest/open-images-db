# Phase 6: Relationship & Hierarchy Audit - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Audit what relationship and hierarchy data exists in the validation set, understand its structure, and identify gaps. Determine whether missing data (e.g., "people on horses") is absent from the source data or lost in our processing pipeline. Focused on relationships and hierarchy only — not other annotation types.

</domain>

<decisions>
## Implementation Decisions

### Audit scope
- Inventory only — catalog what's in our validation set tables, don't compare against full Open Images V7 spec
- Audit BOTH the labeled_relationships view AND the raw relationships table (including the 886 rows dropped by INNER JOIN)
- Focus on relationships and hierarchy only — not labels, boxes, or masks
- Flag that hierarchy covers only ~600 boxable labels while class_descriptions has ~20K labels (note the gap even if we don't fix it)
- Key question: are missing relationships due to the smaller validation subset, or a pipeline processing issue?

### Output format
- SQL scripts in queries/audit/ directory (new, alongside existing queries/tables/ and queries/views/)
- Shell runner script (scripts/run-audit.sh) following existing patterns (create-tables.sh, create-views.sh)
- Markdown report summarizing findings and conclusions
- Both reproducible queries AND written analysis

### Gap definition
- Audit both data existence AND query discoverability — equally important
- Classify each gap by cause: missing from source data vs lost in pipeline vs not queryable through views
- Specifically trace the 886 dropped INNER JOIN rows to understand which relationship types and entity pairs are lost
- Findings feed directly into Phase 7 fixes

### Hierarchy depth
- Full structural analysis: root node(s), max depth, branch density, and coverage
- Distinguish between Subcategory (is-a) and Part (has-part) edge types — the flattener currently treats both as parent-child
- Produce text tree visualization (at least top levels) plus quantitative stats
- Identify which branches are rich (many children) vs sparse

### Claude's Discretion
- Specific SQL query design and optimization
- Order of audit checks
- Level of detail in text tree (how many levels to show)
- Markdown report structure and formatting

</decisions>

<specifics>
## Specific Ideas

- User tried searching for "people on horses" and didn't find it — this is the motivating example. The audit should be able to explain why.
- The validation set is a subset of the larger dataset. If relationships are missing because of the subset, the user can increase the dataset. The audit should make this determination clear.
- The hierarchy JSON has both Subcategory and Part arrays — our flatten-hierarchy.sh processes both but doesn't distinguish them in the output CSV.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `queries/tables/06-relationships.sql`: Relationships Iceberg table (label_name_1, label_name_2, relationship_label, bounding box coords)
- `queries/tables/07-label-hierarchy.sql`: Hierarchy table (parent_mid, child_mid) — flat edges only
- `queries/tables/02-class-descriptions.sql`: MID-to-display-name mapping
- `queries/views/04-labeled-relationships.sql`: View joining relationships with class_descriptions (double join for both labels)
- `scripts/lib/flatten-hierarchy.sh`: Flattens bbox_labels_600_hierarchy.json to CSV using jq recursive descent

### Established Patterns
- Shell runner scripts execute SQL files via Athena CLI (create-tables.sh, create-views.sh pattern)
- SQL files use fully-qualified open_images.tablename references
- Runner scripts continue on failure and report all errors at end (not fail-fast)
- AWS profile stored as configurable readonly variable in common.sh

### Integration Points
- Audit queries read from existing Iceberg tables and views
- New queries/audit/ directory fits alongside existing queries/tables/ and queries/views/
- Shell runner follows same pattern as scripts/create-tables.sh

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-relationship-hierarchy-audit*
*Context gathered: 2026-03-08*
