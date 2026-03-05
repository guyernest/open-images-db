-- 02-class-descriptions.sql
-- Table: class_descriptions (2 columns)
-- Source: oidv7-class-descriptions.csv
-- Requirement: TBL-02
-- Note: Assuming CSV has a header row (skip.header.line.count=1).
--       If the first data row is missing after creation, set to '0' and re-run.

DROP TABLE IF EXISTS open_images.class_descriptions;

DROP TABLE IF EXISTS open_images.raw_class_descriptions;

CREATE EXTERNAL TABLE open_images.raw_class_descriptions (
  label_name    STRING,
  display_name  STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/class_descriptions/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE open_images.class_descriptions
WITH (
  table_type     = 'ICEBERG',
  format         = 'PARQUET',
  write_compression = 'SNAPPY',
  location       = 's3://__BUCKET__/warehouse/class_descriptions/'
) AS
SELECT
  label_name,
  display_name
FROM open_images.raw_class_descriptions;
