# Conversation Flow: Hierarchy Browsing and Code Mode

How users explore the class hierarchy tree and use code mode for advanced queries. Covers: direct hierarchy entry, drilling down through 5 depth levels, tree-to-grid transition, breadcrumb navigation, code mode entry, code mode usage, and code-to-tool mode transition.

**Tool:** `explore_category` (see `design/tool-definitions/tools.json`)
**Prompt:** `start_code_mode` (see `design/tool-definitions/tools.json`)
**Widget:** `hierarchy-browser` (see `design/widget-specs/hierarchy-browser.md`)
**Interaction model:** `design/patterns/interaction-model.md`

---

## Flow 4A: Direct Hierarchy Entry

User asks about categories or uses the MCP prompt.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types "What kinds of animals are in the dataset?" or `/explore_category Animal` | Category exploration request | Step 2 |
| 2 | **LLM** | Calls `explore_category` with `class_name: "Animal"`, `depth: 2` | `{ class_name: "Animal", depth: 2, include_samples: true }` | Step 3 |
| 3 | **MCP Server** | Queries `class_hierarchy` for Animal subtree (maps to `02-hierarchy-browsing.sql` pattern). Gets children at depth+1 and depth+2. Queries `labeled_images` for 3-5 sample thumbnails per subcategory. Queries relationship summary for the Animal subtree (maps to `04-subtree-statistics.sql` pattern). | SQL views: `class_hierarchy` (recursive CTE with root_path), `labeled_images` (samples), `hierarchy_relationships` (relationship counts). Returns: hierarchy tree + samples + relationship summary. | Step 4 |
| 4 | **Widget (hierarchy-browser)** | Renders showing: breadcrumb trail "Entity > Animal", node header "Animal -- 2,847 images, 15 relationship types", children list with expand arrows: Bird (sample thumbnails), Carnivore (sample thumbnails), Mammal, Invertebrate, Reptile, Fish. Each child shows image count. "View all animal images" button at bottom. | `_meta.hierarchy_tree` (recursive structure), `_meta.sample_images` (per subcategory), `_meta.relationship_summary`, `structuredContent.root_path` | Step 5 |
| 5 | **LLM (conversation text)** | "The Animal category has 6 main branches: Bird, Carnivore, Mammal, Invertebrate, Reptile, and Fish. Carnivore is the largest with 1,200+ images including dogs, cats, bears, and more. Click a category to explore deeper, or click 'View all images' to see them all." | `content[0].text` from tool response | User clicks a category (Flow 4B), clicks "View all" (Flow 4C), or clicks breadcrumb (Flow 4D) |

**Hierarchy data:** The `class_hierarchy` view provides `root_path` (e.g., "Entity > Animal"), `depth` (0-4), `display_name`, `edge_type` ("subcategory" or "part"), and `is_leaf`. The hierarchy has 602 classes across 5 depth levels (0=Entity root, 4=deepest leaves).

---

## Flow 4B: Drilling Down the Hierarchy

User navigates deeper into the tree. All drill-down uses `tools/call` (no new conversation turn).

### Level 1 -> Level 2: Animal -> Carnivore

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Carnivore" expand arrow in the tree | Click on tree node | Step 2 |
| 2 | **Widget (hierarchy-browser)** | Calls `tools/call explore_category` | `app.callServerTool({ name: "explore_category", arguments: { class_name: "Carnivore", depth: 2 } })` | Step 3 |
| 3 | **MCP Server** | Returns Carnivore subtree: Dog, Cat, Bear, Fox, Lion, Tiger, etc. with sample thumbnails and image counts. | Carnivore children from `class_hierarchy` | Step 4 |
| 4 | **Widget** | Re-renders in place. Breadcrumb updates to "Entity > Animal > Carnivore". Tree expands Carnivore node showing children with sample thumbnails. Dog, Cat, Bear each show expand arrows (have children). Lion, Tiger show as leaf indicators. | Updated `_meta.hierarchy_tree` for Carnivore subtree | No conversation turn. User clicks deeper. |

### Level 2 -> Level 3: Carnivore -> Dog

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Dog" in the tree | Deeper drill-down | Step 2 |
| 2 | **Widget** | Calls `tools/call explore_category` for Dog | `{ class_name: "Dog", depth: 2 }` | Step 3 |
| 3 | **MCP Server** | Returns Dog subtree: Poodle, German shepherd, Labrador, Golden retriever, etc. These are leaf nodes (depth 4, no children). | Deepest hierarchy level for Dog | Step 4 |
| 4 | **Widget** | Breadcrumb: "Entity > Animal > Carnivore > Dog". Shows breed list without expand arrows (leaf nodes). Each breed shows sample thumbnails and image count. | Leaf nodes have `is_leaf: true` | User can click "View all images" or a breadcrumb to go up |

### Complete 5-Level Trace: Entity -> Animal -> Carnivore -> Dog -> Poodle

| Depth | Node | Path | Children | Leaf? |
|-------|------|------|----------|-------|
| 0 | Entity | Entity | Animal, Food, Clothing, ... | No |
| 1 | Animal | Entity > Animal | Bird, Carnivore, Mammal, ... | No |
| 2 | Carnivore | Entity > Animal > Carnivore | Dog, Cat, Bear, ... | No |
| 3 | Dog | Entity > Animal > Carnivore > Dog | Poodle, German shepherd, ... | No |
| 4 | Poodle | Entity > Animal > Carnivore > Dog > Poodle | (none) | Yes |

At depth 4 (Poodle), the tree shows the leaf node with its image count and sample thumbnails. No expand arrow. The "View all images" button is the primary action.

**Context sync:** After each drill-down, the widget sends `ui/update-model-context` with the current breadcrumb path so the LLM knows where the user is in the hierarchy if they type a follow-up question.

---

## Flow 4C: Transitioning from Hierarchy to Image Grid

User wants to see actual images for a category.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "View all images" button on the Dog category node | Grid transition request | Step 2 |
| 2 | **Widget (hierarchy-browser)** | Calls `tools/call find_images` with subject | `app.callServerTool({ name: "find_images", arguments: { subject: "Dog" } })` | Step 3 |
| 3 | **MCP Server** | Queries for Dog images with breed facets. Returns standard `find_images` three-layer response. | Same response as a direct `find_images` call for "Dog" | Step 4 |
| 4 | **Widget (hierarchy-browser)** | Internal mode transition within the same iframe. Tree view fades out, grid view fades in. Grid shows dog images with subcategory facets (Poodle, German shepherd, Labrador). A "Back to tree" button appears in the top-left. | Widget manages two internal modes: tree and grid. Same iframe, no new conversation turn. | Step 5 |
| 5 | **User** | Browses the grid. Can click facets (same as Flow 2A in `02-refinement-flow.md`), paginate, or click thumbnails. | Standard grid interactions via `tools/call find_images` | User clicks "Back to tree" (Step 6) or continues in grid |
| 6 | **User** | Clicks "Back to tree" button | Return to tree mode | Step 7 |
| 7 | **Widget** | Returns to tree mode. Previous tree state is intact (expanded nodes, breadcrumb position). No server call needed -- tree state was preserved in widget memory. | Client-side state restoration | User continues browsing the tree |

**Key design:** The tree-to-grid and grid-to-tree transitions happen within the same widget iframe. This avoids creating new conversation turns for what is essentially a view toggle. The widget maintains internal state for both modes.

---

## Flow 4D: Navigating Up via Breadcrumb

User jumps back up the hierarchy using the breadcrumb trail.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Animal" in the breadcrumb trail (while viewing Dog subtree at depth 3) | Breadcrumb click | Step 2 |
| 2 | **Widget (hierarchy-browser)** | Calls `tools/call explore_category` for Animal | `app.callServerTool({ name: "explore_category", arguments: { class_name: "Animal", depth: 2 } })` | Step 3 |
| 3 | **MCP Server** | Returns Animal subtree (same as Flow 4A Step 3) | Top-level Animal children | Step 4 |
| 4 | **Widget** | Re-renders at Animal level. Breadcrumb updates to "Entity > Animal". Tree shows top-level animal branches again. | Reset to Animal view | User drills down a different branch |

**Breadcrumb behavior:** Each segment in the breadcrumb is clickable. Clicking any segment navigates to that level via `tools/call explore_category`. The breadcrumb always reflects the current position: "Entity > Animal > Carnivore > Dog".

---

## Flow 4E: Code Mode Entry

User switches to advanced SQL query mode.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types `/start_code_mode` in conversation | MCP prompt trigger | Step 2 |
| 2 | **MCP Client** | Sends prompt directly to MCP server. The LLM is **not involved** — the client routes the prompt to the server without LLM interpretation. | Prompt name: `start_code_mode` | Step 3 |
| 3 | **MCP Server (prompt handler)** | Executes a server-defined workflow: (a) reads `00-mcp-reference.sql` as a resource, (b) assembles messages containing the schema reference, code generation rules, pitfall warnings, and example prompts. Returns messages to the client. The full schema reference (tables, views, common values, query patterns, pitfalls) is now available to the LLM. | Resource: `queries/examples/00-mcp-reference.sql`. Returns: messages array with schema context + instructions | Step 4 |
| 4 | **LLM (conversation text)** | Uses the server-provided messages to compose a response: "Code mode active. I have the full Open Images schema loaded. You can ask me to write SQL queries for anything -- relationships, hierarchy traversal, image analysis, statistics. Try: 'How many images show a person riding a horse?' or 'What are the most common object combinations?'" | LLM adapts server-provided guidance text | Step 5 |
| 5 | **User** | "How many images show a person riding a horse?" | Natural language query for SQL generation | Step 6 |
| 6 | **LLM** | Generates SQL using `hierarchy_relationships` view, ancestor expansion pattern from `00-mcp-reference.sql` Section 3. Uses `ancestor_name_1 = 'Person'` pattern (not `display_name_1 = 'Person'`) to catch Man, Woman, Boy, Girl. Filters `relationship_label != 'is'` per pitfall guidance. | Generated SQL query + explanation | Step 7 |
| 7 | **LLM (conversation text)** | Returns three parts in conversation text (no widget for code mode): (1) The SQL query in a code block, (2) Explanation of what it does and why it uses ancestor expansion, (3) The results (if executable) or expected output pattern, (4) Follow-up suggestions: "You could also count by relationship type, or find which person subtypes ride horses most often." | Pure text response, no widget | User asks another query or switches to tool mode (Flow 4F) |

**Code mode SQL example (from Step 6):**
```sql
SELECT COUNT(DISTINCT image_id) AS image_count
FROM open_images.hierarchy_relationships
WHERE ancestor_name_1 = 'Person'
  AND ancestor_name_2 = 'Horse'
  AND relationship_label IN ('ride', 'on')
  AND relationship_label != 'is';
```

**Code mode rules applied** (from `start_code_mode.instructions.rules`):
- Replace `__DATABASE__` with `open_images`
- Use Athena/Trino SQL dialect
- Prefer views over base tables
- Use `hierarchy_relationships` with `ancestor_name` for parent-class queries
- Filter out 'is' relationship type by default

---

## Flow 4F: Code Mode to Tool Mode Transition

User wants to see images instead of SQL results.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** (in code mode) | "Actually, can you show me those horse riding images?" | Intent to switch from SQL to visual browsing | Step 2 |
| 2 | **LLM** | Recognizes intent to switch to visual mode. Decomposes the code mode context into structured args. | `{ subject: "Person", relationship: "ride", object: "Horse" }` | Step 3 |
| 3 | **MCP Server** | Standard `find_images` query. Returns visual results. | Same as Flow 1B in `01-search-flow.md` | Step 4 |
| 4 | **Widget (results-grid)** | Results-grid widget appears in conversation. User is now in visual tool mode. | Standard grid with facets | Step 5 |
| 5 | **LLM (conversation text)** | "Here are the images. You're now in visual browsing mode -- click any image for details, or use the facets to filter. To return to code mode, type `/start_code_mode` again." | Signals mode transition | User continues in tool mode or re-enters code mode |

**Mode switching is seamless.** There is no explicit "exit code mode" command. The LLM simply starts calling tools when the user's intent shifts from SQL to visual browsing. The user can switch back to code mode at any time with `/start_code_mode`.

---

## Example Query File Mapping

| Example Query File | Maps to Flow | How |
|---|---|---|
| `02-hierarchy-browsing.sql` | Flow 4A, 4B | Hierarchy traversal using `class_hierarchy` view with recursive CTE and root_path |
| `04-subtree-statistics.sql` | Flow 4A | Relationship counts per branch shown in hierarchy-browser node headers |
| `06-category-exploration.sql` | Flow 4A | Category entry point, exploring subcategories of a class |
| `03-relationship-discovery.sql` | Flow 4E | Code mode example -- discovering relationship types via SQL |

---

## Complete Example Query Cross-Reference

All 8 example query files mapped to conversation flows across all four flow documents:

| Example Query File | Flow(s) | How It Maps |
|---|---|---|
| `01-people-on-horses.sql` | 1B, 3C | Relationship query with ancestor expansion; similar scenes navigation |
| `02-hierarchy-browsing.sql` | 4A, 4B | Hierarchy tree navigation using root_path and depth |
| `03-relationship-discovery.sql` | 2A, 4E | Relationship facet clicks; code mode SQL for relationship queries |
| `04-subtree-statistics.sql` | 4A | Branch statistics (image count, relationship types) in hierarchy node headers |
| `05-entity-search.sql` | 1A | Direct class search via MCP prompt (`/find_images`) |
| `06-category-exploration.sql` | 2A, 4A | Category facet in results grid; hierarchy entry via `explore_category` |
| `07-image-contents.sql` | 3A | Multi-table join for single image detail view (labels, boxes, relationships) |
| `08-relationship-inventory.sql` | 1B | Relationship-based search from natural language ("images where X does Y to Z") |

All 8 example query files are accounted for. Each maps to at least one conversation flow. Five map to multiple flows.

---

## Cross-References

- **Entry to hierarchy:** Flow 1C Strategy B (broad query) in `01-search-flow.md`, Flow 3D (explore category from detail) in `03-detail-flow.md`
- **From hierarchy to grid:** Flow 4C transitions to grid mode, which follows `02-refinement-flow.md` patterns
- **From hierarchy to detail:** After grid transition (Flow 4C), clicking a thumbnail enters `03-detail-flow.md`
- **Tool definitions:** `explore_category` and `start_code_mode` prompt in `design/tool-definitions/tools.json`
- **Interaction mechanism:** Tree drill-down uses `tools/call` (deterministic). "View all images" uses `tools/call` for intra-widget mode switch. See `design/patterns/interaction-model.md` Section 2.

---

*Flow: 04-hierarchy-flow*
*Phase: 09-design-navigation-paths-for-ui*
