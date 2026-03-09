# Requirements: Open Images Athena Database

**Defined:** 2026-03-08
**Core Value:** A fully queryable SQL interface over Open Images annotations — labels, bounding boxes, segmentation masks, and visual relationships — that returns accurate, fast results with human-readable class names via convenience views.

## v1.1 Requirements

Requirements for data quality milestone. Each maps to roadmap phases.

### Audit

- [x] **AUDIT-01**: User can see a complete inventory of relationship types in the validation set (e.g., "on", "under", "holds") with counts
- [x] **AUDIT-02**: User can see the class hierarchy structure — root nodes, max depth, and parent-child chains
- [x] **AUDIT-03**: User can identify which relationships involve which entity classes (e.g., Person-on-Horse)
- [x] **AUDIT-04**: User can verify that relationship and hierarchy data is discoverable via MCP server queries

### Data Fixes

- [x] **FIX-01**: Views/queries are updated so relationships are queryable with human-readable class names on both sides
- [x] **FIX-02**: Views/queries expose hierarchy navigation (ancestors, descendants, depth)
- [x] **FIX-03**: Hierarchy root and structure are easy to query (single query for root, depth, subtree)

## Phase 9 Requirements

Requirements for conversational UI navigation design. Design-only (specification documents, no implementation).

### Navigation Design

- [x] **NAV-01**: Complete MCP tool definitions (inputSchema, outputSchema, _meta.ui) exist for find_images, narrow_results, get_image_details, and explore_category
- [x] **NAV-02**: Widget specifications define layout, data contracts, interaction behaviors, and state management for results grid, image detail, and hierarchy browser
- [x] **NAV-03**: Conversation flow documents cover all entry points (NL, MCP prompt), refinement paths (facet + free-text), detail view, hierarchy browsing, and code mode
- [x] **NAV-04**: Interaction pattern documentation provides a decision framework for tools/call vs ui/message vs ui/update-model-context with fallback and error handling patterns

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
| AUDIT-04 | Phase 8 | Complete |
| FIX-01 | Phase 7 | Complete |
| FIX-02 | Phase 7 | Complete |
| FIX-03 | Phase 7 | Complete |
| NAV-01 | Phase 9 | Planned |
| NAV-02 | Phase 9 | Planned |
| NAV-03 | Phase 9 | Planned |
| NAV-04 | Phase 9 | Planned |

**Coverage:**
- v1.1 requirements: 7 total (7 complete)
- Phase 9 requirements: 4 total (0 complete)
- Unmapped: 0

---
*Requirements defined: 2026-03-08*
*Last updated: 2026-03-09 after Phase 9 planning*
