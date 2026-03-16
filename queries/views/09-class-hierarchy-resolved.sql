-- 09-class-hierarchy-resolved.sql
-- View: class_hierarchy_resolved
-- Reads from materialized table class_hierarchy_resolved_mat (847 rows)
-- Run create-tables to rebuild the materialized table if source data changes

CREATE OR REPLACE VIEW __DATABASE__.class_hierarchy_resolved AS
SELECT parent_name, parent_id, child_name, child_id
FROM __DATABASE__.class_hierarchy_resolved_mat;
