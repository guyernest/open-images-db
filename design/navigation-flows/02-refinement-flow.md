# Conversation Flow: Result Refinement

How users narrow search results after an initial query. Covers five refinement patterns: facet click (primary), free-text follow-up, multi-facet, filter removal, and pagination.

**Tool:** `narrow_results` (app-only visibility -- see `design/tool-definitions/tools.json`)
**Widget:** `results-grid` (same widget as search; re-renders in place)
**Interaction model:** `design/patterns/interaction-model.md`

**Key design principle:** Facet click (Flow 2A) is the PRIMARY refinement mechanism. It uses `tools/call` -- reliable, fast, no LLM involvement. Free-text follow-up (Flow 2B) goes through the LLM and produces a new widget, which is fine but slower and less predictable.

---

## Flow 2A: Facet Click Refinement

Within widget, no new conversation turn. This is the most common refinement action.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Poodle" facet pill in the results-grid widget | Click event on category facet | Step 2 |
| 2 | **Widget (results-grid)** | Calls `tools/call narrow_results` via App SDK bridge | `app.callServerTool({ name: "narrow_results", arguments: { previous_query: "dogs", filter: "category:Poodle", page: 1, limit: 20 } })` | Step 3 |
| 3 | **MCP Server** | Adds WHERE clause for Poodle class to the existing query. Queries `labeled_images` filtered by Poodle, recomputes facets from the narrowed result set. Returns three-layer response. | SQL: `WHERE ch.display_name = 'Poodle'` added to base query. Views: `labeled_images`, `class_hierarchy`, `hierarchy_relationships` | Step 4 |
| 4 | **Widget (results-grid)** | Re-renders in place (same iframe, no new conversation turn). Changes: "Poodle" pill becomes active (filled/highlighted). Count bar updates to "89 poodle images". Grid shows only poodle images. Other facets update to reflect poodle-specific relationships (e.g., "wears", "on", "at" become available). | `structuredContent.applied_filters: ["category:Poodle"]`, updated `_meta.images`, updated `structuredContent.facets` | User may click another facet (Flow 2C), remove filter (Flow 2D), paginate (Flow 2E), or click thumbnail (Flow 3A) |

**No conversation turn created.** The LLM is not involved. The widget handles the entire interaction via `tools/call`. This is fast and deterministic.

**Error handling:** If `narrow_results` returns empty results, the widget shows: "No poodle images found matching current filters. [Remove Filters] [New Search]". See `design/patterns/interaction-model.md` Section 4 for error states.

---

## Flow 2B: Free-Text Follow-Up

New conversation turn. The user types a refinement request in the conversation.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types "I see poodles and german shepherds, show me more poodles" in conversation | Free-text input referencing visible results | Step 2 |
| 2 | **LLM** | Reads conversation context (previous `find_images` results visible in `structuredContent`). Recognizes refinement intent. Calls `find_images` (not `narrow_results` -- model cannot see `narrow_results`). | `{ query: "Poodle" }` -- the LLM starts a fresh search for the specific breed | Step 3 |
| 3 | **MCP Server** | Queries for Poodle images. Returns three-layer response. | Same query pattern as `find_images` for a direct class | Step 4 |
| 4 | **Widget (results-grid)** | A NEW results-grid widget appears below in the conversation. The previous results-grid widget freezes in place (becomes historical context). The new widget shows poodle images with poodle-specific facets. | New widget instance, independent of the previous one | Step 5 |
| 5 | **LLM (conversation text)** | "Here are 89 poodle images. I can also show you poodles in specific situations -- for example, poodles with people, or outdoor scenes. Or click a facet to filter further." | Contextual suggestions based on available relationships | User interacts with the NEW widget |

**Key difference from Flow 2A:** This creates a new conversation turn and a new widget. The old widget is frozen. The LLM uses `find_images` (not `narrow_results`) because `narrow_results` has app-only visibility. The result is functionally similar but takes longer (LLM reasoning + network round-trip for new turn).

**When this is preferable:** When the user wants to express complex refinement that facets cannot capture, like "show me poodles playing outdoors" or "I want the ones where they're wearing something."

---

## Flow 2C: Multi-Facet Refinement

Sequential facet clicks within the same widget. Each click adds a filter.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Poodle" category facet | First filter applied | Step 2 |
| 2 | **Widget** | Calls `narrow_results` with `filter: "category:Poodle"`. Re-renders. "Poodle" pill becomes active. | `applied_filters: ["category:Poodle"]` | Step 3 |
| 3 | **User** | Clicks "wears" relationship facet | Second filter added | Step 4 |
| 4 | **Widget** | Calls `narrow_results` with `filter: "category:Poodle,relationship:wears"`. Both filters passed together. | `app.callServerTool({ name: "narrow_results", arguments: { previous_query: "dogs", filter: "category:Poodle,relationship:wears" } })` | Step 5 |
| 5 | **Widget** | Re-renders. Both "Poodle" and "wears" pills active. Grid shows poodles in "wears" relationships only. Count updates. Remaining facets update to show what further refinements are available. | `applied_filters: ["category:Poodle", "relationship:wears"]` | User may add more facets, remove filters (Flow 2D), or click thumbnail (Flow 3A) |

**Filter combination is AND logic.** Each additional facet narrows the result set. The widget tracks all active filters and passes them as a comma-separated list to `narrow_results`.

---

## Flow 2D: Removing Filters

User deactivates an active facet to broaden results.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks the active (filled) "Poodle" pill to toggle it off | Deactivation click on active filter | Step 2 |
| 2 | **Widget** | Calls `narrow_results` with the remaining filters only. If "wears" was also active: `filter: "relationship:wears"`. If no other filters: calls with empty filter or re-queries the original search. | `app.callServerTool({ name: "narrow_results", arguments: { previous_query: "dogs", filter: "relationship:wears" } })` | Step 3 |
| 3 | **MCP Server** | Re-queries with broadened filter set. Returns updated results. | Fewer WHERE clauses applied | Step 4 |
| 4 | **Widget** | Re-renders with broader results. "Poodle" pill returns to inactive (outline) state. Count increases. Grid shows wider variety of dog images that have "wears" relationships. | Updated `applied_filters`, updated `_meta.images` | User continues refining |

**Edge case:** If all filters are removed, the widget returns to the original search results (equivalent to the initial `find_images` response).

---

## Flow 2E: Pagination

User loads more results within the same filter state.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Load more" button at the bottom of the grid | Pagination request | Step 2 |
| 2 | **Widget** | Calls `narrow_results` with `page: 2` and all current filters preserved. | `app.callServerTool({ name: "narrow_results", arguments: { previous_query: "dogs", filter: "category:Poodle", page: 2, limit: 20 } })` | Step 3 |
| 3 | **MCP Server** | Queries page 2 of the filtered result set (offset 20, limit 20). | `OFFSET 20 LIMIT 20` added to query | Step 4 |
| 4 | **Widget** | Appends new images below existing ones in the grid. Does NOT replace the current images. "Load more" button moves to the new bottom. If no more results, button is replaced with "All {count} images shown." | Images array extended, not replaced | User scrolls and continues browsing |

**Context sync:** After pagination, the widget sends `ui/update-model-context` with the currently visible image IDs so the LLM knows what the user is looking at if they type a follow-up.

---

## Example Query File Mapping

| Example Query File | Maps to Flow | How |
|---|---|---|
| `03-relationship-discovery.sql` | Flow 2A | Clicking a relationship facet (e.g., "ride") filters by relationship type |
| `06-category-exploration.sql` | Flow 2A | Clicking a category facet (e.g., "Poodle") filters by class name |

---

## Cross-References

- **Entry to refinement:** All search flows in `01-search-flow.md` lead here
- **From refinement to detail:** Clicking a thumbnail in the refined grid enters `03-detail-flow.md`
- **From refinement to hierarchy:** If user wants to explore categories more broadly, they type a question that leads to `04-hierarchy-flow.md`
- **Tool definition:** `narrow_results` in `design/tool-definitions/tools.json` (app-only visibility)
- **Interaction mechanism:** All facet interactions use `tools/call` per `design/patterns/interaction-model.md` Section 2 decision tree

---

*Flow: 02-refinement-flow*
*Phase: 09-design-navigation-paths-for-ui*
