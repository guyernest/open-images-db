# Roadmap: Open Images Athena Database

## Milestones

- v1.0 MVP - Phases 1-5 (shipped 2026-03-06)
- v1.1 Data Quality - Phases 6-8 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>v1.0 MVP (Phases 1-5) - SHIPPED 2026-03-06</summary>

Phases 1-5 completed. See MILESTONES.md for summary.

</details>

### v1.1 Data Quality (In Progress)

**Milestone Goal:** Audit and fix relationship and hierarchy data so entities and their connections are properly queryable and visible in the MCP server.

- [ ] **Phase 6: Relationship & Hierarchy Audit** - Discover what relationship and hierarchy data exists, its structure, and its gaps
- [x] **Phase 7: Query & View Fixes** - Update views and queries so relationships and hierarchies are queryable with human-readable names (completed 2026-03-08)
- [ ] **Phase 8: End-to-End Validation** - Verify the fixed data is discoverable and queryable through MCP server patterns

## Phase Details

### Phase 6: Relationship & Hierarchy Audit
**Goal**: User understands exactly what relationship and hierarchy data exists in the validation set, including coverage, structure, and gaps
**Depends on**: Phase 5 (v1.0 complete)
**Requirements**: AUDIT-01, AUDIT-02, AUDIT-03
**Success Criteria** (what must be TRUE):
  1. User can run a query that returns every distinct relationship type (e.g., "on", "under", "holds") with the count of instances in the validation set
  2. User can run a query that shows the class hierarchy from root to leaves, with depth and parent-child chains
  3. User can run a query that shows which entity class pairs participate in each relationship type (e.g., Person-on-Horse: 47 instances)
  4. An audit report documents coverage numbers, structural findings, and any data gaps or anomalies discovered
**Plans:** 2 plans

Plans:
- [ ] 06-01-PLAN.md — Create audit SQL queries and runner script
- [ ] 06-02-PLAN.md — Execute audit and produce findings report

### Phase 7: Query & View Fixes
**Goal**: Relationships and hierarchies are queryable through views with human-readable class names, navigation, and structure
**Depends on**: Phase 6
**Requirements**: FIX-01, FIX-02, FIX-03
**Success Criteria** (what must be TRUE):
  1. User can query relationships and see human-readable class names on both the subject and object sides (e.g., "Person is_on Horse" not "/m/01g317 is_on /m/03k3r")
  2. User can query any class and navigate up to its ancestors or down to its descendants in the hierarchy
  3. User can find the hierarchy root, query any subtree, and see depth for every node in a single query
  4. All new or modified views/queries are documented with example usage
**Plans:** 2/2 plans complete

Plans:
- [ ] 07-01-PLAN.md — Update data pipeline (edge_type) and create hierarchy-aware views
- [ ] 07-02-PLAN.md — Create example query files documenting new views

### Phase 8: End-to-End Validation
**Goal**: The fixed relationship and hierarchy data is verified as discoverable and useful through queries that an MCP server would execute
**Depends on**: Phase 7
**Requirements**: AUDIT-04
**Success Criteria** (what must be TRUE):
  1. A set of example queries demonstrates real-world MCP server usage patterns (e.g., "find images of people on horses", "what categories exist under Animal")
  2. Every example query returns correct, non-empty results with human-readable output
  3. User can verify that relationship and hierarchy data round-trips correctly from raw tables through views to query results
**Plans:** 2 plans

Plans:
- [ ] 08-01-PLAN.md — Create MCP reference resource and new example queries
- [ ] 08-02-PLAN.md — Create validation script, run validation, produce report

## Progress

**Execution Order:**
Phases execute in numeric order: 6 -> 7 -> 8

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 6. Relationship & Hierarchy Audit | v1.1 | 0/2 | Planning complete | - |
| 7. Query & View Fixes | 2/2 | Complete   | 2026-03-08 | - |
| 8. End-to-End Validation | v1.1 | 0/2 | Planning complete | - |
