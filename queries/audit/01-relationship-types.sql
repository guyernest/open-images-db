-- 01-relationship-types.sql
-- Audit: Distinct relationship types with counts from raw table and view
-- Requirement: AUDIT-01

-- Query 1: Relationship types and counts from raw relationships table
SELECT
  relationship_label,
  COUNT(*) AS instance_count
FROM __DATABASE__.relationships
GROUP BY relationship_label
ORDER BY instance_count DESC;

-- Query 2: Relationship types and counts from labeled_relationships view
SELECT
  relationship_label,
  COUNT(*) AS instance_count
FROM __DATABASE__.labeled_relationships
GROUP BY relationship_label
ORDER BY instance_count DESC;

-- Query 3: Total row counts from both sources (quantify INNER JOIN drop)
SELECT
  'relationships' AS source,
  COUNT(*)        AS total_rows
FROM __DATABASE__.relationships
UNION ALL
SELECT
  'labeled_relationships' AS source,
  COUNT(*)                AS total_rows
FROM __DATABASE__.labeled_relationships;
