# Conversation Flow: Result Refinement

How users narrow search results after an initial query. Covers five refinement patterns: facet click (primary), free-text follow-up, multi-facet, filter removal, and pagination.

**Tool:** `find_images` (see `design/tool-definitions/tools.json`)
**Widget:** `results-grid` (same widget as search; re-renders in place)
**Interaction model:** `design/patterns/interaction-model.md`

**Key design principle:** Facet click (Flow 2A) is the PRIMARY refinement mechanism. The widget calls `find_images` directly via `tools/call`, constructing args from its local selection state. Reliable, fast, no LLM involvement. Free-text follow-up (Flow 2B) goes through the LLM and produces a new widget, which is fine but slower and less predictable. The server is stateless — every call is a self-contained `find_images` invocation.

---

## Flow 2A: Facet Click Refinement

Within widget, no new conversation turn. This is the most common refinement action.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Poodle" facet pill in the results-grid widget | Click event on category facet | Step 2 |
| 2 | **Widget (results-grid)** | Toggles "Poodle" in local `active_subjects[]`. Constructs full `find_images` args from current selection state. Calls `tools/call find_images` via App SDK bridge. | `app.callServerTool({ name: "find_images", arguments: { subject: "Poodle", page: 1, limit: 20 } })` | Step 3 |
| 3 | **MCP Server** | Receives self-contained query. Queries `labeled_images` filtered by Poodle, computes facets from the result set. Returns three-layer response. | SQL: `WHERE ch.display_name = 'Poodle'`. Views: `labeled_images`, `class_hierarchy`, `hierarchy_relationships` | Step 4 |
| 4 | **Widget (results-grid)** | Re-renders in place (same iframe, no new conversation turn). Changes: "Poodle" pill becomes active (filled/highlighted). Count bar updates to "89 poodle images". Grid shows only poodle images. Other facets update to reflect poodle-specific relationships (e.g., "wears", "on", "at" become available). | Updated `_meta.images`, updated `structuredContent.facets` | User may click another facet (Flow 2C), remove filter (Flow 2D), paginate (Flow 2E), or click thumbnail (Flow 3A) |

**No conversation turn created.** The LLM is not involved. The widget holds selection state locally, constructs complete `find_images` args, and calls the server directly via `tools/call`. The server is stateless — no session, no previous_query. This is fast and deterministic.

**Error handling:** If `find_images` returns empty results, the widget shows: "No poodle images found matching current selection. [Clear Filters] [New Search]". See `design/patterns/interaction-model.md` Section 4 for error states.

---

## Flow 2B: Free-Text Follow-Up

New conversation turn. The user types a refinement request in the conversation.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types "I see poodles and german shepherds, show me more poodles" in conversation | Free-text input referencing visible results | Step 2 |
| 2 | **LLM** | Reads conversation context (previous `find_images` results visible in `structuredContent`). Recognizes refinement intent. Calls `find_images` with structured args. | `{ subject: "Poodle" }` -- the LLM starts a fresh search for the specific breed | Step 3 |
| 3 | **MCP Server** | Queries for Poodle images. Returns three-layer response. | Same query pattern as `find_images` for a direct class | Step 4 |
| 4 | **Widget (results-grid)** | A NEW results-grid widget appears below in the conversation. The previous results-grid widget freezes in place (becomes historical context). The new widget shows poodle images with poodle-specific facets. | New widget instance, independent of the previous one | Step 5 |
| 5 | **LLM (conversation text)** | "Here are 89 poodle images. I can also show you poodles in specific situations -- for example, poodles with people, or outdoor scenes. Or click a facet to filter further." | Contextual suggestions based on available relationships | User interacts with the NEW widget |

**Key difference from Flow 2A:** This creates a new conversation turn and a new widget. The old widget is frozen. The LLM calls `find_images` from conversation context. The result is functionally similar but takes longer (LLM reasoning + network round-trip for new turn).

**When this is preferable:** When the user wants to express complex refinement that facets cannot capture, like "show me poodles playing outdoors" or "I want the ones where they're wearing something."

---

## Flow 2C: Multi-Facet Refinement

Sequential facet clicks within the same widget. Each click adds a filter.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Poodle" category facet | First selection | Step 2 |
| 2 | **Widget** | Toggles "Poodle" into `active_subjects[]`. Calls `find_images` with `{ subject: "Poodle" }`. Re-renders. "Poodle" pill becomes active. | `active_subjects: ["Poodle"]` | Step 3 |
| 3 | **User** | Clicks "wears" relationship facet | Second selection added | Step 4 |
| 4 | **Widget** | Toggles "wears" into `active_relationships[]`. Calls `find_images` with both selections. | `app.callServerTool({ name: "find_images", arguments: { subject: "Poodle", relationship: "wears", page: 1 } })` | Step 5 |
| 5 | **Widget** | Re-renders. Both "Poodle" and "wears" pills active. Grid shows poodles in "wears" relationships only. Count updates. Remaining facets update to show what further refinements are available. | `active_subjects: ["Poodle"], active_relationships: ["wears"]` | User may add more facets, remove selections (Flow 2D), or click thumbnail (Flow 3A) |

**Filter combination is AND across dimensions, OR within.** Subject + relationship = AND. Multiple subjects = OR. The widget holds all selection state locally and constructs complete `find_images` args on each call. The server receives a self-contained request every time.

---

## Flow 2D: Removing Filters

User deactivates an active facet to broaden results.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks the active (filled) "Poodle" pill to toggle it off | Deactivation click | Step 2 |
| 2 | **Widget** | Removes "Poodle" from `active_subjects[]`. Constructs `find_images` args from remaining selections. If "wears" still active: `{ relationship: "wears" }`. If no selections remain: calls with `{ subject: original_subject }`. | `app.callServerTool({ name: "find_images", arguments: { relationship: "wears", page: 1 } })` | Step 3 |
| 3 | **MCP Server** | Receives self-contained query. Returns updated results. | Fewer WHERE clauses applied | Step 4 |
| 4 | **Widget** | Re-renders with broader results. "Poodle" pill returns to inactive (outline) state. Count increases. Grid shows wider variety of dog images that have "wears" relationships. | Updated `_meta.images` | User continues refining |

**Edge case:** If all selections are cleared, the widget calls `find_images` with `original_subject` — returning to the initial unfiltered results.

---

## Flow 2E: Pagination

User loads more results within the same filter state.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Load more" button at the bottom of the grid | Pagination request | Step 2 |
| 2 | **Widget** | Calls `find_images` with current selections + `page: 2`. | `app.callServerTool({ name: "find_images", arguments: { subject: "Poodle", page: 2, limit: 20 } })` | Step 3 |
| 3 | **MCP Server** | Receives self-contained query for page 2 (offset 20, limit 20). | `OFFSET 20 LIMIT 20` added to query | Step 4 |
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
- **Tool definition:** `find_images` in `design/tool-definitions/tools.json` (dual visibility — model and app)
- **Interaction mechanism:** All facet interactions use `tools/call find_images` per `design/patterns/interaction-model.md` Section 2 decision tree

---

*Flow: 02-refinement-flow*
*Phase: 09-design-navigation-paths-for-ui*
