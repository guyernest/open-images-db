-- 08d-class-hierarchy-resolved-mat.sql
-- Table: class_hierarchy_resolved_mat (847 rows, <1 KB)
-- Pre-joined hierarchy edges with parent/child display names
-- Replaces runtime double-join in class_hierarchy_resolved view

DROP TABLE IF EXISTS __DATABASE__.class_hierarchy_resolved_mat;

CREATE TABLE __DATABASE__.class_hierarchy_resolved_mat
WITH (
  table_type        = 'ICEBERG',
  is_external       = false,
  format            = 'PARQUET',
  write_compression = 'SNAPPY',
  location          = 's3://__BUCKET__/warehouse/class_hierarchy_resolved_mat/'
) AS
SELECT parent_name, parent_id, child_name, child_id
FROM __DATABASE__.class_hierarchy_resolved;
