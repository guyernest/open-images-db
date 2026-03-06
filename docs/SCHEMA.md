# Open Images Athena Schema

The `open_images` database runs on Amazon Athena Engine v3 and contains **7 Iceberg tables** and **4 convenience views** built from the Open Images V7 validation set (~42,000 images). All tables use Parquet format with Snappy compression and are stored in the project S3 bucket under the `warehouse/` prefix.

The Athena workgroup is `open-images`. All queries should target the `open_images` database.

---

## Tables

### images

- **Source CSV:** `validation-images-with-rotation.csv`
- **Row count:** ~42,000
- **Raw table:** `raw_images`

| Column | Type | Nullable | Description | Source CSV Column |
|--------|------|----------|-------------|-------------------|
| image_id | VARCHAR | No | Unique 16-character hex image identifier (e.g., `000a1249af2bc5f0`) | ImageID |
| subset | VARCHAR | No | Dataset subset (always `validation` for this dataset) | Subset |
| original_url | VARCHAR | Yes | Original Flickr image URL | OriginalURL |
| original_landing_url | VARCHAR | Yes | Flickr page URL for the image | OriginalLandingURL |
| license | VARCHAR | Yes | Creative Commons license URL | License |
| author_profile_url | VARCHAR | Yes | Flickr profile URL of the image author | AuthorProfileURL |
| author | VARCHAR | Yes | Author display name | Author |
| title | VARCHAR | Yes | Image title from Flickr | Title |
| original_size | INT | Yes | Original image file size in bytes; cast from STRING, empty values become NULL | OriginalSize |
| original_md5 | VARCHAR | Yes | MD5 hash of the original image file | OriginalMD5 |
| thumbnail_300k_url | VARCHAR | Yes | URL for ~300KB thumbnail version | Thumbnail300KURL |
| rotation | DOUBLE | Yes | EXIF rotation angle in degrees; cast from STRING, empty values become NULL | Rotation |

---

### class_descriptions

- **Source CSV:** `oidv7-class-descriptions.csv`
- **Row count:** ~601
- **Raw table:** `raw_class_descriptions`
- **Note:** Assumes CSV has a header row (`skip.header.line.count=1`)

| Column | Type | Nullable | Description | Source CSV Column |
|--------|------|----------|-------------|-------------------|
| label_name | VARCHAR | No | Machine-readable label identifier (MID format, e.g., `/m/011k07`) | LabelName |
| display_name | VARCHAR | No | Human-readable class name (e.g., `Tortoise`) | DisplayName |

---

### labels

- **Source CSVs:** `oidv7-val-annotations-human-imagelabels.csv` + `oidv7-val-annotations-machine-imagelabels.csv`
- **Row count:** Combined from both human and machine annotations via UNION ALL
- **Raw tables:** `raw_labels_human`, `raw_labels_machine`
- **Note:** The `confidence` column is cast from STRING to DOUBLE

| Column | Type | Nullable | Description | Source CSV Column |
|--------|------|----------|-------------|-------------------|
| image_id | VARCHAR | No | References `images.image_id` | ImageID |
| source | VARCHAR | No | Annotation source: `verification` (human) or `machine` | Source |
| label_name | VARCHAR | No | References `class_descriptions.label_name` (MID) | LabelName |
| confidence | DOUBLE | No | Confidence score between 0.0 and 1.0 | Confidence |

---

### bounding_boxes

- **Source CSV:** `validation-annotations-bbox.csv`
- **Row count:** ~303,000
- **Raw table:** `raw_bounding_boxes`
- **Note:** The raw CSV has 21 columns including 8 `x_click` columns; only 13 columns are kept in the Iceberg table. Coordinates are normalized to the 0.0-1.0 range. Boolean columns are cast from `'0'`/`'1'` strings.

| Column | Type | Nullable | Description | Source CSV Column |
|--------|------|----------|-------------|-------------------|
| image_id | VARCHAR | No | References `images.image_id` | ImageID |
| source | VARCHAR | No | Annotation source (`freeform`, `activemil`, `xclick`) | Source |
| label_name | VARCHAR | No | References `class_descriptions.label_name` (MID) | LabelName |
| confidence | DOUBLE | No | Confidence score (1.0 for human annotations) | Confidence |
| x_min | DOUBLE | No | Left edge of bounding box (normalized 0.0-1.0) | XMin |
| x_max | DOUBLE | No | Right edge of bounding box (normalized 0.0-1.0) | XMax |
| y_min | DOUBLE | No | Top edge of bounding box (normalized 0.0-1.0) | YMin |
| y_max | DOUBLE | No | Bottom edge of bounding box (normalized 0.0-1.0) | YMax |
| is_occluded | BOOLEAN | No | Whether the object is partially hidden by another object | IsOccluded |
| is_truncated | BOOLEAN | No | Whether the object extends beyond the image boundary | IsTruncated |
| is_group_of | BOOLEAN | No | Whether the box encloses a group of similar objects | IsGroupOf |
| is_depiction | BOOLEAN | No | Whether the object is a drawing/painting rather than a real object | IsDepiction |
| is_inside | BOOLEAN | No | Whether the object is seen through a window, screen, etc. | IsInside |

---

### masks

- **Source CSV:** `validation-annotations-object-segmentation.csv`
- **Row count:** ~18,000
- **Raw table:** `raw_masks`
- **Note:** The `clicks` column is semicolon-delimited (NOT JSON). Use `split(clicks, ';')` and `cardinality()` to parse -- do NOT use `json_extract()`.

| Column | Type | Nullable | Description | Source CSV Column |
|--------|------|----------|-------------|-------------------|
| mask_path | VARCHAR | No | Path to the segmentation mask PNG file | MaskPath |
| image_id | VARCHAR | No | References `images.image_id` | ImageID |
| label_name | VARCHAR | No | References `class_descriptions.label_name` (MID) | LabelName |
| box_id | VARCHAR | Yes | Identifier linking to a bounding box annotation | BoxID |
| box_x_min | DOUBLE | Yes | Left edge of the mask's bounding box (normalized 0.0-1.0) | BoxXMin |
| box_x_max | DOUBLE | Yes | Right edge of the mask's bounding box (normalized 0.0-1.0) | BoxXMax |
| box_y_min | DOUBLE | Yes | Top edge of the mask's bounding box (normalized 0.0-1.0) | BoxYMin |
| box_y_max | DOUBLE | Yes | Bottom edge of the mask's bounding box (normalized 0.0-1.0) | BoxYMax |
| predicted_iou | DOUBLE | Yes | Predicted intersection-over-union quality score (0.0-1.0) | PredictedIoU |
| clicks | VARCHAR | Yes | Semicolon-delimited annotation click coordinates | Clicks |

---

### relationships

- **Source CSV:** `oidv6-validation-annotations-vrd.csv`
- **Row count:** ~26,000
- **Raw table:** `raw_relationships`
- **Note:** Contains two sets of coordinates for subject and object bounding boxes. All coordinates are normalized 0.0-1.0.

| Column | Type | Nullable | Description | Source CSV Column |
|--------|------|----------|-------------|-------------------|
| image_id | VARCHAR | No | References `images.image_id` | ImageID |
| label_name_1 | VARCHAR | No | MID of the subject entity | LabelName1 |
| label_name_2 | VARCHAR | No | MID of the object entity | LabelName2 |
| x_min_1 | DOUBLE | No | Subject bounding box left edge (normalized 0.0-1.0) | XMin1 |
| x_max_1 | DOUBLE | No | Subject bounding box right edge (normalized 0.0-1.0) | XMax1 |
| y_min_1 | DOUBLE | No | Subject bounding box top edge (normalized 0.0-1.0) | YMin1 |
| y_max_1 | DOUBLE | No | Subject bounding box bottom edge (normalized 0.0-1.0) | YMax1 |
| x_min_2 | DOUBLE | No | Object bounding box left edge (normalized 0.0-1.0) | XMin2 |
| x_max_2 | DOUBLE | No | Object bounding box right edge (normalized 0.0-1.0) | XMax2 |
| y_min_2 | DOUBLE | No | Object bounding box top edge (normalized 0.0-1.0) | YMin2 |
| y_max_2 | DOUBLE | No | Object bounding box bottom edge (normalized 0.0-1.0) | YMax2 |
| relationship_label | VARCHAR | No | Relationship type (e.g., `at`, `on`, `holds`, `under`) | RelationshipLabel |

---

### label_hierarchy

- **Source:** `label_hierarchy.csv` (produced by `flatten-hierarchy.sh` from `bbox_labels_600_hierarchy.json`)
- **Row count:** ~600
- **Raw table:** `raw_label_hierarchy`

| Column | Type | Nullable | Description | Source CSV Column |
|--------|------|----------|-------------|-------------------|
| parent_mid | VARCHAR | No | Parent class MID (references `class_descriptions.label_name`) | parent_mid |
| child_mid | VARCHAR | No | Child class MID (references `class_descriptions.label_name`) | child_mid |

---

## Views

### labeled_images

- **SQL file:** `queries/views/01-labeled-images.sql`
- **Joins:** `labels` + `images` (on `image_id`) + `class_descriptions` (on `label_name`)
- **Purpose:** Enriches labels with image metadata and human-readable class names. Includes both human and machine labels (filter via `source` column).

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| image_id | VARCHAR | labels.image_id | Image identifier |
| original_url | VARCHAR | images.original_url | Original Flickr image URL |
| original_landing_url | VARCHAR | images.original_landing_url | Flickr page URL |
| license | VARCHAR | images.license | Creative Commons license URL |
| author | VARCHAR | images.author | Author display name |
| title | VARCHAR | images.title | Image title |
| original_size | INT | images.original_size | Image file size in bytes |
| thumbnail_300k_url | VARCHAR | images.thumbnail_300k_url | Thumbnail URL |
| rotation | DOUBLE | images.rotation | EXIF rotation angle |
| source | VARCHAR | labels.source | Annotation source (`verification` or `machine`) |
| label_name | VARCHAR | labels.label_name | Class MID |
| display_name | VARCHAR | class_descriptions.display_name | Human-readable class name |
| confidence | DOUBLE | labels.confidence | Confidence score (0.0-1.0) |

---

### labeled_boxes

- **SQL file:** `queries/views/02-labeled-boxes.sql`
- **Joins:** `bounding_boxes` + `images` (on `image_id`) + `class_descriptions` (on `label_name`)
- **Purpose:** Enriches bounding boxes with image metadata, class names, and computed geometry columns.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| image_id | VARCHAR | bounding_boxes.image_id | Image identifier |
| original_url | VARCHAR | images.original_url | Original Flickr image URL |
| original_landing_url | VARCHAR | images.original_landing_url | Flickr page URL |
| license | VARCHAR | images.license | Creative Commons license URL |
| author | VARCHAR | images.author | Author display name |
| original_size | INT | images.original_size | Image file size in bytes |
| thumbnail_300k_url | VARCHAR | images.thumbnail_300k_url | Thumbnail URL |
| source | VARCHAR | bounding_boxes.source | Annotation source |
| label_name | VARCHAR | bounding_boxes.label_name | Class MID |
| display_name | VARCHAR | class_descriptions.display_name | Human-readable class name |
| confidence | DOUBLE | bounding_boxes.confidence | Confidence score |
| x_min | DOUBLE | bounding_boxes.x_min | Left edge (normalized) |
| x_max | DOUBLE | bounding_boxes.x_max | Right edge (normalized) |
| y_min | DOUBLE | bounding_boxes.y_min | Top edge (normalized) |
| y_max | DOUBLE | bounding_boxes.y_max | Bottom edge (normalized) |
| is_occluded | BOOLEAN | bounding_boxes.is_occluded | Object partially hidden |
| is_truncated | BOOLEAN | bounding_boxes.is_truncated | Object extends beyond image |
| is_group_of | BOOLEAN | bounding_boxes.is_group_of | Box encloses group of objects |
| is_depiction | BOOLEAN | bounding_boxes.is_depiction | Object is a depiction |
| is_inside | BOOLEAN | bounding_boxes.is_inside | Object seen through window/screen |
| box_area | DOUBLE | Computed | `(x_max - x_min) * (y_max - y_min)` -- normalized area |
| box_width | DOUBLE | Computed | `(x_max - x_min)` -- normalized width |
| box_height | DOUBLE | Computed | `(y_max - y_min)` -- normalized height |
| box_center_x | DOUBLE | Computed | `(x_min + x_max) / 2.0` -- center X coordinate |
| box_center_y | DOUBLE | Computed | `(y_min + y_max) / 2.0` -- center Y coordinate |
| aspect_ratio | DOUBLE | Computed | `box_width / box_height` (NULL if height is 0) |

---

### labeled_masks

- **SQL file:** `queries/views/03-labeled-masks.sql`
- **Joins:** `masks` + `images` (on `image_id`) + `class_descriptions` (on `label_name`)
- **Purpose:** Enriches masks with image metadata, class names, computed box geometry, and click count from the semicolon-delimited clicks column.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| image_id | VARCHAR | masks.image_id | Image identifier |
| original_url | VARCHAR | images.original_url | Original Flickr image URL |
| original_landing_url | VARCHAR | images.original_landing_url | Flickr page URL |
| license | VARCHAR | images.license | Creative Commons license URL |
| author | VARCHAR | images.author | Author display name |
| original_size | INT | images.original_size | Image file size in bytes |
| thumbnail_300k_url | VARCHAR | images.thumbnail_300k_url | Thumbnail URL |
| label_name | VARCHAR | masks.label_name | Class MID |
| display_name | VARCHAR | class_descriptions.display_name | Human-readable class name |
| mask_path | VARCHAR | masks.mask_path | Path to segmentation mask PNG |
| box_id | VARCHAR | masks.box_id | Linked bounding box identifier |
| box_x_min | DOUBLE | masks.box_x_min | Mask bounding box left edge |
| box_x_max | DOUBLE | masks.box_x_max | Mask bounding box right edge |
| box_y_min | DOUBLE | masks.box_y_min | Mask bounding box top edge |
| box_y_max | DOUBLE | masks.box_y_max | Mask bounding box bottom edge |
| predicted_iou | DOUBLE | masks.predicted_iou | Predicted IoU quality score |
| clicks | VARCHAR | masks.clicks | Raw semicolon-delimited click data |
| box_area | DOUBLE | Computed | `(box_x_max - box_x_min) * (box_y_max - box_y_min)` |
| box_width | DOUBLE | Computed | `(box_x_max - box_x_min)` |
| box_height | DOUBLE | Computed | `(box_y_max - box_y_min)` |
| box_center_x | DOUBLE | Computed | `(box_x_min + box_x_max) / 2.0` |
| box_center_y | DOUBLE | Computed | `(box_y_min + box_y_max) / 2.0` |
| aspect_ratio | DOUBLE | Computed | `box_width / box_height` (NULL if height is 0) |
| click_count | INTEGER | Computed | `cardinality(split(clicks, ';'))` -- 0 if clicks is NULL or empty |

---

### labeled_relationships

- **SQL file:** `queries/views/04-labeled-relationships.sql`
- **Joins:** `relationships` + `images` (on `image_id`) + `class_descriptions` as `cd1` (on `label_name_1`) + `class_descriptions` as `cd2` (on `label_name_2`)
- **Purpose:** Enriches relationships with image metadata and resolves both subject and object MIDs to human-readable display names.
- **Note:** Uses INNER JOIN, which drops ~3.3% of rows (~886) where label MIDs are not found in `class_descriptions`.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| image_id | VARCHAR | relationships.image_id | Image identifier |
| original_url | VARCHAR | images.original_url | Original Flickr image URL |
| original_landing_url | VARCHAR | images.original_landing_url | Flickr page URL |
| license | VARCHAR | images.license | Creative Commons license URL |
| author | VARCHAR | images.author | Author display name |
| original_size | INT | images.original_size | Image file size in bytes |
| thumbnail_300k_url | VARCHAR | images.thumbnail_300k_url | Thumbnail URL |
| label_name_1 | VARCHAR | relationships.label_name_1 | Subject entity MID |
| display_name_1 | VARCHAR | cd1.display_name | Subject entity human-readable name |
| label_name_2 | VARCHAR | relationships.label_name_2 | Object entity MID |
| display_name_2 | VARCHAR | cd2.display_name | Object entity human-readable name |
| relationship_label | VARCHAR | relationships.relationship_label | Relationship type (e.g., `at`, `on`, `holds`) |
| x_min_1 | DOUBLE | relationships.x_min_1 | Subject bounding box left edge |
| x_max_1 | DOUBLE | relationships.x_max_1 | Subject bounding box right edge |
| y_min_1 | DOUBLE | relationships.y_min_1 | Subject bounding box top edge |
| y_max_1 | DOUBLE | relationships.y_max_1 | Subject bounding box bottom edge |
| x_min_2 | DOUBLE | relationships.x_min_2 | Object bounding box left edge |
| x_max_2 | DOUBLE | relationships.x_max_2 | Object bounding box right edge |
| y_min_2 | DOUBLE | relationships.y_min_2 | Object bounding box top edge |
| y_max_2 | DOUBLE | relationships.y_max_2 | Object bounding box bottom edge |

---

## Type Transformations

Summary of type conversions applied when creating Iceberg tables from raw external tables:

| Raw CSV Type | Iceberg Type | Transformation | Columns |
|-------------|-------------|----------------|---------|
| STRING | INT | `CAST(col AS INT)` with NULL for empty | `original_size` |
| STRING | DOUBLE | `CAST(col AS DOUBLE)` | `rotation`, `confidence`, `x_min`, `x_max`, `y_min`, `y_max`, `predicted_iou`, `box_x_min`, `box_x_max`, `box_y_min`, `box_y_max`, coordinate columns in relationships |
| STRING | DOUBLE | `CAST(col AS DOUBLE)` with NULL for empty | `rotation` |
| STRING `'0'`/`'1'` | BOOLEAN | `CASE WHEN col = '1' THEN true ELSE false END` | `is_occluded`, `is_truncated`, `is_group_of`, `is_depiction`, `is_inside` |
| STRING | VARCHAR | Kept as-is (no transformation) | `image_id`, `label_name`, `display_name`, `source`, `mask_path`, `clicks`, `box_id`, `original_url`, `original_md5`, `relationship_label`, etc. |
