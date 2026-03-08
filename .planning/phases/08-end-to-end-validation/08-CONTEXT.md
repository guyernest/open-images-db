# Phase 8: End-to-End Validation - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify that the fixed relationship and hierarchy data is discoverable and useful through queries that an MCP server would execute. Produce a validation script, validation report, MCP reference resource, and additional MCP-pattern example queries. Does not modify existing views or tables — this is pure validation and documentation.

</domain>

<decisions>
## Implementation Decisions

### MCP server context
- MCP server operates in two modes:
  1. **Tool mode (80%):** Pre-built tools mapped to SQL queries, covering common requests
  2. **Code mode (20%):** MCP client LLM generates SQL on-the-fly using resources (schema, examples, common values, failed query patterns) to handle the long tail of user requests
- Phase 8 must support BOTH modes — example queries for tool mode, reference resource for code mode
- Goal: minimize steps for the MCP client LLM to answer any query, including deep analytical queries using Athena functions

### MCP example queries
- Validate all 4 existing Phase 7 example queries (01-04) against live Athena
- Add 4 new MCP-pattern examples (numbered 05-08) in same queries/examples/ directory:
  1. Entity search — "find images of dogs playing" using hierarchy expansion + relationship filter
  2. Category exploration — "what categories exist under Animal?" using class_hierarchy subtree
  3. Image contents — "what's in this image?" joining labels, boxes, relationships for a single image_id
  4. Relationship inventory — "what relationships involve cars?" using hierarchy_relationships grouped by type
- Each new example includes natural language prompt as comment header + SQL + expected output

### MCP reference resource
- Create queries/examples/00-mcp-reference.sql — LLM-optimized reference for code mode context injection
- Content (all four sections):
  1. Schema with semantics — all tables and views with column names, types, and plain-English descriptions
  2. Common values enumeration — all 27 relationship types, top hierarchy branches with subtrees (from audit report data)
  3. Query pattern cookbook — reusable SQL patterns: hierarchy expansion, ancestor filtering, multi-table joins, window functions, aggregation
  4. Known pitfalls — raw MIDs vs display names, INNER JOIN drops, edge_type filtering, recursive CTE depth limits
- Values sourced from audit report (stable); validation script confirms accuracy against live Athena

### Validation approach
- Automated validation script: scripts/run-validation.sh
- Follows existing runner patterns (sources athena.sh, dry-run support, continue on failure)
- Live Athena execution (not dry-run only) — definitive proof everything works
- Four validation check types:
  1. Non-empty results — every query returns at least 1 row
  2. Human-readable names present — display columns contain real names, not raw MIDs
  3. Row count sanity — counts fall within expected ranges from audit data (not exact match)
  4. Cross-view consistency — same entity queried through different views returns consistent results

### Round-trip verification
- Trace specific entities end-to-end from raw tables → views → query results
- 2-3 automated traces in the validation script:
  1. Man on Horse (relationship): raw relationships → labeled_relationships → hierarchy_relationships
  2. Animal subtree (hierarchy): label_hierarchy → class_hierarchy → verify Dog, Cat, Horse appear
  3. Woman wears Hat (relationship): different relationship type, same pipeline trace
- Verify: Layer 2 rows ⊆ Layer 3 rows (hierarchy expansion only adds, never drops)

### Deliverables
- Three outputs:
  1. scripts/run-validation.sh — runs all checks, outputs pass/fail summary
  2. reports/08-validation-report.md — per-query results, round-trip traces, cross-view checks, overall status (populated with live Athena data)
  3. queries/examples/00-mcp-reference.sql — schema, common values, patterns, pitfalls for MCP client LLM

### Claude's Discretion
- Specific SQL for each MCP example query
- Validation script implementation details
- Report formatting and structure
- Which Athena analytical functions to showcase in the pattern cookbook
- Exact common values to enumerate in the reference (use audit report as source)

</decisions>

<specifics>
## Specific Ideas

- "People on horses" remains the primary validation case — must work end-to-end from natural language intent through SQL to correct results
- The MCP reference resource should be dense but LLM-readable — designed to be injected into an LLM context window alongside a user query
- Include advanced Athena SQL patterns (window functions, CTEs, analytical functions) so the MCP client can handle complex queries without multiple round-trips
- The validation report should be the definitive artifact that proves v1.1 Data Quality milestone is complete

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `queries/examples/01-04*.sql`: Phase 7 example queries with expected output — validate these first
- `queries/views/05-class-hierarchy.sql`: Recursive CTE view with depth, root_path, is_leaf, edge_type
- `queries/views/06-hierarchy-relationships.sql`: Ancestor-expanded relationship view with depth columns
- `reports/06-audit-report.md`: Real Athena data including all 27 relationship types, hierarchy structure (single root, 5 levels, 602 MIDs), entity pair counts — source for MCP reference common values
- `scripts/run-audit.sh`: Runner script pattern (128 lines, sources athena.sh, processes SQL files, dry-run support)
- `scripts/lib/athena.sh`: Athena CLI execution helper

### Established Patterns
- SQL files use `__DATABASE__` placeholder (replaced at runtime by runner scripts)
- Runner scripts source `scripts/lib/athena.sh` for query execution
- Reports go in `reports/` directory with phase-number prefix
- Continue on failure, report all errors at end (not fail-fast)
- Example queries include commented expected output from audit data

### Integration Points
- Validation script reads from all existing queries/examples/*.sql files
- Report references Phase 6 audit findings for comparison
- MCP reference resource will be consumed by MCP server team (external consumers)
- This is the last phase of v1.1 — validation report is the milestone capstone

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-end-to-end-validation*
*Context gathered: 2026-03-08*
