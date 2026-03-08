-- 06-hierarchy-relationships.sql
-- View: hierarchy_relationships
-- Expands relationships through class hierarchy so ancestor queries work
-- e.g., "Person on Horse" finds "Man on Horse", "Woman on Horse" etc.
-- Includes all labeled_relationships columns plus ancestor_name_1, ancestor_name_2, depth_1, depth_2

CREATE OR REPLACE VIEW __DATABASE__.hierarchy_relationships AS
WITH RECURSIVE
-- Seed only from MIDs that actually appear in relationships (keeps CTE manageable)
rel_mids(mid) AS (
  SELECT DISTINCT label_name_1 AS mid FROM __DATABASE__.relationships
  UNION
  SELECT DISTINCT label_name_2 AS mid FROM __DATABASE__.relationships
),
-- Walk UP from each relationship MID to all its ancestors
ancestors(mid, ancestor_mid, depth) AS (
  -- Base: every MID is its own ancestor at depth 0
  SELECT mid, mid AS ancestor_mid, 0 AS depth
  FROM rel_mids

  UNION ALL

  -- Recursive: walk up via label_hierarchy (child -> parent)
  SELECT a.mid, h.parent_mid AS ancestor_mid, a.depth + 1 AS depth
  FROM ancestors a
  JOIN __DATABASE__.label_hierarchy h ON a.ancestor_mid = h.child_mid
  WHERE a.depth < 20
)
SELECT
  r.image_id,
  i.original_url,
  i.original_landing_url,
  i.license,
  i.author,
  i.original_size,
  i.thumbnail_300k_url,
  r.label_name_1,
  cd1.display_name AS display_name_1,
  r.label_name_2,
  cd2.display_name AS display_name_2,
  r.relationship_label,
  r.x_min_1, r.x_max_1, r.y_min_1, r.y_max_1,
  r.x_min_2, r.x_max_2, r.y_min_2, r.y_max_2,
  acd1.display_name AS ancestor_name_1,
  acd2.display_name AS ancestor_name_2,
  a1.depth AS depth_1,
  a2.depth AS depth_2
FROM __DATABASE__.relationships r
JOIN __DATABASE__.images i ON r.image_id = i.image_id
JOIN __DATABASE__.class_descriptions cd1 ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2 ON r.label_name_2 = cd2.label_name
JOIN ancestors a1 ON r.label_name_1 = a1.mid
JOIN ancestors a2 ON r.label_name_2 = a2.mid
JOIN __DATABASE__.class_descriptions acd1 ON a1.ancestor_mid = acd1.label_name
JOIN __DATABASE__.class_descriptions acd2 ON a2.ancestor_mid = acd2.label_name;
