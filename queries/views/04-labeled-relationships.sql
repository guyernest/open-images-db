-- 04-labeled-relationships.sql
-- View: labeled_relationships
-- Joins: relationships + images + class_descriptions (twice, for both labels)
-- Requirement: VIEW-04

CREATE OR REPLACE VIEW __DATABASE__.labeled_relationships AS
SELECT
  r.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.original_size,
  i.thumbnail_300k_url,
  i.cvdf_url,
  r.label_name_1,
  cd1.display_name AS display_name_1,
  r.label_name_2,
  cd2.display_name AS display_name_2,
  r.relationship_label,
  r.x_min_1, r.x_max_1, r.y_min_1, r.y_max_1,
  r.x_min_2, r.x_max_2, r.y_min_2, r.y_max_2
FROM __DATABASE__.relationships r
JOIN __DATABASE__.images i
  ON r.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd1
  ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2
  ON r.label_name_2 = cd2.label_name;
