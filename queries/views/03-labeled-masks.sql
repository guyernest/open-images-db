-- 03-labeled-masks.sql
-- View: labeled_masks
-- Joins: masks + images + class_descriptions
-- Includes mask enrichment: computed geometry from box coords + click count
-- Requirements: VIEW-03, MASK-01

CREATE OR REPLACE VIEW __DATABASE__.labeled_masks AS
SELECT
  m.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.original_size,
  i.thumbnail_300k_url,
  m.label_name,
  cd.display_name,
  m.mask_path,
  m.box_id,
  m.box_x_min,
  m.box_x_max,
  m.box_y_min,
  m.box_y_max,
  m.predicted_iou,
  m.clicks,
  -- Computed mask geometry from bounding box coordinates
  (m.box_x_max - m.box_x_min) * (m.box_y_max - m.box_y_min) AS box_area,
  (m.box_x_max - m.box_x_min)                                AS box_width,
  (m.box_y_max - m.box_y_min)                                AS box_height,
  (m.box_x_min + m.box_x_max) / 2.0                          AS box_center_x,
  (m.box_y_min + m.box_y_max) / 2.0                          AS box_center_y,
  -- Click count from semicolon-delimited clicks column
  CASE
    WHEN m.clicks IS NULL OR m.clicks = '' THEN 0
    ELSE cardinality(split(m.clicks, ';'))
  END AS click_count
FROM __DATABASE__.masks m
JOIN __DATABASE__.images i
  ON m.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd
  ON m.label_name = cd.label_name;
