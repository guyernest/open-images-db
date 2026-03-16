-- 08c-label-cooccurrence-top10.sql
-- Table: label_cooccurrence_top10 (~200K rows, ~5 MB)
-- Pre-computed top-10 co-occurring labels per class
-- Eliminates the 45M x 45M self-join in resolve_labels Round 2c
-- NOTE: CTAS takes 10-20 minutes due to the self-join (one-time cost)

DROP TABLE IF EXISTS __DATABASE__.label_cooccurrence_top10;

CREATE TABLE __DATABASE__.label_cooccurrence_top10
WITH (
  table_type        = 'ICEBERG',
  is_external       = false,
  format            = 'PARQUET',
  write_compression = 'SNAPPY',
  location          = 's3://__BUCKET__/warehouse/label_cooccurrence_top10/'
) AS
WITH cooc AS (
  SELECT
    l1.label_name AS target,
    cd1.display_name AS target_name,
    cd2.display_name AS cooccurring_label,
    l2.label_name AS cooccurring_id,
    COUNT(DISTINCT l2.image_id) AS shared_image_count
  FROM __DATABASE__.labels_top5 l1
  JOIN __DATABASE__.labels_top5 l2
    ON l2.image_id = l1.image_id AND l2.label_name != l1.label_name
  JOIN __DATABASE__.class_descriptions cd1 ON l1.label_name = cd1.label_name
  JOIN __DATABASE__.class_descriptions cd2 ON l2.label_name = cd2.label_name
  GROUP BY l1.label_name, cd1.display_name, cd2.display_name, l2.label_name
),
ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY target ORDER BY shared_image_count DESC) AS rn
  FROM cooc
)
SELECT target, target_name, cooccurring_label, cooccurring_id, shared_image_count
FROM ranked
WHERE rn <= 10;
