-- 09-class-hierarchy-resolved.sql
-- View: class_hierarchy_resolved
-- Pre-joined hierarchy edges with display names (~600 rows)
-- Eliminates repeated label_hierarchy + class_descriptions double-join
-- in find_images, explore_category, resolve_labels, and get_image_details

CREATE OR REPLACE VIEW __DATABASE__.class_hierarchy_resolved AS
SELECT
  p.display_name AS parent_name,
  p.label_name   AS parent_id,
  c.display_name AS child_name,
  c.label_name   AS child_id
FROM __DATABASE__.label_hierarchy lh
JOIN __DATABASE__.class_descriptions p
  ON lh.parent_mid = p.label_name
JOIN __DATABASE__.class_descriptions c
  ON lh.child_mid = c.label_name;
