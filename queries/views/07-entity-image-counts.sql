-- 07-entity-image-counts.sql
-- View: entity_image_counts
-- Pre-computed image counts per entity (~20K rows)
-- Uses labels_top5 for interactive performance (45M vs 229M row scan)
-- Eliminates repeated COUNT(DISTINCT image_id) subqueries in resolve_labels and find_images

CREATE OR REPLACE VIEW __DATABASE__.entity_image_counts AS
SELECT
  l.label_name,
  cd.display_name,
  COUNT(DISTINCT l.image_id) AS image_count
FROM __DATABASE__.labels_top5 l
JOIN __DATABASE__.class_descriptions cd
  ON l.label_name = cd.label_name
GROUP BY l.label_name, cd.display_name;
