-- 06-category-exploration.sql
-- MCP prompt: "What categories exist under Animal?"
--
-- Uses the class_hierarchy view to explore the taxonomy. The hierarchy has
-- a single root "Entity" with 90 top-level branches. Animal is one of the
-- richest branches with multiple levels of subclasses.

-- Query 1: Direct children of Animal
--
-- Lists immediate subclasses of Animal with their depth, edge type, and
-- whether they are leaf nodes (no further children).
--
-- Expected output:
--   display_name  | depth | edge_type   | is_leaf
--   Bird          | 2     | subcategory | false
--   Carnivore     | 2     | subcategory | false
--   Fish          | 2     | subcategory | false
--   Invertebrate  | 2     | subcategory | false
--   Mammal        | 2     | subcategory | false
--   Reptile       | 2     | subcategory | false

SELECT display_name, depth, edge_type, is_leaf
FROM __DATABASE__.class_hierarchy
WHERE parent_name = 'Animal'
ORDER BY display_name;

-- Query 2: Full subtree under Animal
--
-- Shows every class in the Animal branch with its full path from root
-- and depth level. Useful for understanding the complete taxonomy.
--
-- Expected output (sample rows):
--   display_name  | depth | root_path
--   Animal        | 1     | Entity > Animal
--   Bird          | 2     | Entity > Animal > Bird
--   Chicken       | 3     | Entity > Animal > Bird > Chicken
--   Duck          | 3     | Entity > Animal > Bird > Duck
--   Eagle         | 3     | Entity > Animal > Bird > Eagle
--   Carnivore     | 2     | Entity > Animal > Carnivore
--   Bear          | 3     | Entity > Animal > Carnivore > Bear
--   Cat           | 3     | Entity > Animal > Carnivore > Cat
--   Dog           | 3     | Entity > Animal > Carnivore > Dog
--   Mammal        | 2     | Entity > Animal > Mammal
--   Horse         | 3     | Entity > Animal > Mammal > Horse
--   ...
-- (Full Animal subtree across depths 1-4, ordered by depth then name)

SELECT display_name, depth, root_path
FROM __DATABASE__.class_hierarchy
WHERE root_path LIKE 'Entity > Animal%'
ORDER BY depth, display_name;
