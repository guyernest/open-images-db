# Phase 7: Query & View Fixes - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Update views and queries so relationships and hierarchies are queryable with human-readable class names, hierarchy navigation, and structure. Create new views that expand class names through the hierarchy (e.g., "Person" includes Man, Woman, Girl, Boy). Does not change existing views — adds new ones alongside them.

</domain>

<decisions>
## Implementation Decisions

### Hierarchy-aware relationship view
- Create a NEW view (hierarchy_relationships) — keep existing labeled_relationships unchanged
- Uses recursive CTE to expand class names to all descendant classes via label_hierarchy
- Expand BOTH subject and object sides (query "Person on Animal" finds "Man on Horse", "Woman on Dog", etc.)
- Include all columns from labeled_relationships PLUS ancestor_name_1, ancestor_name_2, depth_1, depth_2
- Depth columns show hierarchy distance (0 = direct match, 1 = one level up, etc.) for result ranking

### Hierarchy navigation view
- Single view (class_hierarchy) for all navigation — not separate ancestor/descendant views
- Columns: mid, display_name, parent_mid, parent_name, depth, edge_type, root_path, is_leaf
- root_path is a string like "Entity > Person > Man" showing full ancestor chain
- is_leaf boolean identifies classes with no children
- Supports both up-navigation (WHERE mid = X, read depth/root_path) and down-navigation (WHERE parent_mid = X or subtree queries)

### Edge type preservation
- Update flatten-hierarchy.sh to output edge_type column (subcategory or part)
- Rebuild label_hierarchy table with 3 columns: parent_mid, child_mid, edge_type
- Edge type exposed in class_hierarchy view for filtering (e.g., only is-a relationships, not has-part)

### Dropped rows handling
- Accept the 3.3% loss (886 rows) — no changes to existing labeled_relationships INNER JOIN
- All dropped rows are 'is' attribute relationships from 3 orphan MIDs — zero impact on spatial/action queries
- Audit report (reports/06-audit-report.md) already documents this decision — no additional documentation needed

### Documentation & examples
- New queries/examples/ directory alongside existing queries/tables/, queries/views/, queries/audit/
- Four example query files:
  1. "People on horses" — the motivating use case, hierarchy-aware relationship expansion
  2. Hierarchy browsing — navigate class tree, find subtrees, walk root to leaf
  3. Relationship discovery — find relationship types between parent classes
  4. Subtree statistics — count images/relationships per hierarchy branch
- Each file includes SQL query + commented expected output (sample rows and counts from audit data)

### Claude's Discretion
- Specific SQL query optimization and CTE structure
- View naming conventions (as long as they're consistent with existing patterns)
- Order of view creation in runner scripts
- Exact example query SQL and sample output formatting
- Whether to create a new runner script or extend existing create-views.sh

</decisions>

<specifics>
## Specific Ideas

- "People on horses" is the motivating example — this must work end-to-end as the primary validation
- root_path format uses " > " separator (e.g., "Entity > Person > Man")
- The hierarchy_relationships view should feel like a drop-in enhancement over labeled_relationships — same columns plus ancestor/depth info
- Example files should be self-documenting with expected output so Phase 8 can validate against them

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `queries/views/04-labeled-relationships.sql`: Base relationship view with double JOIN to class_descriptions — new hierarchy view builds on this pattern
- `queries/audit/02-hierarchy-structure.sql`: Already has working recursive CTE for hierarchy traversal (root detection, depth, full tree walk) — reuse this pattern
- `queries/audit/03-entity-pair-relationships.sql`: Entity pair grouping with display names — pattern for relationship discovery examples
- `scripts/lib/flatten-hierarchy.sh`: Flattens bbox_labels_600_hierarchy.json via jq — needs edge_type column addition

### Established Patterns
- SQL files use `__DATABASE__` placeholder (replaced at runtime)
- Views numbered sequentially (01-labeled-images through 04-labeled-relationships)
- Runner scripts source `scripts/lib/athena.sh` for Athena CLI execution
- Multi-statement SQL files split on semicolons (create-tables.sh pattern)
- Recursive CTEs in Athena require explicit column aliases on CTE definitions
- Athena recursive CTE depth guard: `WHERE t.depth < 20`

### Integration Points
- New views go in `queries/views/` (numbered 05+)
- label_hierarchy table rebuild requires re-running `queries/tables/07-label-hierarchy.sql` after flatten-hierarchy.sh update
- New examples directory `queries/examples/` follows existing directory structure pattern
- Phase 8 will validate these views work correctly via MCP server query patterns

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-query-view-fixes*
*Context gathered: 2026-03-08*
