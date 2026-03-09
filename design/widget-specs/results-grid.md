# Results Grid Widget Specification

Self-contained image search results widget with inline facet filtering, thumbnail grid, and pagination. Rendered within a single iframe -- no cross-widget communication.

## 1. Overview

- **Purpose:** Display search results as a visual thumbnail grid with inline filtering controls
- **Rendered by:** `find_images` tool responses
- **Widget URI:** `ui://widgets/results-grid.html`
- **Self-contained:** Facets, pagination, and grid all live in this single iframe. Selection state is managed locally; data refresh uses `tools/call` to `find_images` with args constructed from local state. Server is stateless — every call is self-contained.
- **Data source:** `_meta.images` array for thumbnails, `structuredContent.facets` for filter options, `structuredContent.summary` for header text

## 2. Layout Specification

Target viewport: 600-800px wide (ChatGPT conversation column). All layout uses CSS Grid and Flexbox.

### Top Bar

```
+----------------------------------------------------------+
| [summary text: "523 dog images across 12 breeds"]  [523] |
+----------------------------------------------------------+
```

- Left: `structuredContent.summary` text
- Right: `structuredContent.total_results` count badge
- Background: subtle gray (#f5f5f5), 12px padding, bottom border

### Facet Row

```
+----------------------------------------------------------+
| [Poodle 89] [German shepherd 67] [Labrador 54] [ride 45] |
+----------------------------------------------------------+
```

- Horizontal row below top bar, scrollable overflow on narrow viewports
- **Category pills:** Derived from `structuredContent.facets.categories[]`. Each pill shows `{name} ({count})`.
- **Relationship pills:** Derived from `structuredContent.facets.relationships[]`. Each pill shows `{label} ({count})`. Visually distinct from category pills (different border color or icon prefix).
- **Active state:** Filled background (primary color) with white text. Inactive: outlined with primary color border, transparent background.
- **Clicking a pill** toggles it: active -> inactive removes value from local selection, inactive -> active adds value. Both trigger `tools/call` to `find_images` with args constructed from the updated local selection state.
- **Active pills** show the current local selection. No server-side filter state exists — the widget reconstructs full `find_images` args on every interaction.
- Gap between pills: 8px. Pill padding: 6px 12px. Border-radius: 16px (fully rounded).

### Image Grid

```
+----------------------------------------------------------+
| +------------------+ +------------------+ +--------------+|
| | [thumbnail]      | | [thumbnail]      | | [thumbnail]  ||
| |                  | | |                  | |              ||
| | [Dog 95%]        | | [Cat 88%]        | | [Horse 91%]  ||
| +------------------+ +------------------+ +--------------+|
| +------------------+ +------------------+ +--------------+|
| | [thumbnail]      | | [thumbnail]      | | [thumbnail]  ||
| ...                                                       |
+----------------------------------------------------------+
```

- CSS Grid: `grid-template-columns: repeat(3, 1fr)` at 600px+
- Gap: 8px
- Each cell:
  - `thumbnail_300k_url` rendered as `<img>` with `object-fit: cover`, aspect ratio 1:1 (square crop)
  - Bottom overlay bar (semi-transparent dark background): primary label (first item in `labels[]`) left-aligned, confidence badge right-aligned (e.g., "95%" in a rounded chip)
  - Confidence badge color: green (>=0.9), yellow (0.7-0.89), gray (<0.7)
  - Hover: tooltip showing all labels joined by comma (e.g., "Dog, Poodle, Outdoors")
  - Hover: subtle scale transform (1.02) and box-shadow elevation
  - Click: triggers `ui/message` to request `get_image_details` for that `image_id`
- If `has_boxes` is true: small bounding-box icon in top-right corner of thumbnail
- If `has_relationships` is true: small relationship icon (link symbol) next to the box icon

### Pagination Bar

```
+----------------------------------------------------------+
| Showing 20 of 523                    [Load more results]  |
+----------------------------------------------------------+
```

- Left: "Showing {loaded_count} of {total_results}"
- Right: "Load more results" button
- Clicking "Load more" triggers `tools/call` to `find_images` with `page: current_page + 1` and current selection args
- New images are APPENDED to existing grid (not replaced)
- Button disabled with spinner while loading
- Button hidden when all results are loaded (`loaded_count >= total_results`)

### Empty State

```
+----------------------------------------------------------+
|                                                           |
|       No images match your filters.                       |
|       Try broadening your search.                         |
|                                                           |
|              [Clear all filters]                          |
|                                                           |
+----------------------------------------------------------+
```

- Centered text, muted color
- "Clear all filters" button triggers `tools/call` to `find_images` with original query and no filters
- Only shown when `_meta.images` is an empty array AND filters are active
- If no filters are active and results are empty, show: "No images found for this search. Try a different query." (no button -- user must type in conversation)

## 3. Data Contract

The widget expects this JSON structure from tool responses:

### From `structuredContent` (model-readable layer)

```json
{
  "query": "string -- the search query for display and re-query",
  "total_results": "number -- total matching images across all pages",
  "page": "number -- current page (1-indexed)",
  "facets": {
    "categories": [
      { "name": "string -- category display_name", "count": "number" }
    ],
    "relationships": [
      { "label": "string -- relationship type (excluding 'is')", "count": "number" }
    ],
    "confidence_ranges": [
      { "range": "string -- e.g., '0.9-1.0'", "count": "number" }
    ]
  },
  "summary": "string -- human-readable one-line summary"
}
```

### From `_meta` (widget-exclusive layer)

```json
{
  "images": [
    {
      "id": "string -- Open Images image_id",
      "thumbnail_300k_url": "string -- URL to ~300KB thumbnail",
      "labels": ["string -- human-readable label names"],
      "confidence": "number -- highest confidence among matching labels (0.0-1.0)",
      "has_boxes": "boolean -- bounding box annotations exist",
      "has_relationships": "boolean -- relationship annotations exist"
    }
  ],
  "hierarchy_context": {
    "path": "string -- root path (e.g., 'Entity > Animal > Carnivore > Dog')",
    "children": ["string -- direct subcategory names"],
    "depth": "number -- current depth in hierarchy"
  },
  "query_metadata": {
    "sql_views_used": ["string -- views queried"],
    "execution_time_ms": "number -- server-side query time"
  }
}
```

### Source Tool Mapping

| Field | Source Tool | Notes |
|-------|-----------|-------|
| `structuredContent.*` | `find_images` | Single tool for all search and refinement |
| `_meta.images[]` | `find_images` | Same image shape for initial and refined queries |

## 4. Interaction Behaviors

Every user action maps to a mechanism from the interaction model (`design/patterns/interaction-model.md`).

| Action | Mechanism | Tool | Parameters | Widget Behavior |
|--------|-----------|------|------------|-----------------|
| Click category facet pill | `tools/call` | `find_images` | `subject: {toggled selection}`, plus current relationship/object selections, `page: 1` | Toggle pill state. Construct full args from local selection. Replace grid with filtered results. Reset pagination to page 1. |
| Click relationship facet pill | `tools/call` | `find_images` | `relationship: {toggled selection}`, plus current subject/object selections, `page: 1` | Same as category facet. Toggle pill, reconstruct args, replace grid. |
| Remove active facet toggle | `tools/call` | `find_images` | Remaining selections as args, `page: 1` | Remove value from local selection, re-query. Replace grid. Reset pagination. |
| Click "Load more" | `tools/call` | `find_images` | Current selections as args, `page: {current_page + 1}` | Append new images to existing grid. Update "Showing X of Y" count. Increment current_page. |
| Click image thumbnail | `ui/message` | (triggers `get_image_details`) | Message: `"Show details for image {id} [get_image_details]"` | Show loading overlay on clicked thumbnail (spinner + dimmed). After 5s without response: show fallback text "Try typing: Show details for image {id}". Widget freezes when new detail widget appears below. |
| Click "Clear all filters" | `tools/call` | `find_images` | `subject: {original_subject}`, no other args, `page: 1` | Clear local selection state. Reset grid to unfiltered results. Reset pagination. |

### Loading States

- **Facet click / filter change:** Dim the grid (opacity 0.5), show spinner centered over grid area. Facet pills remain interactive during load (queued clicks cancel previous request).
- **Load more:** Disable the "Load more" button, show inline spinner next to it. Grid remains fully visible and scrollable.
- **Image click:** Loading overlay on the specific thumbnail only. Other thumbnails remain clickable (but additional clicks are no-ops while a ui/message is pending).

### Error Handling

Per interaction model error patterns:
- `tools/call` timeout: Spinner (0-3s) -> "Loading..." (3-10s) -> "Request timed out." + Retry button (10s+)
- `tools/call` empty results: Show empty state (see Layout section)
- `ui/message` no response: Show fallback text after 5s (see image thumbnail click behavior)

## 5. State Management

The widget maintains this internal state:

```javascript
{
  // Selection state — the widget IS the query
  active_subjects: string[],       // e.g., ["Poodle"] — toggled category facets
  active_relationships: string[],  // e.g., ["ride", "on"] — toggled relationship facets
  active_objects: string[],        // e.g., ["Horse"] — toggled object facets
  original_subject: string|null,   // The initial subject from first find_images (for "clear all")

  // Display state
  current_page: number,            // Current pagination page (1-indexed)
  loaded_images: object[],         // Accumulated images across all loaded pages
  total_results: number,           // Total available results
  facets: object,                  // Current facet options from structuredContent

  // Request state
  pending_request: string|null     // Track in-flight tools/call to cancel on new request
}
```

The widget constructs `find_images` args from local state on every interaction:
```javascript
function buildFindImagesArgs() {
  const args = { page: 1, limit: 20 };
  if (active_subjects.length === 1) args.subject = active_subjects[0];
  else if (active_subjects.length > 1) args.subject = active_subjects;
  if (active_relationships.length === 1) args.relationship = active_relationships[0];
  else if (active_relationships.length > 1) args.relationship = active_relationships;
  if (active_objects.length === 1) args.object = active_objects[0];
  else if (active_objects.length > 1) args.object = active_objects;
  return args;
}
```

### State Transitions

| Trigger | State Change |
|---------|-------------|
| Initial render (from `find_images`) | Parse `_meta.images` into `loaded_images`. Set `original_subject` from the initial query subject. Set `current_page` from `structuredContent.page`. Populate `facets` from `structuredContent.facets`. All active arrays = empty (initial results show unfiltered). |
| Facet toggle (from `find_images` via `tools/call`) | Add/remove value in the appropriate active array. Call `find_images` with `buildFindImagesArgs()`. REPLACE `loaded_images` with new response. Update `facets` from new response. Reset `current_page` to 1. |
| Load more (from `find_images` via `tools/call`) | Call `find_images` with current args + `page: current_page + 1`. APPEND new images to `loaded_images`. Increment `current_page`. Selections and facets unchanged. |
| Clear all filters | Clear all active arrays. Call `find_images` with `subject: original_subject`. REPLACE `loaded_images`. Reset `current_page` to 1. |

### Request Cancellation

When a new `tools/call` is triggered while a previous one is in-flight:
- Cancel the previous request (ignore its response when it arrives)
- Update `pending_request` to the new request ID
- This prevents race conditions where a slow filter response overwrites a faster subsequent filter response

## 6. Accessibility

| Element | ARIA | Keyboard |
|---------|------|----------|
| Facet pills | `role="button"`, `aria-pressed="true/false"` for active state, `aria-label="{name}: {count} results"` | Tab to navigate between pills. Enter/Space to toggle. |
| Applied filter chips | `role="button"`, `aria-label="Remove filter: {filter_name}"` | Tab to navigate. Enter/Space to remove. |
| Image grid | `role="grid"` on container, `role="gridcell"` on each image cell | Tab into grid. Arrow keys to navigate between cells. Enter to select (trigger detail view). |
| Image cell | `alt="{labels joined by comma}"` on img element, `aria-label="Image: {primary_label}, {confidence}% confidence"` on cell | Focus ring visible on keyboard navigation. |
| Load more button | Standard `<button>`, `aria-label="Load more results. Showing {count} of {total}"` | Tab to reach. Enter to activate. |
| Loading spinner | `aria-live="polite"`, `aria-label="Loading results"` | Announced by screen reader when loading starts. |
| Empty state | `role="alert"` | Announced immediately when filters produce no results. |

### Focus Management

- After facet toggle: focus returns to the toggled pill (grid content changes but focus stays in facet row)
- After Load more: focus moves to the first newly loaded image cell
- After Clear all filters: focus moves to the first image cell in the refreshed grid

## 7. Responsive Behavior

| Viewport Width | Grid Columns | Facet Row | Thumbnail Size |
|----------------|-------------|-----------|----------------|
| 600px+ | 3 columns | Horizontal row, wraps if needed | ~190px squares |
| 400-599px | 2 columns | Wraps to multiple rows | ~190px squares |
| Below 400px | 2 columns | Horizontal scroll (overflow-x: auto) | ~170px squares |

### Breakpoint Details

- **600px+ (default):** 3-column CSS grid. Facet row displays as flex-wrap row. Top bar shows full summary text. Pagination bar shows count + button side by side.
- **400-599px:** 2-column CSS grid. Facet row wraps to multiple lines. Top bar truncates summary with ellipsis if needed. Count shown on its own line above button.
- **Below 400px:** 2-column CSS grid. Facet row becomes single-line horizontal scroll with `-webkit-overflow-scrolling: touch`. Scroll indicators (fade gradient on edges) hint at more pills. Summary text truncated. Pagination stacks vertically.

### Image Loading

- Thumbnails use `loading="lazy"` for images below the fold
- Placeholder: gray rectangle with shimmer animation while image loads
- Failed image load: show broken-image icon with the primary label as text below
