-- 01-images.sql
-- Table: images (12 columns)
-- Source: validation-images-with-rotation.csv
-- Requirement: TBL-01

DROP TABLE IF EXISTS __DATABASE__.images;

DROP TABLE IF EXISTS __DATABASE__.raw_images;

CREATE EXTERNAL TABLE __DATABASE__.raw_images (
  image_id       STRING,
  subset         STRING,
  original_url   STRING,
  original_landing_url STRING,
  license        STRING,
  author_profile_url STRING,
  author         STRING,
  title          STRING,
  original_size  STRING,
  original_md5   STRING,
  thumbnail_300k_url STRING,
  rotation       STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/images/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE __DATABASE__.images
WITH (
  table_type     = 'ICEBERG',
  is_external    = false,
  format         = 'PARQUET',
  write_compression = 'SNAPPY',
  location       = 's3://__BUCKET__/warehouse/images/'
) AS
SELECT
  image_id,
  subset,
  original_url,
  original_landing_url,
  license,
  author_profile_url,
  author,
  title,
  CAST(original_size AS INT) AS original_size,
  original_md5,
  thumbnail_300k_url,
  CAST(rotation AS DOUBLE) AS rotation
FROM __DATABASE__.raw_images;
