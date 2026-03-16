-- 08a-entity-image-counts-mat.sql
-- Table: entity_image_counts_mat (~20K rows, <1 MB)
-- Pre-computed image count per class from labels_top5
-- Replaces runtime aggregation in entity_image_counts view

DROP TABLE IF EXISTS __DATABASE__.entity_image_counts_mat;

CREATE TABLE __DATABASE__.entity_image_counts_mat
WITH (
  table_type        = 'ICEBERG',
  is_external       = false,
  format            = 'PARQUET',
  write_compression = 'SNAPPY',
  location          = 's3://__BUCKET__/warehouse/entity_image_counts_mat/'
) AS
SELECT
  l.label_name,
  cd.display_name,
  COUNT(DISTINCT l.image_id) AS image_count
FROM __DATABASE__.labels_top5 l
JOIN __DATABASE__.class_descriptions cd ON l.label_name = cd.label_name
GROUP BY l.label_name, cd.display_name;
