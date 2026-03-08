# Requirements: Open Images Athena Database

**Defined:** 2026-03-08
**Core Value:** A fully queryable SQL interface over Open Images annotations — labels, bounding boxes, segmentation masks, and visual relationships — that returns accurate, fast results with human-readable class names via convenience views.

## v1.1 Requirements

Requirements for data quality milestone. Each maps to roadmap phases.

### Audit

- [x] **AUDIT-01**: User can see a complete inventory of relationship types in the validation set (e.g., "on", "under", "holds") with counts
- [x] **AUDIT-02**: User can see the class hierarchy structure — root nodes, max depth, and parent-child chains
- [x] **AUDIT-03**: User can identify which relationships involve which entity classes (e.g., Person-on-Horse)
- [ ] **AUDIT-04**: User can verify that relationship and hierarchy data is discoverable via MCP server queries

### Data Fixes

- [x] **FIX-01**: Views/queries are updated so relationships are queryable with human-readable class names on both sides
- [x] **FIX-02**: Views/queries expose hierarchy navigation (ancestors, descendants, depth)
- [x] **FIX-03**: Hierarchy root and structure are easy to query (single query for root, depth, subtree)

## Future Requirements

None identified yet.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Full dataset (train/test) | Validation set only for now |
| MCP server changes | Built by another team; we fix the SQL layer |
| New data ingestion | Working with already-loaded data |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUDIT-01 | Phase 6 | Complete |
| AUDIT-02 | Phase 6 | Complete |
| AUDIT-03 | Phase 6 | Complete |
| AUDIT-04 | Phase 8 | Pending |
| FIX-01 | Phase 7 | Complete |
| FIX-02 | Phase 7 | Complete |
| FIX-03 | Phase 7 | Complete |

**Coverage:**
- v1.1 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0

---
*Requirements defined: 2026-03-08*
*Last updated: 2026-03-08 after roadmap creation*
