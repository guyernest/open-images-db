-- 02-labeled-boxes.sql
-- View: labeled_boxes
-- Joins: bounding_boxes + images + class_descriptions
-- Includes computed geometry columns
-- Requirement: VIEW-02

CREATE OR REPLACE VIEW __DATABASE__.labeled_boxes AS
SELECT
  bb.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.original_size,
  i.thumbnail_300k_url,
  bb.source,
  bb.label_name,
  cd.display_name,
  bb.confidence,
  bb.x_min,
  bb.x_max,
  bb.y_min,
  bb.y_max,
  bb.is_occluded,
  bb.is_truncated,
  bb.is_group_of,
  bb.is_depiction,
  bb.is_inside,
  -- Computed geometry (normalized coordinates, 0.0-1.0 range)
  (bb.x_max - bb.x_min) * (bb.y_max - bb.y_min) AS box_area,
  (bb.x_max - bb.x_min)                          AS box_width,
  (bb.y_max - bb.y_min)                          AS box_height,
  (bb.x_min + bb.x_max) / 2.0                    AS box_center_x,
  (bb.y_min + bb.y_max) / 2.0                    AS box_center_y,
  CASE WHEN (bb.y_max - bb.y_min) > 0
    THEN (bb.x_max - bb.x_min) / (bb.y_max - bb.y_min)
    ELSE NULL
  END                                             AS aspect_ratio
FROM __DATABASE__.bounding_boxes bb
JOIN __DATABASE__.images i
  ON bb.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd
  ON bb.label_name = cd.label_name;
