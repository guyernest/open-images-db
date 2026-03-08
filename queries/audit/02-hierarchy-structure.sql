-- 02-hierarchy-structure.sql
-- Audit: Hierarchy root nodes, max depth, full tree structure, branch density
-- Requirement: AUDIT-02
-- Note: label_hierarchy uses MID format (parent_mid, child_mid).
--       Join to class_descriptions ON label_name (both are MID format like /m/01g317).

-- Query 1: Root nodes -- parents that never appear as children
SELECT
  h.parent_mid                AS root_mid,
  COALESCE(cd.display_name, h.parent_mid) AS root_display_name
FROM __DATABASE__.label_hierarchy h
LEFT JOIN __DATABASE__.class_descriptions cd
  ON h.parent_mid = cd.label_name
WHERE h.parent_mid NOT IN (
  SELECT child_mid FROM __DATABASE__.label_hierarchy
)
GROUP BY h.parent_mid, cd.display_name
ORDER BY root_display_name;

-- Query 2: Max depth via recursive CTE
-- Note: Athena requires column aliases on recursive CTE definitions
WITH RECURSIVE roots(mid) AS (
  SELECT DISTINCT parent_mid AS mid
  FROM __DATABASE__.label_hierarchy
  WHERE parent_mid NOT IN (
    SELECT child_mid FROM __DATABASE__.label_hierarchy
  )
),
tree(mid, depth) AS (
  SELECT mid, 0 AS depth
  FROM roots
  UNION ALL
  SELECT h.child_mid AS mid, t.depth + 1 AS depth
  FROM tree t
  JOIN __DATABASE__.label_hierarchy h
    ON t.mid = h.parent_mid
  WHERE t.depth < 20
)
SELECT MAX(depth) AS max_depth
FROM tree;

-- Query 3: Full hierarchy traversal from roots to leaves
-- Note: Athena requires column aliases on recursive CTE definitions
WITH RECURSIVE roots(mid) AS (
  SELECT DISTINCT parent_mid AS mid
  FROM __DATABASE__.label_hierarchy
  WHERE parent_mid NOT IN (
    SELECT child_mid FROM __DATABASE__.label_hierarchy
  )
),
tree(mid, parent_mid, depth) AS (
  SELECT
    mid,
    CAST(NULL AS VARCHAR) AS parent_mid,
    0 AS depth
  FROM roots
  UNION ALL
  SELECT
    h.child_mid AS mid,
    h.parent_mid AS parent_mid,
    t.depth + 1  AS depth
  FROM tree t
  JOIN __DATABASE__.label_hierarchy h
    ON t.mid = h.parent_mid
  WHERE t.depth < 20
)
SELECT
  t.mid,
  COALESCE(cd.display_name, t.mid)   AS display_name,
  t.depth,
  t.parent_mid,
  COALESCE(pcd.display_name, t.parent_mid) AS parent_display_name
FROM tree t
LEFT JOIN __DATABASE__.class_descriptions cd
  ON t.mid = cd.label_name
LEFT JOIN __DATABASE__.class_descriptions pcd
  ON t.parent_mid = pcd.label_name
ORDER BY t.depth, display_name;

-- Query 4: Branch density -- direct child count per parent node
SELECT
  h.parent_mid,
  COALESCE(cd.display_name, h.parent_mid) AS parent_name,
  COUNT(*)                                 AS child_count
FROM __DATABASE__.label_hierarchy h
LEFT JOIN __DATABASE__.class_descriptions cd
  ON h.parent_mid = cd.label_name
GROUP BY h.parent_mid, cd.display_name
ORDER BY child_count DESC;

-- Query 5: Coverage analysis -- distinct MIDs in hierarchy vs class_descriptions
SELECT
  'label_hierarchy_distinct_mids' AS metric,
  COUNT(DISTINCT mid)             AS value
FROM (
  SELECT parent_mid AS mid FROM __DATABASE__.label_hierarchy
  UNION
  SELECT child_mid AS mid FROM __DATABASE__.label_hierarchy
)
UNION ALL
SELECT
  'class_descriptions_total' AS metric,
  COUNT(*)                   AS value
FROM __DATABASE__.class_descriptions;
