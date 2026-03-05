-- 05-masks.sql
-- Table: masks (10 columns)
-- Source: validation-annotations-object-segmentation.csv
-- Requirement: TBL-05

DROP TABLE IF EXISTS open_images.masks;

DROP TABLE IF EXISTS open_images.raw_masks;

CREATE EXTERNAL TABLE open_images.raw_masks (
  mask_path      STRING,
  image_id       STRING,
  label_name     STRING,
  box_id         STRING,
  box_x_min      STRING,
  box_x_max      STRING,
  box_y_min      STRING,
  box_y_max      STRING,
  predicted_iou  STRING,
  clicks         STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/masks/'
TBLPROPERTIES ('skip.header.line.count' = '1');

-- clicks column stored as VARCHAR; future enrichment may convert to JSON
-- for json_extract queries (TBL-10)
CREATE TABLE open_images.masks
WITH (
  table_type     = 'ICEBERG',
  format         = 'PARQUET',
  write_compression = 'SNAPPY',
  location       = 's3://__BUCKET__/warehouse/masks/'
) AS
SELECT
  mask_path,
  image_id,
  label_name,
  box_id,
  CAST(box_x_min AS DOUBLE)     AS box_x_min,
  CAST(box_x_max AS DOUBLE)     AS box_x_max,
  CAST(box_y_min AS DOUBLE)     AS box_y_min,
  CAST(box_y_max AS DOUBLE)     AS box_y_max,
  CAST(predicted_iou AS DOUBLE) AS predicted_iou,
  clicks
FROM open_images.raw_masks;
