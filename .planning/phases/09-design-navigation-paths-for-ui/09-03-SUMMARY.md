---
phase: 09-design-navigation-paths-for-ui
plan: 03
subsystem: design
tags: [mcp-apps, conversation-flows, navigation-flows, user-journeys, search-ux]

# Dependency graph
requires:
  - phase: 09-design-navigation-paths-for-ui
    plan: 01
    provides: "MCP tool definitions (find_images, narrow_results, get_image_details, explore_category) and interaction model decision framework"
provides:
  - "Four end-to-end conversation flow documents covering search, refinement, detail, and hierarchy navigation"
  - "Complete mapping of all 8 example query files to conversation flows"
  - "Code mode entry and SQL generation flow with code-to-tool transition"
  - "ui/message fallback pattern for all navigate-from-image actions"
affects: [widget-implementation, mcp-server-implementation]

# Tech tracking
tech-stack:
  added: []
  patterns: [actor-action-data-next-flow-tables, dual-entry-point-search, facet-as-primary-refinement, tree-to-grid-intra-widget-transition, ui-message-with-5s-fallback]

key-files:
  created:
    - design/navigation-flows/01-search-flow.md
    - design/navigation-flows/02-refinement-flow.md
    - design/navigation-flows/03-detail-flow.md
    - design/navigation-flows/04-hierarchy-flow.md

key-decisions:
  - "Facet click (tools/call) is the PRIMARY refinement mechanism -- fast, deterministic, no LLM involvement"
  - "Free-text follow-up creates a new widget (via find_images) rather than updating the existing one"
  - "Tree-to-grid transition happens within the same widget iframe to avoid new conversation turns"
  - "Code mode has no explicit exit -- LLM seamlessly switches to tool mode when user intent shifts"

patterns-established:
  - "Actor/Action/Data/Next table format for documenting conversation flow steps"
  - "Dual entry strategy for broad queries: show results (visual-first default) or show hierarchy"
  - "Navigate-from-image uses parent class names (Person not Man) for broader result sets"
  - "Every ui/message action has a 5-second fallback with click-to-copy text"

requirements-completed: [NAV-03]

# Metrics
duration: 5min
completed: 2026-03-09
---

# Phase 9 Plan 3: Conversation Flows Summary

**Four end-to-end conversation flow documents covering search entry (MCP prompt + NL + broad query), result refinement (facet clicks + free-text), image detail with navigate-from-image actions, and hierarchy browsing with code mode**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-09T16:16:06Z
- **Completed:** 2026-03-09T16:21:06Z
- **Tasks:** 2
- **Files created:** 4

## Accomplishments

- Search flow covering three entry patterns: MCP prompt (deterministic), natural language (LLM-interpreted), and broad/ambiguous queries (with LLM strategy selection between results-first and hierarchy-first)
- Refinement flow documenting five interaction patterns: facet click (primary, via tools/call), free-text follow-up (new turn), multi-facet AND combination, filter removal, and pagination
- Detail flow with six sub-flows: enter-from-grid, navigate-from-image (more with label, similar scenes, explore category), annotation interaction, and universal ui/message fallback pattern
- Hierarchy flow tracing all 5 depth levels (Entity -> Animal -> Carnivore -> Dog -> Poodle), tree-to-grid intra-widget transition, breadcrumb navigation, code mode entry/usage, and code-to-tool mode switching
- Complete cross-reference table mapping all 8 example query files to at least one conversation flow

## Task Commits

Each task was committed atomically:

1. **Task 1: Document search and refinement conversation flows** - `0b6186c` (feat)
2. **Task 2: Document detail and hierarchy conversation flows** - `c3e0de5` (feat)

## Files Created/Modified

- `design/navigation-flows/01-search-flow.md` - Initial search flow: MCP prompt, natural language, broad/ambiguous entry points with branching
- `design/navigation-flows/02-refinement-flow.md` - Result refinement: facet click (tools/call), free-text (new turn), multi-facet, filter removal, pagination
- `design/navigation-flows/03-detail-flow.md` - Image detail view: enter-from-grid, navigate-from-image actions, annotation interaction, ui/message fallback
- `design/navigation-flows/04-hierarchy-flow.md` - Hierarchy browsing: 5-level drill-down, tree-to-grid transition, breadcrumb nav, code mode entry/usage/transition

## Decisions Made

- **Facet click as primary refinement:** tools/call is fast and deterministic. Free-text follow-up creates a new widget and goes through LLM reasoning -- fine but slower and less predictable. Design emphasizes facets as the main path.
- **Free-text uses find_images, not narrow_results:** The model cannot see narrow_results (app-only visibility). When user types a refinement in conversation, the LLM calls find_images for a fresh search, producing a new widget below the old one.
- **Tree-to-grid within same iframe:** Clicking "View all images" in the hierarchy browser transitions to grid mode within the same widget. No new conversation turn needed. "Back to tree" restores previous state from widget memory.
- **No explicit code mode exit:** The LLM seamlessly switches to tool mode when the user's intent changes from SQL queries to visual browsing. User can re-enter code mode with `/start_code_mode`.
- **Parent class names for navigate-from-image:** When user clicks a relationship like "Man ride Horse" in detail view, the ui/message uses "Person" (parent class) instead of "Man" for broader results via ancestor expansion.

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- All four conversation flow documents complete the design phase
- Flows cross-reference tool definitions (09-01) and can reference widget specs (09-02) once complete
- A developer can trace any user journey from first query to final image selection using these documents
- Implementation phase can use these flows as acceptance criteria for MCP server and widget behavior

## Self-Check: PASSED

All 4 flow files exist. Both task commits verified (0b6186c, c3e0de5).

---
*Phase: 09-design-navigation-paths-for-ui*
*Completed: 2026-03-09*
