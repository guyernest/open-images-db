-- 03-labels.sql
-- Table: labels (4 columns, combines human + machine label CSVs)
-- Source: oidv7-val-annotations-human-imagelabels.csv
--         oidv7-val-annotations-machine-imagelabels.csv
-- Requirement: TBL-03

DROP TABLE IF EXISTS open_images.labels;

DROP TABLE IF EXISTS open_images.raw_labels_human;

DROP TABLE IF EXISTS open_images.raw_labels_machine;

CREATE EXTERNAL TABLE open_images.raw_labels_human (
  image_id    STRING,
  source      STRING,
  label_name  STRING,
  confidence  STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/labels_human/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE EXTERNAL TABLE open_images.raw_labels_machine (
  image_id    STRING,
  source      STRING,
  label_name  STRING,
  confidence  STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar'     = '"',
  'escapeChar'    = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/tables/labels_machine/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE open_images.labels
WITH (
  table_type     = 'ICEBERG',
  format         = 'PARQUET',
  write_compression = 'SNAPPY',
  location       = 's3://__BUCKET__/warehouse/labels/'
) AS
SELECT
  image_id,
  source,
  label_name,
  CAST(confidence AS DOUBLE) AS confidence
FROM open_images.raw_labels_human
UNION ALL
SELECT
  image_id,
  source,
  label_name,
  CAST(confidence AS DOUBLE) AS confidence
FROM open_images.raw_labels_machine;
