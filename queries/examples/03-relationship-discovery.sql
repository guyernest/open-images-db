-- 03-relationship-discovery.sql
-- Discover relationship types between parent classes.
--
-- Uses the hierarchy_relationships view to find what relationship types
-- exist between high-level class categories, without needing to enumerate
-- every subclass combination.

-- Query 1: What relationships exist between Person and Animal?
--
-- Expected output:
--   relationship_label | instance_count
--   interacts_with     | ...
--   on                 | ...
--   ride               | ...
--   ...
-- (all relationship types where any Person subclass relates to any Animal subclass)

SELECT relationship_label, COUNT(*) AS instance_count
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Person'
  AND ancestor_name_2 = 'Animal'
GROUP BY relationship_label
ORDER BY instance_count DESC;

-- Query 2: Top entity pairs by relationship count (using depth-1 ancestor classes)
--
-- Shows relationships at the "parent class" level of abstraction.
-- depth_1 = 1 and depth_2 = 1 selects the immediate parent of each
-- concrete class, giving a mid-level grouping.
--
-- Expected output (top rows):
--   ancestor_name_1 | ancestor_name_2 | relationship_label | instance_count
--   Person          | Clothing        | wears              | ...
--   Person          | Animal          | interacts_with     | ...
--   ...

SELECT ancestor_name_1, ancestor_name_2, relationship_label,
       COUNT(*) AS instance_count
FROM __DATABASE__.hierarchy_relationships
WHERE depth_1 = 1 AND depth_2 = 1
GROUP BY ancestor_name_1, ancestor_name_2, relationship_label
ORDER BY instance_count DESC
LIMIT 20;
