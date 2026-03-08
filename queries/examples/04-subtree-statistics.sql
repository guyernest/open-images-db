-- 04-subtree-statistics.sql
-- Count images and relationships per hierarchy branch.
--
-- Uses both class_hierarchy and hierarchy_relationships views to aggregate
-- statistics across the class taxonomy.

-- Query 1: Relationship count per top-level ancestor class (as subject)
--
-- Shows which high-level classes participate most in relationships.
-- depth_1 > 0 excludes self-matches (where the class IS its own ancestor).
--
-- Expected output (top rows):
--   class_name | relationship_count
--   Person     | ...
--   Clothing   | ...
--   Animal     | ...
--   ...

SELECT ancestor_name_1 AS class_name, COUNT(*) AS relationship_count
FROM __DATABASE__.hierarchy_relationships
WHERE depth_1 > 0
GROUP BY ancestor_name_1
ORDER BY relationship_count DESC
LIMIT 15;

-- Query 2: Classes with most direct children
--
-- Uses class_hierarchy to find which parent classes have the most
-- immediate subclasses (subcategory or part edges).
--
-- Expected output (top rows):
--   parent_name | child_count
--   Entity      | ...  (many direct children under root)
--   Food        | ...
--   Animal      | ...
--   ...

SELECT parent_name, COUNT(*) AS child_count
FROM __DATABASE__.class_hierarchy
WHERE parent_name IS NOT NULL
GROUP BY parent_name
ORDER BY child_count DESC
LIMIT 15;
