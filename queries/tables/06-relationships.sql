-- 06-relationships.sql
-- Table: relationships (12 columns)
-- Source: oidv6-validation-annotations-vrd.csv
-- Requirement: TBL-06

DROP TABLE IF EXISTS __DATABASE__.relationships;

DROP TABLE IF EXISTS __DATABASE__.raw_relationships;

CREATE EXTERNAL TABLE __DATABASE__.raw_relationships (
  image_id           STRING,
  label_name_1       STRING,
  label_name_2       STRING,
  x_min_1            STRING,
  x_max_1            STRING,
  y_min_1            STRING,
  y_max_1            STRING,
  x_min_2            STRING,
  x_max_2            STRING,
  y_min_2            STRING,
  y_max_2            STRING,
  relationship_label STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/relationships/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE __DATABASE__.relationships
WITH (
  table_type     = 'ICEBERG',
  is_external    = false,
  format         = 'PARQUET',
  write_compression = 'SNAPPY',
  location       = 's3://__BUCKET__/warehouse/relationships/'
) AS
SELECT
  image_id,
  label_name_1,
  label_name_2,
  CAST(x_min_1 AS DOUBLE) AS x_min_1,
  CAST(x_max_1 AS DOUBLE) AS x_max_1,
  CAST(y_min_1 AS DOUBLE) AS y_min_1,
  CAST(y_max_1 AS DOUBLE) AS y_max_1,
  CAST(x_min_2 AS DOUBLE) AS x_min_2,
  CAST(x_max_2 AS DOUBLE) AS x_max_2,
  CAST(y_min_2 AS DOUBLE) AS y_min_2,
  CAST(y_max_2 AS DOUBLE) AS y_max_2,
  relationship_label
FROM __DATABASE__.raw_relationships;
