# Example SQL Queries

These queries run against the `open_images` database via the `open-images` Athena workgroup. All table and view references use the fully-qualified `open_images.tablename` format.

---

## Single-Table Queries

### 1. List images with metadata

Browse images in the dataset with key metadata fields.

```sql
SELECT
  image_id,
  original_url,
  license,
  author,
  original_size,
  rotation
FROM open_images.images
LIMIT 20;
```

### 2. Look up a class name by MID

Find the human-readable display name for a machine-readable label identifier.

```sql
SELECT
  label_name,
  display_name
FROM open_images.class_descriptions
WHERE label_name = '/m/0bt9lr';
```

### 3. Count labels by source type

Compare the volume of human-verified vs machine-generated labels.

```sql
SELECT
  source,
  COUNT(*) AS label_count
FROM open_images.labels
GROUP BY source
ORDER BY label_count DESC;
```

### 4. Find large bounding boxes

Identify bounding boxes that cover more than 50% of the image area. Coordinates are normalized to 0.0-1.0, so area is computed as `(x_max - x_min) * (y_max - y_min)`.

```sql
SELECT
  image_id,
  label_name,
  x_min,
  x_max,
  y_min,
  y_max,
  (x_max - x_min) * (y_max - y_min) AS box_area
FROM open_images.bounding_boxes
WHERE (x_max - x_min) * (y_max - y_min) > 0.5
ORDER BY box_area DESC
LIMIT 20;
```

### 5. List masks with high predicted IoU

Find segmentation masks with high quality scores.

```sql
SELECT
  image_id,
  label_name,
  mask_path,
  predicted_iou
FROM open_images.masks
WHERE predicted_iou > 0.9
ORDER BY predicted_iou DESC
LIMIT 20;
```

### 6. Count visual relationships by type

See which relationship types are most common in the dataset.

```sql
SELECT
  relationship_label,
  COUNT(*) AS relationship_count
FROM open_images.relationships
GROUP BY relationship_label
ORDER BY relationship_count DESC;
```

### 7. Find child classes of a parent in the label hierarchy

Look up the class hierarchy to find all child classes of a given parent, resolving MIDs to human-readable names. This joins `label_hierarchy` with `class_descriptions` twice: once for the parent and once for the child.

```sql
SELECT
  lh.parent_mid,
  cd_parent.display_name AS parent_name,
  lh.child_mid,
  cd_child.display_name AS child_name
FROM open_images.label_hierarchy lh
JOIN open_images.class_descriptions cd_parent
  ON lh.parent_mid = cd_parent.label_name
JOIN open_images.class_descriptions cd_child
  ON lh.child_mid = cd_child.label_name
WHERE cd_parent.display_name = 'Animal'
ORDER BY child_name;
```

---

## Cross-Table Joins

### 8. Find images labeled "Dog" with bounding boxes

Use the `labeled_boxes` convenience view to find all bounding box annotations for dogs, including computed geometry.

```sql
SELECT
  image_id,
  original_url,
  display_name,
  x_min,
  y_min,
  x_max,
  y_max,
  box_area,
  aspect_ratio,
  is_occluded,
  is_truncated
FROM open_images.labeled_boxes
WHERE display_name = 'Dog'
ORDER BY box_area DESC
LIMIT 20;
```

### 9. Images with both labels and segmentation masks

Find images that have both image-level labels and segmentation masks for the same class, joining through `class_descriptions` for human-readable names.

```sql
SELECT DISTINCT
  l.image_id,
  cd.display_name,
  l.source AS label_source,
  l.confidence AS label_confidence,
  m.mask_path,
  m.predicted_iou
FROM open_images.labels l
JOIN open_images.masks m
  ON l.image_id = m.image_id
  AND l.label_name = m.label_name
JOIN open_images.class_descriptions cd
  ON l.label_name = cd.label_name
WHERE l.confidence > 0.8
  AND m.predicted_iou > 0.7
LIMIT 20;
```

### 10. Visual relationships with human-readable labels

Use the `labeled_relationships` convenience view to browse relationships with resolved display names for both subject and object entities.

```sql
SELECT
  image_id,
  display_name_1 AS subject,
  relationship_label,
  display_name_2 AS object,
  original_url
FROM open_images.labeled_relationships
WHERE relationship_label = 'on'
LIMIT 20;
```

---

## String Field Parsing

### 11. Parse semicolon-delimited clicks column

The `clicks` column in the `masks` table contains semicolon-delimited coordinate data. Use `split()` and `cardinality()` to parse it -- do NOT use `json_extract()`.

```sql
SELECT
  image_id,
  label_name,
  mask_path,
  clicks,
  cardinality(split(clicks, ';')) AS click_count,
  split(clicks, ';') AS click_array
FROM open_images.masks
WHERE clicks IS NOT NULL
  AND clicks <> ''
LIMIT 10;
```

### 12. Count clicks per mask using the labeled_masks view

The `labeled_masks` view pre-computes `click_count` via `cardinality(split(clicks, ';'))`. Use it to find masks with the most annotation clicks.

```sql
SELECT
  image_id,
  display_name,
  mask_path,
  predicted_iou,
  click_count
FROM open_images.labeled_masks
WHERE click_count > 0
ORDER BY click_count DESC
LIMIT 20;
```
