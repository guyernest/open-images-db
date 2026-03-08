-- 05-class-hierarchy.sql
-- View: class_hierarchy
-- Recursive CTE providing hierarchy navigation with depth, root path, and leaf detection
-- Columns: mid, display_name, parent_mid, parent_name, depth, edge_type, root_path, is_leaf

CREATE OR REPLACE VIEW __DATABASE__.class_hierarchy AS
WITH RECURSIVE
roots(mid) AS (
  SELECT DISTINCT lh.parent_mid AS mid
  FROM __DATABASE__.label_hierarchy lh
  WHERE NOT EXISTS (
    SELECT 1 FROM __DATABASE__.label_hierarchy c WHERE c.child_mid = lh.parent_mid
  )
),
tree(mid, parent_mid, depth, edge_type, root_path) AS (
  -- Base case: root nodes (no parent edge)
  SELECT
    r.mid,
    CAST(NULL AS VARCHAR) AS parent_mid,
    0 AS depth,
    CAST(NULL AS VARCHAR) AS edge_type,
    COALESCE(cd.display_name, r.mid) AS root_path
  FROM roots r
  LEFT JOIN __DATABASE__.class_descriptions cd ON r.mid = cd.label_name

  UNION ALL

  -- Recursive: walk down from parent to child
  SELECT
    h.child_mid AS mid,
    h.parent_mid AS parent_mid,
    t.depth + 1 AS depth,
    h.edge_type AS edge_type,
    t.root_path || ' > ' || COALESCE(cd.display_name, h.child_mid) AS root_path
  FROM tree t
  JOIN __DATABASE__.label_hierarchy h ON t.mid = h.parent_mid
  LEFT JOIN __DATABASE__.class_descriptions cd ON h.child_mid = cd.label_name
  WHERE t.depth < 20
)
SELECT
  t.mid,
  COALESCE(cd.display_name, t.mid) AS display_name,
  t.parent_mid,
  COALESCE(pcd.display_name, t.parent_mid) AS parent_name,
  t.depth,
  t.edge_type,
  t.root_path,
  NOT EXISTS (
    SELECT 1 FROM __DATABASE__.label_hierarchy lh WHERE lh.parent_mid = t.mid
  ) AS is_leaf
FROM tree t
LEFT JOIN __DATABASE__.class_descriptions cd ON t.mid = cd.label_name
LEFT JOIN __DATABASE__.class_descriptions pcd ON t.parent_mid = pcd.label_name
ORDER BY t.depth, cd.display_name;
