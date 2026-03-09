# Image Detail Widget Specification

Single image deep-view widget with annotation overlays (bounding boxes, relationship lines), metadata panel, and navigate-from-image actions. Rendered within a single iframe.

## 1. Overview

- **Purpose:** Display a single image at maximum size with all annotations as toggleable overlay layers, plus metadata and navigation actions
- **Rendered by:** `get_image_details` tool response
- **Widget URI:** `ui://widgets/image-detail.html`
- **Self-contained:** All annotation rendering, layer toggling, and navigation actions happen within this iframe. Navigate-from-image actions use `ui/message` to create new conversation turns.

## 2. Layout Specification

Two-panel vertical layout within the iframe. Target viewport: 600-800px wide.

### Image Panel (top 60% of iframe height)

```
+----------------------------------------------------------+
|                                              [B] [L] [R]  |
|                                                           |
|              +------+                                     |
|              | Dog  |                                     |
|              |      +--------+                            |
|              |      | Ball   |                            |
|              +------+--------+                            |
|                  ---- plays_with ----                     |
|                                                           |
+----------------------------------------------------------+
```

- **Image display:** Full width of iframe. Use `original_url` if available, fall back to `thumbnail_300k_url`. Maintain aspect ratio (`object-fit: contain` on a dark background).
- **Annotation overlay layers** (absolutely positioned `<div>` elements over the image):
  - **Bounding boxes:** Colored rectangles using normalized coordinates (`x_min * image_width`, etc.). Label text positioned above each box in a pill-shaped badge matching the box color.
  - **Relationship lines:** Dashed lines (SVG `<line>` or CSS) connecting center of `subject_box` to center of `object_box`. `relationship_label` displayed at the midpoint in a small badge.
- **Layer toggle buttons** (top-right corner of image panel, overlaid):
  - "Boxes" toggle (default: ON)
  - "Labels" toggle (default: ON)
  - "Relationships" toggle (default: ON)
  - Toggle buttons use filled/outlined style to indicate on/off state
  - Toggling is local state only -- no `tools/call` needed
- **If no boxes AND no relationships exist:** Display labels as a horizontal chip bar below the image instead of overlays. Each chip shows `display_name` with a confidence indicator.

### Info Panel (bottom 40%, scrollable)

```
+----------------------------------------------------------+
| METADATA                                                  |
| Author: John Smith  |  License: CC BY 4.0  |  1.2 MB     |
|----------------------------------------------------------|
| LABELS                                                    |
| Dog          human   95%  ████████████████░░░             |
| Ball         machine 82%  █████████████░░░░░░             |
| Outdoors     machine 71%  ██████████░░░░░░░░░             |
|----------------------------------------------------------|
| RELATIONSHIPS                                             |
| Dog [plays with] Ball         87%                         |
| Dog [at] Outdoors             73%                         |
| [ ] Show 'is' relationships                               |
|----------------------------------------------------------|
| ACTIONS                                                   |
| [More with Dog] [Similar scenes] [Explore Animal]         |
+----------------------------------------------------------+
```

#### Metadata Section

- **Author:** `structuredContent.metadata.author`
- **License:** `structuredContent.metadata.license` as a clickable link (if URL-like)
- **Title:** `structuredContent.metadata.title` (if not null)
- **Size:** `structuredContent.metadata.original_size` formatted as human-readable (e.g., "1.2 MB")
- **Rotation:** `structuredContent.metadata.rotation` (show only if non-zero, e.g., "Rotated 90 degrees")
- Layout: horizontal key-value pairs separated by vertical dividers

#### Labels Section

Table with columns:

| Column | Source | Display |
|--------|--------|---------|
| Label | `_meta.labels[].display_name` | Text, clickable (triggers `ui/message` search) |
| Source | `_meta.labels[].source` | Badge: "human" (green) or "machine" (blue) |
| Confidence | `_meta.labels[].confidence` | Percentage bar (filled proportional to value) + percentage text |

- Sorted by confidence descending
- Clicking a label name triggers `ui/message`: `"Find more images of {display_name} [find_images]"`

#### Relationships Section

- List format: `"{display_name_1} [{relationship_label}] {display_name_2}"` with confidence percentage
- **Default:** Filter out relationships where `relationship_label == "is"` (attribute/state relationships dominate at 81.8%)
- **Toggle:** Checkbox `"Show 'is' relationships"` at bottom of section. When checked, includes attribute relationships.
- Clicking a relationship triggers `ui/message`: `"Find images where {display_name_1} {relationship_label} {display_name_2} [find_images]"`
- If no relationships exist: show "No relationships annotated for this image."

#### Navigate-From-Image Actions

Button row at the bottom of the info panel:

| Button Text | Mechanism | Message Text | Source Data |
|-------------|-----------|-------------|-------------|
| "More with {primary_label}" | `ui/message` | `"Find more images of {primary_label} [find_images]"` | `_meta.navigate_actions.more_like_this` or first label |
| "Similar scenes" | `ui/message` | `"Find images with similar objects to image {id} [find_images]"` | Uses the image's label set for context |
| "Explore {category}" | `ui/message` | `"Explore the {root_category} category hierarchy [explore_category]"` | `_meta.navigate_actions.same_category` or derive from `_meta.labels[0]` hierarchy |

- All buttons follow the fallback pattern: after 5 seconds without LLM response, show copy-paste hint text below the button (e.g., `Try typing: "Find more images of Dog"`)
- Buttons disabled while a `ui/message` is pending (prevent double-send)

## 3. Data Contract

### From `structuredContent` (model-readable layer)

```json
{
  "image_id": "string -- Open Images image identifier",
  "thumbnail_300k_url": "string -- display-ready thumbnail URL",
  "original_url": "string -- full resolution image URL",
  "metadata": {
    "author": "string",
    "license": "string -- license name or URL",
    "title": "string|null",
    "rotation": "number -- EXIF rotation in degrees",
    "original_size": "number -- file size in bytes"
  }
}
```

### From `_meta` (widget-exclusive layer)

```json
{
  "labels": [
    {
      "display_name": "string -- human-readable label",
      "source": "string -- 'verification' (human) or 'machine'",
      "confidence": "number -- 0.0 to 1.0"
    }
  ],
  "boxes": [
    {
      "display_name": "string -- object class name",
      "coordinates": {
        "x_min": "number -- normalized 0.0-1.0",
        "y_min": "number -- normalized 0.0-1.0",
        "x_max": "number -- normalized 0.0-1.0",
        "y_max": "number -- normalized 0.0-1.0"
      },
      "confidence": "number -- 0.0 to 1.0",
      "is_occluded": "boolean",
      "is_truncated": "boolean",
      "is_group_of": "boolean",
      "is_depiction": "boolean"
    }
  ],
  "relationships": [
    {
      "display_name_1": "string -- subject entity",
      "relationship_label": "string -- relationship type",
      "display_name_2": "string -- object entity",
      "subject_box": {
        "x_min": "number", "y_min": "number",
        "x_max": "number", "y_max": "number"
      },
      "object_box": {
        "x_min": "number", "y_min": "number",
        "x_max": "number", "y_max": "number"
      }
    }
  ],
  "masks": [
    {
      "display_name": "string -- object class name",
      "mask_path": "string -- S3 path to segmentation mask PNG",
      "predicted_iou": "number -- mask quality score"
    }
  ],
  "navigate_actions": {
    "more_like_this": "string -- query for similar images by primary label",
    "same_objects": ["string -- queries for images with same objects"],
    "same_relationships": ["string -- queries for same relationship patterns"],
    "same_category": "string -- query to browse parent category"
  }
}
```

## 4. Interaction Behaviors

| Action | Mechanism | Behavior |
|--------|-----------|----------|
| Toggle "Boxes" layer | Local state | Show/hide all bounding box `<div>` overlays. Label badges above boxes also hide. |
| Toggle "Labels" layer | Local state | Show/hide label text badges on bounding boxes. Boxes remain visible if "Boxes" is on. |
| Toggle "Relationships" layer | Local state | Show/hide relationship lines and midpoint labels. |
| Click navigate action button | `ui/message` | Send pre-formatted message text. Disable button. Show spinner on button. After 5s: show fallback copy-paste text below button. |
| Click label name in info panel | `ui/message` | `"Find more images of {display_name} [find_images]"`. Show fallback after 5s. |
| Click relationship in info panel | `ui/message` | `"Find images where {display_name_1} {relationship_label} {display_name_2} [find_images]"`. Show fallback after 5s. |
| Hover bounding box | Local state | Highlight box border (increase width/brightness). Show tooltip with: `display_name`, confidence percentage, flags (occluded/truncated/group/depiction). |
| Toggle "Show 'is' relationships" | Local state | Re-render relationships list to include/exclude `is` type relationships. |

### Context Sync

On initial render and after any toggle interaction, send `ui/update-model-context`:

```json
{
  "current_view": "image-detail",
  "image_id": "{id}",
  "active_layers": ["boxes", "labels", "relationships"],
  "visible_labels": ["{top 5 labels by confidence}"]
}
```

This ensures the LLM knows what the user is currently viewing if they type a follow-up question in conversation.

## 5. Annotation Rendering Rules

### Coordinate Normalization

All coordinates in `_meta.boxes[]` and `_meta.relationships[]` are normalized (0.0-1.0). Convert to pixel positions:

```
pixel_x = normalized_x * rendered_image_width
pixel_y = normalized_y * rendered_image_height
```

The image `<img>` element's rendered dimensions (after `object-fit: contain`) determine the scaling. Account for letterboxing: if the image is letterboxed, offset coordinates by the letterbox padding.

### Bounding Box Colors

Deterministic color assignment based on `display_name`:

```javascript
function classColor(displayName) {
  // Hash display_name to index into a 12-color palette
  const hash = displayName.split('').reduce((h, c) => ((h << 5) - h + c.charCodeAt(0)) | 0, 0);
  return PALETTE[Math.abs(hash) % PALETTE.length];
}

// 12-color palette (colorblind-friendly, high contrast on images)
const PALETTE = [
  '#e6194b', '#3cb44b', '#4363d8', '#f58231',
  '#911eb4', '#42d4f4', '#f032e6', '#bfef45',
  '#fabed4', '#469990', '#dcbeff', '#9A6324'
];
```

Same class always gets the same color across all boxes in the image.

### Box Rendering

- Border: 2px solid, class color. Border-radius: 2px.
- Label badge: positioned above the box (or below if box is at top edge). Class color background, white text, 10px font, 4px padding, 4px border-radius.
- **`is_depiction` boxes:** Dashed border style (`border-style: dashed`)
- **`is_group_of` boxes:** Double border style (`border-style: double`, 4px width)
- **`is_occluded` boxes:** Normal style but with a small "occluded" indicator icon in the badge
- **`is_truncated` boxes:** Normal style but box edges that touch image boundary are highlighted (thicker border on the truncated edge)

### Z-Index Ordering

- Higher confidence boxes render on top (higher z-index)
- Within same confidence: smaller boxes render on top (so they are not hidden behind larger boxes)
- Formula: `z-index = Math.round(confidence * 1000) + Math.round((1 - area) * 100)`
  - Where `area = (x_max - x_min) * (y_max - y_min)`

### Relationship Lines

- Draw SVG `<line>` from center of `subject_box` to center of `object_box`:
  - `subject_center_x = (subject_box.x_min + subject_box.x_max) / 2 * image_width`
  - `subject_center_y = (subject_box.y_min + subject_box.y_max) / 2 * image_height`
  - Same for object_box
- Line style: dashed (4px dash, 4px gap), 2px stroke width, white with 80% opacity
- Drop shadow on line for visibility against both light and dark backgrounds
- Label at midpoint: small badge with `relationship_label` text, semi-transparent dark background, white text

### Overlapping Boxes

When multiple boxes overlap significantly (>50% IoU):
- Render all boxes but offset label badges to avoid text overlap
- Stack labels vertically if they would overlap horizontally
- On hover: bring hovered box to top z-index and dim other boxes (opacity 0.3)

## 6. Accessibility

| Element | ARIA | Keyboard |
|---------|------|----------|
| Image | `role="img"`, `alt="{all labels joined by comma}"` | -- |
| Layer toggles | `role="switch"`, `aria-checked="true/false"`, `aria-label="Toggle {layer} overlay"` | Tab between toggles. Space to flip. |
| Bounding boxes | `role="button"`, `aria-label="{display_name}, {confidence}% confidence"` | Tab through boxes (ordered by confidence). Enter to show tooltip. |
| Labels in info panel | `role="link"`, `aria-label="Search for more {display_name} images"` | Tab through labels. Enter to search. |
| Relationships in info panel | `role="link"`, `aria-label="Search for {subject} {relationship} {object}"` | Tab through relationships. Enter to search. |
| Navigate action buttons | Standard `<button>`, `aria-label="{button text}"` | Tab to reach. Enter to activate. |
| Info panel | `role="complementary"`, scrollable via keyboard | Tab into panel. Arrow keys to scroll. |

### Focus Management

- Initial focus: first layer toggle button (user can immediately toggle layers)
- After clicking a navigate action: focus remains on the button (response appears in conversation below)
- Screen reader: announce image contents on load (`aria-live="polite"` region with label summary)

## 7. Responsive Behavior

| Viewport Width | Image Panel | Info Panel |
|----------------|-------------|------------|
| 600px+ | 60% height, full width | 40% height, scrollable |
| Below 600px | 50% height | 50% height, scrollable |
| Below 400px | Image fills width, fixed 250px height | Remaining height, scrollable |

- Layer toggles: always visible in top-right of image, regardless of viewport
- Annotation overlays scale with the image (normalized coordinates handle this automatically)
- Info panel sections stack vertically in all viewport sizes
- Navigate action buttons: wrap to multiple rows on narrow viewports
