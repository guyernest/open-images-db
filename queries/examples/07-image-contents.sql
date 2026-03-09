-- 07-image-contents.sql
-- MCP prompt: "What's in this image?" (given an image_id)
--
-- Demonstrates how to retrieve all annotations for a single image by
-- querying labels, bounding boxes, and relationships separately.
--
-- In practice, an MCP tool would receive the image_id as a parameter.
-- These examples use a subquery to pick an image with relationships
-- so the validation always returns non-empty results.

-- Query 1: All image-level labels
--
-- Shows what objects/concepts are tagged in the image with confidence scores.
--
-- Expected output (example for an image with people and animals):
--   display_name | source       | confidence
--   Person       | verification | 1.0
--   Horse        | verification | 1.0
--   Animal       | machine      | 0.92
--   ...

SELECT display_name, source, confidence
FROM __DATABASE__.labeled_images
WHERE image_id IN (SELECT image_id FROM __DATABASE__.labeled_relationships LIMIT 1)
ORDER BY confidence DESC, display_name;

-- Query 2: All bounding boxes
--
-- Shows object locations as normalized coordinates (0.0-1.0 range).
--
-- Expected output:
--   display_name | x_min | x_max | y_min | y_max
--   Man          | 0.12  | 0.45  | 0.10  | 0.85
--   Horse        | 0.30  | 0.90  | 0.20  | 0.95
--   ...

SELECT display_name, x_min, x_max, y_min, y_max
FROM __DATABASE__.labeled_boxes
WHERE image_id IN (SELECT image_id FROM __DATABASE__.labeled_relationships LIMIT 1)
ORDER BY display_name;

-- Query 3: All relationships
--
-- Shows how objects in the image relate to each other.
--
-- Expected output:
--   display_name_1 | relationship_label | display_name_2
--   Man            | ride               | Horse
--   Man            | on                 | Horse
--   ...

SELECT display_name_1, relationship_label, display_name_2
FROM __DATABASE__.labeled_relationships
WHERE image_id IN (SELECT image_id FROM __DATABASE__.labeled_relationships LIMIT 1)
ORDER BY display_name_1, relationship_label;
