-- 04-dropped-rows-analysis.sql
-- Audit: Analysis of rows dropped by INNER JOIN in labeled_relationships view
-- Traces which relationship types and MIDs are lost when class_descriptions has no match

-- Query 1: Rows in relationships with no match in class_descriptions (either side)
SELECT
  r.relationship_label,
  r.label_name_1,
  r.label_name_2,
  COUNT(*) AS dropped_count
FROM __DATABASE__.relationships r
LEFT JOIN __DATABASE__.class_descriptions cd1
  ON r.label_name_1 = cd1.label_name
LEFT JOIN __DATABASE__.class_descriptions cd2
  ON r.label_name_2 = cd2.label_name
WHERE cd1.label_name IS NULL
   OR cd2.label_name IS NULL
GROUP BY r.relationship_label, r.label_name_1, r.label_name_2
ORDER BY dropped_count DESC;

-- Query 2: Distinct orphan MIDs from relationships with no class_descriptions match
SELECT orphan_mid, side, COUNT(*) AS occurrence_count
FROM (
  SELECT r.label_name_1 AS orphan_mid, '1' AS side
  FROM __DATABASE__.relationships r
  LEFT JOIN __DATABASE__.class_descriptions cd
    ON r.label_name_1 = cd.label_name
  WHERE cd.label_name IS NULL
  UNION ALL
  SELECT r.label_name_2 AS orphan_mid, '2' AS side
  FROM __DATABASE__.relationships r
  LEFT JOIN __DATABASE__.class_descriptions cd
    ON r.label_name_2 = cd.label_name
  WHERE cd.label_name IS NULL
)
GROUP BY orphan_mid, side
ORDER BY occurrence_count DESC;
