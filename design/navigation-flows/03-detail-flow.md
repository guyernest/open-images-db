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
| 5 | **Widget (image-detail)** | Renders below the results grid in conversation. Shows: full-size image with bounding box overlays (toggleable), layer toggle buttons (boxes, labels, relationships, masks), metadata panel with labels table (display_name, source, confidence), relationships list (subject - relationship - object), image info (author, license). Navigate-from-image action buttons derived from `_meta.navigate_actions`: subject buttons ("More with Dog"), relationship buttons ("Person ride Horse"), and category button ("Explore Animal"). | `_meta.labels`, `_meta.boxes`, `_meta.relationships`, `_meta.masks`, `_meta.navigate_actions` | Step 6 |
| 6 | **LLM (conversation text)** | "This image contains a Man riding a Horse outdoors. The Man is wearing a Helmet. There are 3 labeled objects, 2 relationships, and 4 bounding boxes. You can click on any label to find more images of that type, or use the action buttons below the image." | `content[0].text` synthesized from annotation data | User decides: navigate-from-image (Flows 3B-3D), interact with annotations (Flow 3E), or type follow-up |

**The results-grid widget freezes in place** above the new detail widget. The user can scroll up to see it, but it no longer accepts interactions.

---

## Flow 3B: Navigate-From-Image -- "More with [subject]"

User wants to find more images containing a specific object from the current image. The button and pre-computed args come from `_meta.navigate_actions.by_subject[]`.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "More with Dog" button in the image-detail widget | Button derived from `navigate_actions.by_subject[].label` | Step 2 |
| 2 | **Widget (image-detail)** | Reads `find_images_args` from the clicked action. Sends `ui/message`: "Find more images of Dog [find_images]" | `postMessage({ method: "ui/message", params: { role: "user", content: [{ type: "text", text: "Find more images of Dog [find_images]" }] } })`. Pre-computed args: `{ subject: "Dog" }` | Step 3 |
| 3 | **LLM** | Recognizes the tool hint, decomposes into structured args, calls `find_images` | `{ subject: "Dog" }` | Step 4 |
| 4 | **Widget (results-grid)** | New results-grid widget appears below the detail widget, showing dog images with breed facets | Standard `find_images` response | Step 5 |
| 5 | **LLM (conversation text)** | "Here are 523 dog images. The most common breeds are Poodle, German Shepherd, and Labrador. Click a breed or relationship to narrow down." | Standard search response | User continues browsing in the new grid |

**Fallback (Flow 3F applies):** If no new widget appears after 5 seconds, the "More with Dog" button shows: "Try typing: Find more images of Dog". Text is click-to-copy.

---

## Flow 3C: Navigate-From-Image -- Relationship navigation

User wants images with the same relationship pattern. The buttons come from `_meta.navigate_actions.by_relationship[]` — each represents a specific subject-relationship-object triple found in the image, with parent classes pre-resolved by the server (Man→Person).

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Person ride Horse" button in image-detail widget | Button derived from `navigate_actions.by_relationship[].label` | Step 2 |
| 2 | **Widget (image-detail)** | Reads `find_images_args` from the clicked action: `{ subject: "Person", relationship: "ride", object: "Horse" }`. Sends `ui/message`: "Find images where Person ride Horse [find_images]" | Message uses the pre-computed parent class names for broader results | Step 3 |
| 3 | **LLM** | Recognizes the structured relationship query. Calls `find_images` with the three dimensions. | `{ subject: "Person", relationship: "ride", object: "Horse" }` | Step 4 |
| 4 | **Widget (results-grid)** | New results-grid appears with person-horse riding images. Subject facets show Person subcategories (Man, Woman, Boy, Girl). Relationship facets show related types (on, interacts_with). | Ancestor expansion finds all Person subclasses automatically | Step 5 |
| 5 | **LLM (conversation text)** | "Found 149 images of people riding horses. Most subjects are Men (78) and Women (45). You can click a subject type or add a relationship filter to narrow down." | Contextual description | User continues |

**Maps to example query:** `01-people-on-horses.sql` — the ancestor expansion pattern enables finding all person-horse scenes regardless of the specific Person subclass.

**Multiple relationship buttons:** If the image has multiple relationships (e.g., "Man ride Horse" and "Man wears Helmet"), each appears as a separate button. The user picks which relationship to follow. This gives the user explicit control over which dimension to navigate — rather than combining everything into one ambiguous query.

---

## Flow 3D: Navigate-From-Image -- "Explore [category]"

User wants to browse the hierarchy around one of the image's objects. The button comes from `_meta.navigate_actions.explore_category`.

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks "Explore Animal" button (derived from hierarchy path of the Dog label: Entity > Animal > Carnivore > Dog) | Button derived from `navigate_actions.explore_category.label` | Step 2 |
| 2 | **Widget (image-detail)** | Reads `class_name` from the action. Sends `ui/message`: "Explore the Animal category hierarchy [explore_category]" | `navigate_actions.explore_category.class_name` provides the parent class | Step 3 |
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
| 2 | **Widget (image-detail)** | Sends `ui/message`: "Find more images of Horse [find_images]" | Same pattern as Flow 3B — single subject search | Step 3 |
| 3 | **LLM** | Calls `find_images` with structured subject | `{ subject: "Horse" }` | New results-grid widget appears |

### Clicking a Relationship in the Info Panel

| Step | Actor | Action | Data | Next |
|------|-------|--------|------|------|
| 1 | **User** | Clicks on "Man ride Horse" in the relationships list | Click on relationship entry | Step 2 |
| 2 | **Widget (image-detail)** | Resolves leaf→parent (Man→Person) using `_meta.navigate_actions.by_relationship[]` match. Sends `ui/message`: "Find images where Person ride Horse [find_images]" | Uses parent class "Person" for broader results | Step 3 |
| 3 | **LLM** | Calls `find_images` with all three structured dimensions | `{ subject: "Person", relationship: "ride", object: "Horse" }` | New results-grid widget appears |

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
| `01-people-on-horses.sql` | Flow 3C | Relationship navigation with ancestor expansion (Person ride Horse) |

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
