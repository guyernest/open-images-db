-- 07-label-hierarchy.sql
-- Table: label_hierarchy (2 columns, from flattened CSV)
-- Source: label_hierarchy.csv (produced by flatten-hierarchy.sh)
-- Requirement: TBL-07

DROP TABLE IF EXISTS open_images.label_hierarchy;

DROP TABLE IF EXISTS open_images.raw_label_hierarchy;

CREATE EXTERNAL TABLE open_images.raw_label_hierarchy (
  parent_mid  STRING,
  child_mid   STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/label_hierarchy/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE open_images.label_hierarchy
WITH (
  table_type     = 'ICEBERG',
  format         = 'PARQUET',
  write_compression = 'SNAPPY',
  location       = 's3://__BUCKET__/warehouse/label_hierarchy/'
) AS
SELECT
  parent_mid,
  child_mid
FROM open_images.raw_label_hierarchy;
