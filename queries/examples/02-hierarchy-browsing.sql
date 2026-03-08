-- 02-hierarchy-browsing.sql
-- Navigate the class hierarchy -- roots, subtrees, paths.
--
-- Uses the class_hierarchy view which provides depth, root_path, edge_type,
-- and is_leaf for every node in the Open Images class taxonomy.

-- Query 1: Find root node(s)
--
-- Expected output:
--   mid      | display_name
--   /m/0dzct | Entity
-- (single root node)

SELECT mid, display_name
FROM __DATABASE__.class_hierarchy
WHERE depth = 0;

-- Query 2: Browse children of a class (e.g., Person)
--
-- Expected output:
--   display_name | depth | edge_type   | is_leaf
--   Boy          | 2     | subcategory | true
--   Girl         | 2     | subcategory | true
--   Man          | 2     | subcategory | true
--   Woman        | 2     | subcategory | true

SELECT display_name, depth, edge_type, is_leaf
FROM __DATABASE__.class_hierarchy
WHERE parent_name = 'Person'
ORDER BY display_name;

-- Query 3: Full path from root to a specific class
--
-- Expected output:
--   display_name | depth | root_path
--   Man          | 2     | Entity > Person > Man

SELECT display_name, depth, root_path
FROM __DATABASE__.class_hierarchy
WHERE display_name = 'Man';

-- Query 4: All leaf nodes at maximum depth
--
-- Expected output: deepest leaf nodes with their full root_path, e.g.:
--   display_name      | depth | root_path
--   French fries       | 4     | Entity > Food > ... > French fries
--   ...
-- (sorted by depth descending, then alphabetically)

SELECT display_name, depth, root_path
FROM __DATABASE__.class_hierarchy
WHERE is_leaf = true
ORDER BY depth DESC, display_name
LIMIT 20;
