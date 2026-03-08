-- 05-entity-search.sql
-- MCP prompt: "Find images of dogs playing"
--
-- Uses hierarchy_relationships to find play-related relationships involving
-- Dog and its ancestors. The hierarchy expansion means querying "Dog" as an
-- ancestor also catches any Dog subclasses if they exist.

-- Query 1: Find images with dogs in play-related relationships
--
-- Uses ancestor_name columns to match Dog (and any subclasses) involved in
-- action relationships like plays, interacts_with.
--
-- Expected output: rows showing specific dog interactions, e.g.:
--   image_id         | display_name_1 | display_name_2 | relationship_label | thumbnail_300k_url
--   abcdef123456     | Dog            | Man            | plays              | https://...
--   ...
-- (Dog participates in plays, interacts_with, and other action relationships)

SELECT image_id, display_name_1, display_name_2, relationship_label,
       thumbnail_300k_url
FROM __DATABASE__.hierarchy_relationships
WHERE (ancestor_name_1 = 'Dog' OR ancestor_name_2 = 'Dog')
  AND relationship_label IN ('plays', 'interacts_with')
ORDER BY relationship_label, display_name_1
LIMIT 20;

-- Query 2: Expand to all Animal subclasses playing
--
-- Group by entity and relationship type to see which animals participate
-- in play-related relationships and how frequently.
--
-- Expected output (approximate):
--   display_name_1   | relationship_label | instance_count
--   Dog              | interacts_with     | ...
--   Cat              | interacts_with     | ...
--   Dog              | plays              | ...
--   ...
-- (Various Animal subclasses with action relationship counts)

SELECT display_name_1, relationship_label, COUNT(*) AS instance_count
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Animal'
  AND depth_1 > 0
  AND relationship_label IN ('plays', 'interacts_with', 'ride', 'on')
GROUP BY display_name_1, relationship_label
ORDER BY instance_count DESC
LIMIT 20;
