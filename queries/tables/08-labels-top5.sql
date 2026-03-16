-- 08-labels-top5.sql
-- Table: labels_top5 (4 columns, same schema as labels)
-- Source: Derived from labels table — top 5 labels per image by confidence
-- Purpose: 80% row reduction (229M → ~45M) for interactive query performance
-- Note: Original labels table is kept for ad-hoc queries needing the full set

DROP TABLE IF EXISTS __DATABASE__.labels_top5;

CREATE TABLE __DATABASE__.labels_top5
WITH (
  table_type        = 'ICEBERG',
  is_external       = false,
  format            = 'PARQUET',
  write_compression = 'SNAPPY',
  location          = 's3://__BUCKET__/warehouse/labels_top5/'
) AS
WITH ranked AS (
  SELECT
    image_id,
    source,
    label_name,
    confidence,
    ROW_NUMBER() OVER (PARTITION BY image_id ORDER BY confidence DESC) AS rn
  FROM __DATABASE__.labels
)
SELECT image_id, source, label_name, confidence
FROM ranked
WHERE rn <= 5;
