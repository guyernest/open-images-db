# Conversation Flow: Image Detail View

How users view full image details and navigate from a single image to related content. Covers: entering detail view from grid, navigate-from-image actions (more with label, similar scenes, explore category), annotation interaction, and the ui/message fallback pattern.

**Tool:** `get_image_details` (see `design/tool-definitions/tools.json`)
**Widget:** `image-detail` (see `design/widget-specs/image-detail.md`)
**Interaction model:** `design/patterns/interaction-model.md`

---

## Flow 3A: Entering Detail View (from results grid)

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks a thumbnail in the results-grid widget | Click event on image thumbnail | Step 2 |
| 2 | **Widget (results-grid)** | Sends `ui/message` to the conversation: "Show me details for image {image_id} [get_image_details]" | `postMessage({ method: "ui/message", params: { role: "user", content: [{ type: "text", text: "Show me details for image 000a1249af2bc5f0 [get_image_details]" }] } })` | Step 3 |
| 3 | **LLM** | Receives the message, recognizes the tool hint `[get_image_details]`, calls `get_image_details` with `image_id` | `{ image_id: "000a1249af2bc5f0" }` | Step 4 |
| 4 | **MCP Server** | Queries four views for complete image data. Maps to the query pattern from `07-image-contents.sql`: (1) `labeled_images` for image-level labels with confidence, (2) `labeled_boxes` for bounding box coordinates, (3) `labeled_relationships` for object relationships, (4) `labeled_masks` for segmentation masks. Joins with `images` table for metadata (author, license, URLs). Assembles three-layer response with `navigate_actions` pre-computed. | SQL views: `labeled_images`, `labeled_boxes`, `labeled_relationships`, `labeled_masks`, `images`. Output: full annotation payload in `_meta` | Step 5 |
| 5 | **Widget (image-detail)** | Renders below the results grid in conversation. Shows: full-size image with bounding box overlays (toggleable), layer toggle buttons (boxes, labels, relationships, masks), metadata panel with labels table (display_name, source, confidence), relationships list (subject - relationship - object), image info (author, license). Navigate-from-image action buttons at the bottom. | `_meta.labels`, `_meta.boxes`, `_meta.relationships`, `_meta.masks`, `_meta.navigate_actions` | Step 6 |
| 6 | **LLM (conversation text)** | "This image contains a Man riding a Horse outdoors. The Man is wearing a Helmet. There are 3 labeled objects, 2 relationships, and 4 bounding boxes. You can click on any label to find more images of that type, or use the action buttons below the image." | `content[0].text` synthesized from annotation data | User decides: navigate-from-image (Flows 3B-3D), interact with annotations (Flow 3E), or type follow-up |

**The results-grid widget freezes in place** above the new detail widget. The user can scroll up to see it, but it no longer accepts interactions.

---

## Flow 3B: Navigate-From-Image -- "More with [label]"

User wants to find more images containing a specific object from the current image.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "More with Dog" button in the image-detail widget | Click on navigate action button | Step 2 |
| 2 | **Widget (image-detail)** | Sends `ui/message`: "Find more images of Dog [find_images]" | `postMessage({ method: "ui/message", params: { role: "user", content: [{ type: "text", text: "Find more images of Dog [find_images]" }] } })` | Step 3 |
| 3 | **LLM** | Recognizes the tool hint, calls `find_images` with `query: "Dog"` | `{ query: "Dog" }` | Step 4 |
| 4 | **Widget (results-grid)** | New results-grid widget appears below the detail widget, showing dog images with breed facets | Standard `find_images` response | Step 5 |
| 5 | **LLM (conversation text)** | "Here are 523 dog images. The most common breeds are Poodle, German Shepherd, and Labrador. Click a breed or relationship to narrow down." | Standard search response | User continues browsing in the new grid |

**Fallback (Flow 3F applies):** If no new widget appears after 5 seconds, the "More with Dog" button shows: "Try typing: Find more images of Dog". Text is click-to-copy.

---

## Flow 3C: Navigate-From-Image -- "Similar scenes"

User wants images with the same combination of objects/relationships.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Similar scenes" button in image-detail widget | Click on navigate action | Step 2 |
| 2 | **Widget (image-detail)** | Reads the image's label set from `_meta.navigate_actions.same_objects`. Sends `ui/message`: "Find images containing Man, Horse, and Helmet [find_images]" | Message includes the primary labels from the current image | Step 3 |
| 3 | **LLM** | Interprets as a multi-class search. Calls `find_images` with a combined query. May also pass `relationship: "ride"` if relationships were prominent. | `{ query: "Man Horse Helmet", relationship: "ride" }` | Step 4 |
| 4 | **Widget (results-grid)** | New results-grid appears with images containing similar object combinations. Facets show the shared labels and relationships. | Multi-class query results | Step 5 |
| 5 | **LLM (conversation text)** | "Found 23 images with people, horses, and helmets. Most show riding scenes. You can remove any of the object filters to broaden results." | Contextual description | User continues |

**Maps to example query:** `01-people-on-horses.sql` -- the ancestor expansion pattern enables finding all person-horse scenes regardless of the specific Person subclass (Man, Woman, Boy, Girl).

---

## Flow 3D: Navigate-From-Image -- "Explore [category]"

User wants to browse the hierarchy around one of the image's objects.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Explore Animal" button (derived from hierarchy path of the Dog label: Entity > Animal > Carnivore > Dog) | Navigate action referencing parent category | Step 2 |
| 2 | **Widget (image-detail)** | Sends `ui/message`: "Explore the Animal category hierarchy [explore_category]" | `_meta.navigate_actions.same_category` provides the category name | Step 3 |
| 3 | **LLM** | Recognizes hierarchy exploration intent. Calls `explore_category` with `class_name: "Animal"` | `{ class_name: "Animal", depth: 2 }` | Step 4 |
| 4 | **Widget (hierarchy-browser)** | New hierarchy-browser widget appears below. Shows Animal subtree with Bird, Carnivore, Mammal, etc. as expandable branches. | Standard `explore_category` response | Step 5 |
| 5 | **LLM (conversation text)** | "The Animal category has 6 main branches. Dog is under Carnivore. You can explore any branch or click 'View all images' to see photos." | Guides hierarchy browsing | User enters hierarchy flow (Flow 4B in `04-hierarchy-flow.md`) |

---

## Flow 3E: Interacting with Annotations

User clicks on visual elements within the image-detail widget.

### Clicking a Bounding Box Label

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks on a bounding box label overlay (e.g., the "Horse" label on the horse bounding box) | Click on annotation overlay | Step 2 |
| 2 | **Widget (image-detail)** | Sends `ui/message`: "Find more images of Horse [find_images]" | Same pattern as Flow 3B | Step 3 |
| 3 | **LLM** | Calls `find_images` for Horse | `{ query: "Horse" }` | New results-grid widget appears |

### Clicking a Relationship in the Info Panel

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks on "Man ride Horse" in the relationships list | Click on relationship entry | Step 2 |
| 2 | **Widget (image-detail)** | Sends `ui/message`: "Find images where Person ride Horse [find_images]" | Uses parent class "Person" (from hierarchy) instead of leaf "Man" for broader results | Step 3 |
| 3 | **LLM** | Calls `find_images` with query and relationship filter | `{ query: "Person Horse", relationship: "ride" }` | New results-grid widget appears |

### Toggling Annotation Layers

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Toggles the "Relationships" layer off, "Masks" layer on | Layer toggle buttons | Step 2 |
| 2 | **Widget (image-detail)** | Re-renders the image overlay locally (no server call). Hides relationship lines, shows segmentation masks. | Purely client-side rendering change | Step 3 |
| 3 | **Widget (image-detail)** | Sends `ui/update-model-context` to sync: `{ active_layers: ["boxes", "labels", "masks"], viewing: "image 000a1249af2bc5f0" }` | Context sync so LLM knows what user is looking at | No new turn |

---

## Flow 3F: ui/message Fallback Pattern

All navigate-from-image actions use `ui/message`, which is MEDIUM reliability. This flow documents the universal fallback.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **Widget** | Sends `ui/message` with tool hint | Any navigate action | Step 2 |
| 2 | **Widget** | Starts 5-second timer | Waiting for new conversation turn | Step 3 or Step 4 |
| 3 | **Host** | New conversation turn appears (LLM called the tool). Timer cancelled. | Success path | Navigate action complete |
| 4 | **Widget** (after 5s, no new turn) | Shows fallback text below the action button: "It looks like that didn't work. Try typing: {the exact text that was sent}" | Fallback display | Step 5 |
| 5 | **User** | Clicks the fallback text (click-to-copy to clipboard). Pastes into conversation input and sends. | Manual text entry | Step 6 |
| 6 | **LLM** | Processes the pasted text normally. Calls the appropriate tool. | Standard conversation flow | New widget appears |

**Fallback design principles:**
- The fallback text matches exactly what was sent via `ui/message` (including the `[tool_name]` hint)
- Click-to-copy reduces friction (user does not need to type)
- The fallback appears after 5 seconds -- long enough for normal LLM response time, short enough to not frustrate
- After 10 seconds with no response, the fallback text becomes more prominent (larger, colored)

---

## Example Query File Mapping

| Example Query File | Maps to Flow | How |
|---|---|---|
| `07-image-contents.sql` | Flow 3A | Multi-table join for single image: labels, boxes, relationships |
| `01-people-on-horses.sql` | Flow 3C | Similar scenes using relationship-based search with ancestor expansion |

---

## Cross-References

- **Entry to detail:** Thumbnail click from any `results-grid` widget (Flow 2A/2B results, Flow 1A/1B/1C search results)
- **From detail to search:** Navigate-from-image actions lead back to `01-search-flow.md` (new `find_images` call)
- **From detail to hierarchy:** "Explore [category]" leads to `04-hierarchy-flow.md`
- **Tool definition:** `get_image_details` in `design/tool-definitions/tools.json`
- **Interaction mechanism:** All navigate-from-image actions use `ui/message` with fallback per `design/patterns/interaction-model.md` Section 3

---

*Flow: 03-detail-flow*
*Phase: 09-design-navigation-paths-for-ui*
