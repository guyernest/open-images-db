-- 04-bounding-boxes.sql
-- Table: bounding_boxes (13 columns from 21 raw columns; x_click columns excluded)
-- Source: validation-annotations-bbox.csv
-- Requirement: TBL-04

DROP TABLE IF EXISTS __DATABASE__.bounding_boxes;

DROP TABLE IF EXISTS __DATABASE__.raw_bounding_boxes;

CREATE EXTERNAL TABLE __DATABASE__.raw_bounding_boxes (
  image_id      STRING,
  source        STRING,
  label_name    STRING,
  confidence    STRING,
  x_min         STRING,
  x_max         STRING,
  y_min         STRING,
  y_max         STRING,
  is_occluded   STRING,
  is_truncated  STRING,
  is_group_of   STRING,
  is_depiction  STRING,
  is_inside     STRING,
  x_click_1x    STRING,
  x_click_2x    STRING,
  x_click_3x    STRING,
  x_click_4x    STRING,
  x_click_1y    STRING,
  x_click_2y    STRING,
  x_click_3y    STRING,
  x_click_4y    STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/bounding_boxes/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE __DATABASE__.bounding_boxes
WITH (
  table_type     = 'ICEBERG',
  format         = 'PARQUET',
  write_compression = 'SNAPPY',
  location       = 's3://__BUCKET__/warehouse/bounding_boxes/'
) AS
SELECT
  image_id,
  source,
  label_name,
  CAST(confidence AS DOUBLE)  AS confidence,
  CAST(x_min AS DOUBLE)       AS x_min,
  CAST(x_max AS DOUBLE)       AS x_max,
  CAST(y_min AS DOUBLE)       AS y_min,
  CAST(y_max AS DOUBLE)       AS y_max,
  CASE WHEN is_occluded  = '1' THEN true ELSE false END AS is_occluded,
  CASE WHEN is_truncated = '1' THEN true ELSE false END AS is_truncated,
  CASE WHEN is_group_of  = '1' THEN true ELSE false END AS is_group_of,
  CASE WHEN is_depiction = '1' THEN true ELSE false END AS is_depiction,
  CASE WHEN is_inside    = '1' THEN true ELSE false END AS is_inside
FROM __DATABASE__.raw_bounding_boxes;
