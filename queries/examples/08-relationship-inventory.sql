-- 08-relationship-inventory.sql
-- MCP prompt: "What relationships involve cars?"
--
-- Uses hierarchy_relationships to find all relationship types where Car
-- (or any Car subclass) participates as either subject or object.
-- Car is under Vehicle > Land vehicle > Car in the hierarchy.

-- Query 1: Relationship types involving Car, with counts
--
-- Groups by relationship type to show what kinds of interactions
-- cars participate in across the dataset.
--
-- Expected output (approximate):
--   relationship_label | instance_count
--   is                 | ...  (attributes like "Car is Red")
--   on                 | ...  (spatial, e.g., "Person on Car")
--   contain            | ...
--   inside_of          | ...
--   ...

SELECT relationship_label, COUNT(*) AS instance_count
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Car' OR ancestor_name_2 = 'Car'
GROUP BY relationship_label
ORDER BY instance_count DESC;

-- Query 2: Specific entity pairs involving Car
--
-- Shows which entities cars interact with and how, grouped by
-- the concrete entity names and relationship type.
--
-- Expected output (approximate top rows):
--   display_name_1 | display_name_2 | relationship_label | pair_count
--   Car            | Wheel          | contain            | ...
--   Man            | Car            | on                 | ...
--   Man            | Car            | inside_of          | ...
--   Woman          | Car            | inside_of          | ...
--   ...

SELECT display_name_1, display_name_2, relationship_label,
       COUNT(*) AS pair_count
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Car' OR ancestor_name_2 = 'Car'
GROUP BY display_name_1, display_name_2, relationship_label
ORDER BY pair_count DESC
LIMIT 20;
