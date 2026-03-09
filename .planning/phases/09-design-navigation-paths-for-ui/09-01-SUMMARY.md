---
phase: 09-design-navigation-paths-for-ui
plan: 01
subsystem: design
tags: [mcp-apps, tool-definitions, interaction-model, json-schema, widget-protocol]

# Dependency graph
requires:
  - phase: 08-end-to-end-validation
    provides: "Validated SQL views and MCP reference file (00-mcp-reference.sql)"
provides:
  - "MCP tool definitions (find_images, narrow_results, get_image_details, explore_category) with complete input/output schemas"
  - "start_code_mode prompt definition with SQL generation rules"
  - "Interaction model decision framework (tools/call vs ui/message vs ui/update-model-context)"
  - "Visibility matrix defining which tools are model-visible vs app-only"
affects: [09-02, 09-03, widget-specs, navigation-flows]

# Tech tracking
tech-stack:
  added: [mcp-apps-extension, json-rpc-2.0-postmessage]
  patterns: [three-layer-response, self-contained-widget, tools-call-for-refresh, ui-message-with-fallback]

key-files:
  created:
    - design/tool-definitions/tools.json
    - design/patterns/interaction-model.md

key-decisions:
  - "narrow_results is app-only visibility -- widget calls directly for fast filtering, model should use find_images for new searches"
  - "ui/message text includes tool name hint in brackets (e.g., [get_image_details]) to maximize LLM tool-call probability"
  - "Fallback pattern: 5-second timeout before showing copy-paste text hint for unreliable ui/message actions"
  - "start_code_mode defined as MCP prompt (not tool) that loads 00-mcp-reference.sql as resource context"

patterns-established:
  - "Three-layer response: structuredContent (model-readable), content (conversation text), _meta (widget-exclusive data)"
  - "tools/call for deterministic intra-widget interactions, ui/message for context-switching actions"
  - "Fallback text prompts for every ui/message action to handle LLM non-response"
  - "Error handling: spinner 3s, loading text 3-10s, error with retry after 10s"

requirements-completed: [NAV-01, NAV-04]

# Metrics
duration: 4min
completed: 2026-03-09
---

# Phase 9 Plan 1: Tool Definitions and Interaction Model Summary

**4 MCP tool definitions with three-layer response schemas plus interaction model decision framework covering tools/call, ui/message, and ui/update-model-context**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-09T16:09:26Z
- **Completed:** 2026-03-09T16:13:15Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments

- Complete MCP tool definitions for find_images, narrow_results, get_image_details, and explore_category with full inputSchema, outputSchema (three-layer pattern), and _meta.ui configuration
- start_code_mode MCP prompt with SQL generation rules, pitfall warnings, and 00-mcp-reference.sql resource injection
- Interaction model document with decision tree, fallback patterns, error handling, data flow diagrams, and visibility matrix

## Task Commits

Each task was committed atomically:

1. **Task 1: Create MCP tool definitions with complete schemas** - `a9b888b` (feat)
2. **Task 2: Create interaction model decision framework** - `6d6e400` (feat)

## Files Created/Modified

- `design/tool-definitions/tools.json` - Complete MCP tool and prompt definitions with input/output schemas
- `design/patterns/interaction-model.md` - Decision framework for widget-host interaction mechanisms

## Decisions Made

- **narrow_results app-only visibility:** Widget calls directly for fast deterministic filtering. Model should use find_images for new searches, preventing confusion between refinement and new queries.
- **Tool name hints in ui/message:** Including `[get_image_details]` at the end of ui/message text increases LLM tool-call probability. Documented as a design principle.
- **5-second fallback timeout:** After sending ui/message, widgets wait 5 seconds before showing copy-paste text hint. Balances responsiveness with giving the LLM time to respond.
- **start_code_mode as prompt, not tool:** Code mode is an LLM context injection, not a data-fetching operation. MCP prompts are the correct mechanism.

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- Tool definitions serve as the single source of truth for widget specs (plan 09-02) and navigation flows (plan 09-03)
- Interaction model provides the decision framework referenced by all subsequent design documents
- Both documents can be referenced without circular dependencies

---
*Phase: 09-design-navigation-paths-for-ui*
*Completed: 2026-03-09*
