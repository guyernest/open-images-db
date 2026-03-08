-- 03-entity-pair-relationships.sql
-- Audit: Entity class pairs per relationship type with human-readable names
-- Requirement: AUDIT-03

-- Query 1: All entity pairs with display names and relationship types
SELECT
  cd1.display_name AS display_name_1,
  cd2.display_name AS display_name_2,
  r.relationship_label,
  COUNT(*)         AS instance_count
FROM __DATABASE__.relationships r
JOIN __DATABASE__.class_descriptions cd1
  ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2
  ON r.label_name_2 = cd2.label_name
GROUP BY cd1.display_name, cd2.display_name, r.relationship_label
ORDER BY instance_count DESC;

-- Query 2: Person-Horse relationships (answering "people on horses" question)
SELECT
  cd1.display_name AS display_name_1,
  cd2.display_name AS display_name_2,
  r.relationship_label,
  COUNT(*)         AS instance_count
FROM __DATABASE__.relationships r
JOIN __DATABASE__.class_descriptions cd1
  ON r.label_name_1 = cd1.label_name
JOIN __DATABASE__.class_descriptions cd2
  ON r.label_name_2 = cd2.label_name
WHERE (cd1.display_name LIKE '%Person%' AND cd2.display_name LIKE '%Horse%')
   OR (cd1.display_name LIKE '%Horse%' AND cd2.display_name LIKE '%Person%')
GROUP BY cd1.display_name, cd2.display_name, r.relationship_label
ORDER BY instance_count DESC;
