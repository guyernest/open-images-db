---
phase: 09-design-navigation-paths-for-ui
plan: 02
subsystem: design
tags: [mcp-apps, widget-specs, results-grid, image-detail, hierarchy-browser, annotation-overlay, facet-filtering]

# Dependency graph
requires:
  - phase: 09-design-navigation-paths-for-ui
    plan: 01
    provides: "MCP tool definitions (tools.json) and interaction model decision framework"
provides:
  - "Results grid widget spec with inline facets, pagination, thumbnail grid, and state management"
  - "Image detail widget spec with bounding box overlays, relationship lines, layer toggles, and navigate-from-image actions"
  - "Hierarchy browser widget spec with collapsible tree, breadcrumb navigation, sample thumbnails, and tree-to-grid transition"
affects: [09-03, navigation-flows, widget-implementation]

# Tech tracking
tech-stack:
  added: []
  patterns: [self-contained-widget, intra-widget-drill-down, deterministic-color-palette, normalized-coordinate-overlays, tree-to-grid-transition]

key-files:
  created:
    - design/widget-specs/results-grid.md
    - design/widget-specs/image-detail.md
    - design/widget-specs/hierarchy-browser.md

key-decisions:
  - "Facet pills use toggle semantics (click active pill to remove filter) rather than separate add/remove UI"
  - "Bounding box colors assigned via deterministic hash of display_name ensuring consistent colors per class"
  - "Hierarchy browser transitions between tree-mode and grid-mode within same iframe rather than opening new conversation turn"
  - "'is' relationships hidden by default in image detail with explicit toggle, matching the 81.8% dominance filtering"

patterns-established:
  - "Annotation overlay rendering: normalized coordinates, deterministic color palette, z-index by confidence+area"
  - "Request cancellation pattern: new tools/call cancels in-flight previous request to prevent race conditions"
  - "Tree-to-grid mode transition: widget switches views internally, tree data preserved in memory for instant back navigation"
  - "Sample thumbnail mapping: flat array with class_name field grouped by widget at render time"

requirements-completed: [NAV-02]

# Metrics
duration: 5min
completed: 2026-03-09
---

# Phase 9 Plan 2: Widget Specifications Summary

**Three self-contained widget specs (results-grid, image-detail, hierarchy-browser) with annotation overlay rendering rules, inline facets, tree-to-grid transitions, and full interaction/accessibility coverage**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-09T16:15:59Z
- **Completed:** 2026-03-09T16:20:54Z
- **Tasks:** 2
- **Files created:** 3

## Accomplishments

- Results grid widget spec with inline facet pills, 3-column responsive thumbnail grid, load-more pagination, state management for filter/pagination/request cancellation
- Image detail widget spec with bounding box overlays (coordinate normalization, deterministic colors, z-index ordering), relationship lines between subject/object boxes, layer toggles, and navigate-from-image action buttons
- Hierarchy browser widget spec with collapsible tree (breadcrumb trail, edge type distinction, sample thumbnails per node), tree-to-grid mode transition, and depth-limited lazy loading

## Task Commits

Each task was committed atomically:

1. **Task 1: Specify results grid widget** - `81f9157` (feat)
2. **Task 2: Specify image detail and hierarchy browser widgets** - `711a9d2` (feat)

## Files Created/Modified

- `design/widget-specs/results-grid.md` - Image grid widget with inline facets, pagination, state management, responsive breakpoints
- `design/widget-specs/image-detail.md` - Single image view with annotation overlays, layer toggles, navigate-from-image actions
- `design/widget-specs/hierarchy-browser.md` - Category tree widget with breadcrumb navigation, tree-to-grid transition, sample thumbnails

## Decisions Made

- **Facet toggle semantics:** Clicking an active facet pill removes the filter (toggle behavior), rather than requiring a separate "X" button. Applied filter chips from `narrow_results` response DO have remove-X buttons for clarity when multiple filters are stacked.
- **Deterministic color palette:** Bounding box colors assigned by hashing `display_name` into a 12-color colorblind-friendly palette. Ensures same class always gets same color without maintaining global state.
- **Tree-to-grid within iframe:** Hierarchy browser transitions to grid-mode internally rather than sending `ui/message` to create a new results-grid widget. This preserves tree data in memory for instant back-navigation and avoids unreliable `ui/message` for a primary navigation action.
- **'is' relationship default hidden:** Both image detail (relationships section) and hierarchy browser (relationship summary) exclude 'is' relationships by default with explicit toggle, consistent with the 81.8% dominance noted in the research.

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- All three widget specs define complete layout, data contract, interaction behaviors, and state management
- Widget specs reference correct tools from tools.json and interaction mechanisms from interaction-model.md
- Navigation flow design (plan 09-03) can now trace complete user journeys through these widgets

---
*Phase: 09-design-navigation-paths-for-ui*
*Completed: 2026-03-09*
