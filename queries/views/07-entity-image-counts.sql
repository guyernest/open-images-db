-- 07-entity-image-counts.sql
-- View: entity_image_counts
-- Reads from materialized table entity_image_counts_mat (~20K rows)
-- Run create-tables to rebuild the materialized table if source data changes

CREATE OR REPLACE VIEW __DATABASE__.entity_image_counts AS
SELECT label_name, display_name, image_count
FROM __DATABASE__.entity_image_counts_mat;
