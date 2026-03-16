-- 08b-relationship-summary-mat.sql
-- Table: relationship_summary_mat (~15K rows, <1 MB)
-- Pre-aggregated relationship triples with resolved display names
-- Replaces runtime triple-join + GROUP BY in relationship_summary view

DROP TABLE IF EXISTS __DATABASE__.relationship_summary_mat;

CREATE TABLE __DATABASE__.relationship_summary_mat
WITH (
  table_type        = 'ICEBERG',
  is_external       = false,
  format            = 'PARQUET',
  write_compression = 'SNAPPY',
  location          = 's3://__BUCKET__/warehouse/relationship_summary_mat/'
) AS
SELECT
  cd1.display_name AS subject_name,
  r.label_name_1   AS subject_id,
  r.relationship_label AS predicate,
  cd2.display_name AS object_name,
  r.label_name_2   AS object_id,
  COUNT(*)          AS occurrence_count
FROM __DATABASE__.relationships r
JOIN __DATABASE__.class_descriptions cd1 ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2 ON r.label_name_2 = cd2.label_name
GROUP BY
  cd1.display_name, r.label_name_1,
  r.relationship_label,
  cd2.display_name, r.label_name_2;
