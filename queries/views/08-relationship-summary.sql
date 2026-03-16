-- 08-relationship-summary.sql
-- View: relationship_summary
-- Reads from materialized table relationship_summary_mat (~15K rows)
-- Run create-tables to rebuild the materialized table if source data changes

CREATE OR REPLACE VIEW __DATABASE__.relationship_summary AS
SELECT subject_name, subject_id, predicate, object_name, object_id, occurrence_count
FROM __DATABASE__.relationship_summary_mat;
