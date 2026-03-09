# Conversation Flow: Initial Search

How users enter the Open Images search experience. Covers three entry patterns: MCP prompt (structured), natural language (conversational), and broad/ambiguous queries (guided).

**Tool:** `find_images` (see `design/tool-definitions/tools.json`)
**Widget:** `results-grid` (see `design/widget-specs/results-grid.md`)
**Interaction model:** `design/patterns/interaction-model.md`

---

## Flow 1A: MCP Prompt Entry

Example: User types `/find_images dogs`

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types `/find_images dogs` in conversation | Input: MCP prompt with argument "dogs" | Step 2 |
| 2 | **MCP Client** | Sends prompt directly to MCP server. The LLM is **not involved** in this step — the client routes the prompt to the server without LLM interpretation. | Prompt name: `find_images`, args: `{ query: "dogs" }` | Step 3 |
| 3 | **MCP Server (prompt handler)** | Executes a **server-defined workflow** — this is pre-designed logic, not LLM-decided. The workflow: (a) resolves "dogs" to class hierarchy via `class_hierarchy` view, (b) queries `labeled_images` for matching images, (c) queries `class_hierarchy` for subcategories (Poodle, German shepherd, Labrador...), (d) queries `hierarchy_relationships` for relationship context (ride, on, wears), (e) assembles and returns a list of messages back to the client. | SQL views: `labeled_images`, `class_hierarchy`, `hierarchy_relationships`. Returns: messages array containing conversation context + structured tool results with `{ structuredContent, content, _meta }` | Step 4 |
| 4 | **Widget (results-grid)** | Renders in conversation from the structured content in the server's response. Shows: top bar "523 dog images found", facet pills for subcategories (Poodle, German shepherd, Labrador) and relationships (ride, on, wears), 3-column grid of thumbnails with label overlays, "Load more" at bottom. | `_meta.images` (20 thumbnails), `_meta.hierarchy_context` (path, children), `structuredContent.facets` | Step 5 |
| 5 | **LLM (conversation text)** | Uses the context messages returned by the server to compose a response. The server provides pre-written guidance text that the LLM can use directly or adapt: "Found 523 images of dogs across 12 breeds. The most common are Poodle (89), German Shepherd (67), and Labrador (54). You can click a breed to narrow results, or tell me what you're looking for." | Server-provided messages inform the LLM's response | User decides: click facet (Flow 2A), type follow-up (Flow 2B), click thumbnail (Flow 3A) |

**Key characteristic:** Deterministic, server-orchestrated entry. The MCP prompt bypasses LLM reasoning entirely — the server's prompt handler runs a pre-designed workflow that queries the right views, assembles context, and returns messages. The LLM receives the results and presents them, but doesn't decide *what* to query or *how* to structure the search. This guarantees consistent behavior regardless of which LLM hosts the MCP client.

**Architecture note:** The prompt handler on the server may internally call the same `find_images` tool logic, but this is a server-side implementation detail. From the protocol perspective, the client sends a prompt and receives messages back — no tool call is visible to the client or LLM.

---

## Flow 1B: Natural Language Entry

Example: User types "I need photos of people riding horses"

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types "I need photos of people riding horses" in conversation | Free-text input | Step 2 |
| 2 | **LLM** | Decomposes natural language into structured arguments. The tool description instructs: use singular capitalized class names, common top-level classes listed. LLM maps: "people" → `subject: "Person"` (parent class), "horses" → `object: "Horse"`, "riding" → `relationship: "ride"`. Calls `find_images` with structured args. | `{ subject: "Person", relationship: "ride", object: "Horse" }` | Step 3 |
| 3 | **MCP Server** | Receives clean structured input — no NL parsing needed. Uses `hierarchy_relationships` view with `ancestor_name_1='Person'` and `ancestor_name_2='Horse'` and `relationship_label='ride'`. Ancestor expansion resolves Person to Man, Woman, Boy, Girl automatically. Maps to query pattern from `01-people-on-horses.sql`. | SQL views: `hierarchy_relationships`, `labeled_images`, `class_hierarchy`. Returns Man/Woman/Boy/Girl + Horse images with ride relationships. | Step 4 |
| 4 | **Widget (results-grid)** | Facets reflect the structured query: Person subcategories (Man, Woman, Boy, Girl) as category facets, relationship types (ride, on, interacts_with) as relationship facets. Grid shows thumbnails of people-horse scenes. | Facets derived from result set | Step 5 |
| 5 | **LLM (conversation text)** | "Found 149 images of people with horses. The most common relationship is 'ride' (46 images), followed by 'on' (42) and 'interacts_with' (59). Results include men, women, and children. Click a relationship type or person category to narrow down, or describe what you're looking for." | Conversational response using `content` and `structuredContent` | User decides: click facet (Flow 2A), type follow-up (Flow 2B), click thumbnail (Flow 3A) |

**Key characteristic:** The LLM does what it's good at (NL → structure) and the server does what it's good at (structure → SQL). The tool description provides enough inline guidance for the LLM to normalize common terms (people→Person, horses→Horse) and decompose relationships. No NL parsing on the server.

**When the LLM is unsure of a class name** (e.g., "pictures of labradors" — is it "Labrador" or "Labrador retriever"?): the LLM can call `resolve_entity` first to look up the canonical name, then call `find_images` with the resolved name. The LLM may also load the `popular_entities` resource at the start of a long conversation to pre-cache common class names.

**Argument population guidance** (from tool description):
- `subject`/`object`: Singular, capitalized, matching dataset hierarchy names. Tool description lists the 10 most common top-level classes.
- `relationship`: Lowercase. Tool description lists the common relationship types.
- `query`: Free-text fallback for requests that don't decompose cleanly (e.g., "outdoor scenes with bright colors").
- No argument is required — the server handles partial input (subject-only, subject+relationship, query-only, etc.)

### Flow 1B variant: LLM calls resolve_entity first

Example: User types "show me pictures of poodles playing"

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types "show me pictures of poodles playing" | Free-text input | Step 2 |
| 2 | **LLM** | Recognizes "poodles" but unsure of exact class name. Calls `resolve_entity` to validate. | `{ term: "poodle" }` | Step 3 |
| 3 | **MCP Server** | Fuzzy matches "poodle" → returns `[{ display_name: "Poodle", root_path: "Entity > Animal > Carnivore > Dog > Poodle", image_count: 89, match_type: "case_insensitive" }]` | Lightweight JSON response, no widget | Step 4 |
| 4 | **LLM** | Now confident in the name. Calls `find_images` with structured args. | `{ subject: "Poodle", relationship: "plays" }` | Step 5 |
| 5 | **MCP Server** | Queries with resolved class name. If "plays" returns few results, server may expand to related relationships. | Standard find_images response | Widget renders |

**This two-call pattern is optional.** For common classes listed in the tool description (Person, Dog, Horse, Car, etc.), the LLM can call `find_images` directly. `resolve_entity` is for edge cases and unfamiliar terms.

---

## Flow 1C: Broad/Ambiguous Query

Example: User types "show me animals"

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Types "show me animals" | Broad category query | Step 2 |
| 2 | **LLM** | Recognizes broad query. Two strategies available: | | Step 2A or 2B |

### Strategy A: Show Top Results + Suggest Narrowing

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 2A | **LLM** | Calls `find_images` with `subject: "Animal"` | `{ subject: "Animal", limit: 20 }` | Step 3A |
| 3A | **MCP Server** | Queries for Animal class and all descendants. Returns top 20 images with diverse subcategories. Facets show major branches: Bird, Carnivore, Mammal, Invertebrate, Reptile, Fish. | `class_hierarchy` children of Animal at depth+1 as category facets | Step 4A |
| 4A | **Widget (results-grid)** | Renders grid with animal images. Facet pills show the 6 major animal branches with counts. Count bar shows "2,847+ animal images found." | Large result count signals breadth | Step 5A |
| 5A | **LLM (conversation text)** | "Found over 2,800 animal images across 6 major branches. The largest groups are Carnivore (1,200+ images including dogs, cats, bears) and Bird (800+ images). Click a category to narrow down, or ask for a specific animal like 'dogs' or 'eagles'." | Suggests narrowing paths based on hierarchy | User decides next action |

### Strategy B: Show Hierarchy First

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 2B | **LLM** | Calls `explore_category` with `class_name="Animal"` to show the hierarchy tree | `{ class_name: "Animal", depth: 2 }` | Step 3B |
| 3B | **MCP Server** | Returns hierarchy tree for Animal with 2 levels of children. Includes sample images and relationship summaries. Maps to pattern from `02-hierarchy-browsing.sql`. | SQL views: `class_hierarchy`, `labeled_images` (samples) | Step 4B |
| 4B | **Widget (hierarchy-browser)** | Renders tree view with Animal at root, showing Bird, Carnivore, Mammal, etc. as expandable branches. Each branch shows sample thumbnails and image count. | Hierarchy tree with `include_samples: true` | Step 5B |
| 5B | **LLM (conversation text)** | "The Animal category has 6 main branches. Here's the hierarchy so you can browse by type. Click any category to see its subcategories, or click 'View all images' to see matching photos." | Guides user through tree navigation | User explores hierarchy (Flow 4B) or clicks "View all images" (Flow 4C) |

**LLM strategy selection:** The LLM chooses between Strategy A and B based on:
- If the user seems to want images ("show me animals") -> Strategy A (visual results)
- If the user seems to want structure ("what kinds of animals are there?") -> Strategy B (hierarchy)
- If ambiguous, Strategy A is the default (visual-first principle from CONTEXT.md)

---

## Example Query File Mapping

| Example Query File | Maps to Flow | How |
|---|---|---|
| `01-people-on-horses.sql` | Flow 1B | Relationship query with ancestor expansion: `ancestor_name_1='Person'`, `ancestor_name_2='Horse'` |
| `05-entity-search.sql` | Flow 1A | Direct class search by name, straightforward `find_images` call |
| `08-relationship-inventory.sql` | Flow 1B | Relationship-based search, LLM extracts relationship type from natural language |

---

## Cross-References

- **After search completes:** User can refine results via `02-refinement-flow.md` (facet clicks or free-text follow-ups)
- **From results to detail:** User can click a thumbnail to enter `03-detail-flow.md` (image detail view)
- **Broad query to hierarchy:** Strategy B leads to `04-hierarchy-flow.md` (category browsing)
- **Tool definitions:** `find_images` and `explore_category` in `design/tool-definitions/tools.json`
- **Interaction mechanism:** `ui/message` for thumbnail clicks, `tools/call` for facet interactions -- see `design/patterns/interaction-model.md` Section 2

---

*Flow: 01-search-flow*
*Phase: 09-design-navigation-paths-for-ui*
