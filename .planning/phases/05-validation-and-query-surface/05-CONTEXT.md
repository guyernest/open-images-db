# Phase 5: Validation and Query Surface - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Validate data quality across all Iceberg tables (row counts vs source, spot-checks) and deliver the query surface for downstream MCP server team (example SQL queries and schema documentation). No new tables or views -- this phase validates and documents what was built.

</domain>

<decisions>
## Implementation Decisions

### Validation approach
- New `scripts/validate-data.sh` script (separate from verify-tables.sh which checks structure)
- Row count validation (VAL-01): queries raw_* external tables and Iceberg tables, compares counts
- Tolerance allowed for count mismatches (small percentage, e.g., <1%) -- some rows may be filtered during CTAS type casting
- Spot-check validation (VAL-02): picks values from live data, verifies specific ImageIDs have non-null columns within valid ranges (not hardcoded known values)
- Script sources common.sh + athena.sh, follows established runner pattern

### Example query organization
- Single markdown file: `docs/examples.md`
- Grouped by query pattern: single-table queries, cross-table joins, JSON/string field parsing
- Each query has title, description of what it demonstrates, and SQL block (no sample output -- keeps docs maintainable)
- Examples use both base tables and convenience views -- downstream team sees both options
- Must cover 8-12 queries total across all annotation types (QUERY-01, QUERY-02, QUERY-03)

### Schema documentation format
- Single markdown file: `docs/SCHEMA.md`
- Hand-written from SQL files (not auto-generated) -- includes semantic context
- Full detail per table/view: column name, type, description, source CSV column mapping, nullable, example domain
- Views section includes which tables each view joins and explains computed columns
- Source CSV mapping traces each column back to its original CSV file and column name (QUERY-04)

### Execution strategy
- Fully autonomous -- validation script runs only SELECT queries (read-only, minimal cost)
- Example queries verified against live Athena to confirm they actually work (catches typos and schema mismatches)

### Claude's Discretion
- Specific ImageIDs used for spot-checks (discovered from live data)
- Exact tolerance threshold for row count mismatches
- Which 8-12 example queries to write (covering all annotation types and patterns)
- Schema description wording and column semantics

</decisions>

<specifics>
## Specific Ideas

- Validation script follows existing verify-tables.sh / verify-views.sh patterns (banner, phase-based checks, summary)
- docs/ directory is new -- this is the first phase creating user-facing documentation files
- Downstream MCP server team is the primary consumer of both docs/SCHEMA.md and docs/examples.md
- QUERY-03 about "JSON field parsing" should reference the clicks column's semicolon-delimited format (not actual JSON), demonstrating split() and cardinality()

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/lib/common.sh`: Logging, prerequisites check, bucket discovery, AWS profile
- `scripts/lib/athena.sh`: athena_execute_and_wait, athena_query_scalar, run_athena_query (with dry-run support)
- `scripts/verify-tables.sh` and `scripts/verify-views.sh`: Verification script patterns (phased checks, column checks, count comparisons)
- `raw_*` external tables in Athena: Available for row count comparison against Iceberg tables
- 7 table SQL files in `queries/tables/`: Source of truth for column names, types, and source CSV mappings
- 4 view SQL files in `queries/views/`: Source of truth for view joins and computed columns

### Established Patterns
- Shell scripts source common.sh + athena.sh for shared functions
- Numbered SQL files in queries/ subdirectories
- Verification scripts use phased approach (existence, columns, counts) with pass/fail/warn reporting
- Scripts are idempotent and support --quick and --help flags

### Integration Points
- Validation queries run against open_images database via Athena workgroup open-images
- Schema docs reference tables/views created in Phases 3-4
- Example queries reference both base tables and convenience views
- docs/ directory will be new -- first documentation artifacts outside .planning/

</code_context>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 05-validation-and-query-surface*
*Context gathered: 2026-03-06*
