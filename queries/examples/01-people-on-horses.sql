-- 01-people-on-horses.sql
-- The motivating use case -- find all relationships between people and horses
-- using hierarchy expansion.
--
-- Without the hierarchy_relationships view, you would need to know every
-- subclass of Person (Man, Woman, Girl, Boy) and query them individually.
-- With ancestor expansion, a single WHERE clause on ancestor_name covers
-- all subclasses automatically.

-- Query 1: Find all "Person on/ride/interacts_with Horse" relationships
--
-- Expected output: rows for Man/Woman/Girl/Boy with Horse, e.g.:
--   display_name_1 | display_name_2 | relationship_label | ancestor_name_1 | ancestor_name_2 | depth_1 | depth_2
--   Boy            | Horse          | interacts_with     | Person          | Horse           | 2       | 1
--   Boy            | Horse          | on                 | Person          | Horse           | 2       | 1
--   Girl           | Horse          | ride               | Person          | Horse           | 2       | 1
--   Man            | Horse          | interacts_with     | Person          | Horse           | 2       | 1
--   Man            | Horse          | on                 | Person          | Horse           | 2       | 1
--   Man            | Horse          | ride               | Person          | Horse           | 2       | 1
--   Woman          | Horse          | interacts_with     | Person          | Horse           | 2       | 1
--   Woman          | Horse          | on                 | Person          | Horse           | 2       | 1
--   Woman          | Horse          | ride               | Person          | Horse           | 2       | 1
--   ...
-- Total: ~149 rows (person-horse relationship instances from audit data)

SELECT display_name_1, display_name_2, relationship_label,
       ancestor_name_1, ancestor_name_2, depth_1, depth_2
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Person'
  AND ancestor_name_2 = 'Horse'
  AND relationship_label IN ('on', 'ride', 'interacts_with')
ORDER BY display_name_1, relationship_label;

-- Query 2: Count by relationship type
--
-- Expected output (approximate from audit data):
--   relationship_label | instance_count
--   interacts_with     | ~59
--   ride               | ~46
--   on                 | ~42

SELECT relationship_label, COUNT(*) AS instance_count
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Person'
  AND ancestor_name_2 = 'Horse'
GROUP BY relationship_label
ORDER BY instance_count DESC;
