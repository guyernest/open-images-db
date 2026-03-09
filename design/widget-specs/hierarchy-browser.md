# Hierarchy Browser Widget Specification

Category tree exploration widget with breadcrumb navigation, collapsible tree nodes, sample thumbnails, and a grid-mode transition for viewing all images in a category. Rendered within a single iframe.

## 1. Overview

- **Purpose:** Browse the Open Images class hierarchy as an interactive tree, with sample images at each level and drill-down into subcategories
- **Rendered by:** `explore_category` tool response
- **Widget URI:** `ui://widgets/hierarchy-browser.html`
- **Self-contained:** Transitions between tree-view (browsing hierarchy) and grid-view (viewing category images) within the same iframe. Tree expansion uses `tools/call` for deeper levels; grid-view uses `tools/call` to `find_images`.

## 2. Layout Specification

Two modes within one widget, switchable via internal state.

### Tree Mode (default)

```
+----------------------------------------------------------+
| Entity > Animal > Carnivore > Dog                         |
|----------------------------------------------------------|
| DOG                                          1,234 images |
| 12 relationship types (ride: 45, on: 32, holds: 28)      |
|----------------------------------------------------------|
| v Poodle (89)           [img] [img] [img]                |
|   > Toy Poodle (12)                                      |
|   > Standard Poodle (34)                                 |
| v German shepherd (67)  [img] [img] [img]                |
| > Labrador (54)         [img] [img] [img]                |
| > Bulldog (41)          [img] [img] [img]                |
|   (part) Tail (23)      [img] [img] [img]                |
|----------------------------------------------------------|
| [View all 1,234 Dog images]                               |
+----------------------------------------------------------+
```

#### Breadcrumb Trail (top)

- Shows path from root to current node: e.g., `Entity > Animal > Carnivore > Dog`
- Source: `structuredContent.root_path` split by `" > "`
- Each segment is a clickable link (except the last, which is the current node shown bold)
- Clicking a breadcrumb segment triggers `tools/call` to `explore_category` with that class name
- Separator: `>` character with 4px padding on each side
- Overflow on narrow viewports: truncate from the left with `...` prefix (e.g., `... > Carnivore > Dog`)

#### Current Node Header

- **Class name:** Large text (18px bold), from `structuredContent.class_name`
- **Image count:** Right-aligned badge showing total images for this class, from `_meta.hierarchy_tree.sample_count`
- **Relationship summary:** One-line summary below the class name. Format: `"{count} relationship types (top 3: {label}: {count}, ...)"` from `_meta.relationship_summary[]`. Sorted by count descending, show top 3.
- If no relationships: show "No annotated relationships"

#### Children List

Each child node in `_meta.hierarchy_tree.children[]` renders as an expandable row:

| Element | Source | Behavior |
|---------|--------|----------|
| Expand/collapse arrow | `is_leaf` field | `v` (expanded) or `>` (collapsed). Hidden for leaf nodes. Click toggles local expand/collapse. |
| Class name | `children[].name` | Bold text. Click triggers `tools/call` to `explore_category` for that class (re-renders entire widget with new root). |
| Image count badge | `children[].sample_count` | Muted text in parentheses: `(89)` |
| Edge type indicator | `children[].edge_type` | If `"part"`: prefix with italic "(part)" label and indent 8px extra. Different icon (puzzle piece vs folder). Default `"subcategory"` uses folder icon. |
| Sample thumbnails | `_meta.sample_images[]` matching class | Up to 3 small thumbnails (48x48px, rounded corners) inline after the count badge. Click triggers `ui/message`: `"Show details for image {id} [get_image_details]"`. |

#### Expand/Collapse Behavior

- **Initial render:** Shows 2 levels deep (from `explore_category` depth parameter). First level is expanded, second level collapsed.
- **Expanding a node with already-loaded children:** Toggle visibility (local state, no network call)
- **Expanding a node needing deeper data:** Trigger `tools/call` to `explore_category` with `class_name: {node_name}, depth: 2`. Merge response into widget state. Show spinner on the node during load.
- **Maximum visible depth in one render:** 3 levels (to prevent overwhelming the UI). Nodes at depth 3 always show as collapsed with expand arrows if they have children.

#### "View All Images" Button

- Full-width button at the bottom of the children list
- Text: `"View all {sample_count} {class_name} images"`
- Click transitions widget to Grid Mode

### Grid Mode

```
+----------------------------------------------------------+
| [< Back to Dog hierarchy]                                 |
|----------------------------------------------------------|
| [Poodle 89] [German shepherd 67] [Labrador 54]           |
|----------------------------------------------------------|
| +------------------+ +------------------+ +--------------+|
| | [thumbnail]      | | [thumbnail]      | | [thumbnail]  ||
| | [Dog 95%]        | | [Dog 88%]        | | [Dog 91%]    ||
| +------------------+ +------------------+ +--------------+|
| ...                                                       |
|                              [Load more results]          |
+----------------------------------------------------------+
```

- **Back button:** Top-left, `"< Back to {class_name} hierarchy"`. Returns to Tree Mode (data still in memory, no network call).
- **Facet row:** Limited to subcategories of the current class (from `_meta.hierarchy_tree.children[]` names). Uses same pill design as results-grid widget.
- **Image grid:** Same layout as the results-grid widget (3-col/2-col responsive grid with thumbnails).
- **Data source:** Triggers `tools/call` to `find_images` with `subject: {class_name}` when entering grid mode. Widget renders the response images.
- **Pagination:** Same "Load more" pattern as results-grid widget, using `tools/call` to `find_images` with incremented page.
- **Image click:** Same as results-grid: `ui/message` to `"Show details for image {id} [get_image_details]"` with 5s fallback.

## 3. Data Contract

### From `structuredContent` (model-readable layer)

```json
{
  "class_name": "string -- the explored class display_name",
  "root_path": "string -- full path from Entity root (e.g., 'Entity > Animal > Carnivore > Dog')",
  "depth": "number -- number of hierarchy levels shown below the class",
  "child_count": "number -- total number of direct children",
  "edge_type": "string -- 'subcategory' or 'part'"
}
```

### From `_meta` (widget-exclusive layer)

```json
{
  "hierarchy_tree": {
    "name": "string -- class display_name",
    "mid": "string -- MID identifier (e.g., '/m/0bt9lr')",
    "depth": "number -- depth in overall hierarchy (0 = Entity root)",
    "edge_type": "string -- 'subcategory' or 'part'",
    "is_leaf": "boolean -- true if no children exist",
    "children": [
      {
        "name": "string",
        "mid": "string",
        "depth": "number",
        "edge_type": "string",
        "is_leaf": "boolean",
        "children": ["recursive -- same structure, may be empty array"],
        "sample_count": "number"
      }
    ],
    "sample_count": "number -- total images with this label"
  },
  "relationship_summary": [
    {
      "relationship_label": "string -- relationship type (excluding 'is')",
      "count": "number -- occurrences in dataset"
    }
  ],
  "sample_images": [
    {
      "id": "string -- Open Images image_id",
      "thumbnail_300k_url": "string -- thumbnail URL",
      "class_name": "string -- which class this sample belongs to"
    }
  ]
}
```

### Sample Image Mapping

`_meta.sample_images[]` is a flat array. Each entry has a `class_name` field that maps it to the correct tree node. The widget groups sample images by `class_name` to display the right thumbnails next to each node.

When `include_samples` is false in the tool call, `sample_images` will be an empty array.

## 4. Interaction Behaviors

### Tree Mode Interactions

| Action | Mechanism | Tool | Behavior |
|--------|-----------|------|----------|
| Click child class name | `tools/call` | `explore_category` | Re-render entire widget with clicked class as new root. Update breadcrumb trail. Reset expand/collapse state. |
| Click breadcrumb segment | `tools/call` | `explore_category` | Navigate up to that level. Re-render widget with breadcrumb segment as root. |
| Expand/collapse node (arrow click) | Local state | none | Toggle children visibility. If children data already loaded, no network call. If children need loading (depth exceeded), trigger `tools/call` to `explore_category` with `depth: 2`. |
| Click sample thumbnail | `ui/message` | (triggers `get_image_details`) | `"Show details for image {id} [get_image_details]"`. Show fallback text after 5s. |
| Click "View all images" | `tools/call` | `find_images` | Transition to Grid Mode. Call: `find_images({ subject: "{class_name}" })`. Show loading spinner during transition. |

### Grid Mode Interactions

| Action | Mechanism | Tool | Behavior |
|--------|-----------|------|----------|
| Click back button | Local state | none | Return to Tree Mode. Tree data still in widget memory. No network call. |
| Click subcategory facet | `tools/call` | `find_images` | Filter grid by subcategory. Widget constructs `find_images` args from selection state. Same behavior as results-grid widget facets. |
| Click "Load more" | `tools/call` | `find_images` | Append more images. Widget sends same args with incremented page. Same behavior as results-grid widget pagination. |
| Click image thumbnail | `ui/message` | (triggers `get_image_details`) | Same as results-grid widget: message + 5s fallback. |

### Loading States

- **Tree node expansion (needs data):** Spinner replaces the expand arrow for 0-3s. Then "Loading..." text. Then error + retry after 10s.
- **"View all images" transition:** Full-widget spinner overlay during transition to Grid Mode.
- **Back to tree:** Instant (data in memory). No loading state needed.

### Error Handling

- `tools/call` failure on tree expansion: Show error inline on the node: "Couldn't load subcategories." + small retry link.
- `tools/call` failure on "View all images": Show error in grid area with retry button. Back button still works.
- Same timeout pattern as interaction model: spinner 0-3s, loading 3-10s, error + retry 10s+.

## 5. Tree Rendering Rules

### Depth Limits

- Initial render from `explore_category`: Shows `depth` levels (default 2) below the root node
- First level: expanded by default
- Second level and deeper: collapsed by default
- Maximum visible depth in one render: 3 levels
- Beyond depth 3: nodes show as collapsed with expand arrows. Expanding triggers `tools/call` for deeper data.

### Node Indentation

- Each depth level indented 24px from parent
- Vertical guide lines (1px light gray) connect parent to children on the left side
- Guide lines terminate at the last child node

### Edge Type Visual Treatment

| Edge Type | Icon | Text Style | Indent |
|-----------|------|------------|--------|
| `subcategory` | Folder icon | Normal weight | Standard (24px per level) |
| `part` | Puzzle piece icon | Italic | Standard + 8px extra indent |

"Part" nodes are visually distinct to communicate that "Tail" is a part of "Dog", not a subcategory of "Dog".

### Leaf Nodes

- No expand/collapse arrow (just a bullet or dot)
- Class name + count badge + sample thumbnails (same as non-leaf)
- Clicking class name still triggers `tools/call` to `explore_category` (which will return a node with `is_leaf: true` and empty children)

### Relationship Summary Rendering

- Show top 3 relationships by count in the header area
- Format: `"ride (45), on (32), holds (28)"`
- If more than 3: append `"... and {N} more"` as a tooltip trigger
- Exclude `"is"` relationships from the summary (consistent with overall design)

### Node Interaction Feedback

- Hover on class name: underline + cursor pointer
- Hover on expand arrow: arrow color change
- Hover on sample thumbnail: slight scale (1.05) + border highlight
- Active/loading node: pulsing background highlight

## 6. Accessibility

| Element | ARIA | Keyboard |
|---------|------|----------|
| Breadcrumb trail | `nav` with `aria-label="Category breadcrumb"`, each segment `role="link"` | Tab through segments. Enter to navigate. |
| Tree container | `role="tree"` | Arrow Up/Down to move between visible nodes. |
| Tree node | `role="treeitem"`, `aria-expanded="true/false"` for expandable nodes, `aria-level="{depth}"` | Left arrow collapses. Right arrow expands. Enter to navigate into class. |
| Leaf node | `role="treeitem"`, no `aria-expanded` | Enter to navigate into class. |
| Sample thumbnails | `role="button"`, `alt="{class_name} sample image"` | Tab from parent node. Enter to view details. |
| "View all images" button | Standard `<button>` | Tab to reach. Enter to activate. |
| Grid mode back button | Standard `<button>`, `aria-label="Back to {class_name} hierarchy tree"` | Tab to reach. Enter to return. |

### Focus Management

- Initial focus: first child node in the tree (after breadcrumb)
- After tree expansion: focus moves to the first newly revealed child node
- After breadcrumb navigation: focus moves to the first child of the new root
- Transition to Grid Mode: focus moves to the back button
- Return to Tree Mode: focus moves to the "View all images" button (where they left off)

### Screen Reader Announcements

- On initial render: `"Browsing {class_name} category. {child_count} subcategories, {sample_count} images."`
- On node expand: `"{node_name} expanded. {child_count} children."`
- On breadcrumb navigation: `"Navigated to {class_name}. {child_count} subcategories."`
- On mode transition: `"Viewing all {class_name} images. {total_results} results."`

## 7. Responsive Behavior

| Viewport Width | Tree Mode | Grid Mode |
|----------------|-----------|-----------|
| 600px+ | Full tree with 3 sample thumbnails per node | 3-column image grid |
| 400-599px | 2 sample thumbnails per node | 2-column image grid |
| Below 400px | 1 sample thumbnail per node, relationship summary collapsed by default | 2-column image grid, facets scroll horizontally |

### Breakpoint Details

- **600px+ (default):** Full layout as described. Breadcrumb shows complete path. Children list shows 3 sample thumbnails inline.
- **400-599px:** Breadcrumb truncates from left with `...`. Sample thumbnails reduced to 2 per node. Relationship summary still visible but with fewer top entries (show 2 instead of 3).
- **Below 400px:** Breadcrumb shows only current + parent (e.g., `Carnivore > Dog`). Sample thumbnails reduced to 1 per node. Relationship summary collapsed behind a "Show relationships" toggle. Node indentation reduced to 16px per level.

### Touch Interactions

- Tree node expand/collapse: tap on the arrow area (44x44px minimum touch target)
- Class name navigation: tap on the text (distinct from expand arrow)
- Sample thumbnails: tap to view details (44x44px minimum, larger than the 48px visual size to account for padding)
- Swipe gestures: none (avoids conflicts with host app scrolling)
