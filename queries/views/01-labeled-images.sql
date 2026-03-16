-- 01-labeled-images.sql
-- View: labeled_images
-- Joins: labels_top5 + images + class_descriptions
-- Uses top 5 labels per image for interactive performance (45M vs 229M rows)
-- Requirement: VIEW-01

CREATE OR REPLACE VIEW __DATABASE__.labeled_images AS
SELECT
  l.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.title,
  i.original_size,
  i.thumbnail_300k_url,
  i.cvdf_url,
  i.rotation,
  l.source,
  l.label_name,
  cd.display_name,
  l.confidence
FROM __DATABASE__.labels_top5 l
JOIN __DATABASE__.images i
  ON l.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd
  ON l.label_name = cd.label_name;
