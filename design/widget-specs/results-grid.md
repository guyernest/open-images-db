# Results Grid Widget Specification

Self-contained image search results widget with inline facet filtering, thumbnail grid, and pagination. Rendered within a single iframe -- no cross-widget communication.

## 1. Overview

- **Purpose:** Display search results as a visual thumbnail grid with inline filtering controls
- **Rendered by:** `find_images` and `narrow_results` tool responses
- **Widget URI:** `ui://widgets/results-grid.html`
- **Self-contained:** Facets, pagination, and grid all live in this single iframe. Filter state is managed locally; data refresh uses `tools/call` to `narrow_results`.
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
- **Clicking a pill** toggles it: active -> inactive removes filter, inactive -> active adds filter. Both trigger `tools/call` to `narrow_results`.
- **Applied filters from `narrow_results` response:** If `structuredContent.applied_filters` is present, render those as removable chips (with X icon) at the start of the facet row.
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
- Clicking "Load more" triggers `tools/call` to `narrow_results` with `page: current_page + 1` and all active filters
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
  "applied_filters": ["string -- currently active filter expressions (from narrow_results only)"],
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
| `structuredContent.*` | `find_images`, `narrow_results` | Both tools produce identical structuredContent shape |
| `_meta.images[]` | `find_images`, `narrow_results` | Same image shape from both tools |
| `applied_filters` | `narrow_results` only | Not present in initial `find_images` response |

## 4. Interaction Behaviors

Every user action maps to a mechanism from the interaction model (`design/patterns/interaction-model.md`).

| Action | Mechanism | Tool | Parameters | Widget Behavior |
|--------|-----------|------|------------|-----------------|
| Click category facet pill | `tools/call` | `narrow_results` | `filter: "category:{name}"`, `previous_query: {current_query}`, `page: 1` | Replace grid with filtered results. Update facet pill to active state. Reset pagination to page 1. |
| Click relationship facet pill | `tools/call` | `narrow_results` | `filter: "relationship:{label}"`, `previous_query: {current_query}`, `page: 1` | Same as category facet. Relationship pills use same active/inactive toggle. |
| Remove applied filter chip | `tools/call` | `narrow_results` | `filter: {remaining_filters}`, `previous_query: {current_query}`, `page: 1` | Re-query without the removed filter. Replace grid. Reset pagination. |
| Click "Load more" | `tools/call` | `narrow_results` | `previous_query: {current_query}`, `filter: {active_filters}`, `page: {current_page + 1}` | Append new images to existing grid. Update "Showing X of Y" count. Increment current_page. |
| Click image thumbnail | `ui/message` | (triggers `get_image_details`) | Message: `"Show details for image {id} [get_image_details]"` | Show loading overlay on clicked thumbnail (spinner + dimmed). After 5s without response: show fallback text "Try typing: Show details for image {id}". Widget freezes when new detail widget appears below. |
| Click "Clear all filters" | `tools/call` | `find_images` | `query: {original_query}` | Reset grid to unfiltered state. Clear all active filter pills. Reset pagination. |

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
  original_query: string,       // The initial search query (never modified by filters)
  current_query: string,        // May include filter context
  active_filters: string[],     // Array of active filter expressions (e.g., ["category:Poodle", "relationship:ride"])
  current_page: number,         // Current pagination page (1-indexed)
  loaded_images: object[],      // Accumulated images across all loaded pages
  total_results: number,        // Total available results
  facets: object,               // Current facet options from structuredContent
  pending_request: string|null  // Track in-flight tools/call to cancel on new request
}
```

### State Transitions

| Trigger | State Change |
|---------|-------------|
| Initial render (from `find_images`) | Parse `_meta.images` into `loaded_images`. Set `original_query` and `current_query` from `structuredContent.query`. Set `current_page` from `structuredContent.page`. Populate `facets` from `structuredContent.facets`. `active_filters` = empty. |
| Facet toggle (from `narrow_results`) | REPLACE `loaded_images` with new response images. Update `facets` from new response. Add/remove filter from `active_filters`. Reset `current_page` to 1. |
| Load more (from `narrow_results`) | APPEND new images to `loaded_images`. Increment `current_page`. Facets and filters unchanged. |
| Clear all filters (from `find_images`) | REPLACE `loaded_images`. Clear `active_filters`. Reset `current_page` to 1. Restore `current_query` to `original_query`. |

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
