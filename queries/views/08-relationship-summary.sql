-- 08-relationship-summary.sql
-- View: relationship_summary
-- Pre-joined and aggregated relationship triples with display names
-- Eliminates repeated triple-join + GROUP BY pattern in resolve_labels,
-- explore_category, browse_relationships, and find_images facets

CREATE OR REPLACE VIEW __DATABASE__.relationship_summary AS
SELECT
  cd1.display_name AS subject_name,
  r.label_name_1   AS subject_id,
  r.relationship_label AS predicate,
  cd2.display_name AS object_name,
  r.label_name_2   AS object_id,
  COUNT(*)          AS occurrence_count
FROM __DATABASE__.relationships r
JOIN __DATABASE__.class_descriptions cd1
  ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2
  ON r.label_name_2 = cd2.label_name
GROUP BY
  cd1.display_name, r.label_name_1,
  r.relationship_label,
  cd2.display_name, r.label_name_2;
