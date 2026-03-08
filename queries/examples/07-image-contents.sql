-- 07-image-contents.sql
-- MCP prompt: "What's in this image?" (given an image_id)
--
-- Demonstrates how to retrieve all annotations for a single image by
-- querying labels, bounding boxes, and relationships separately.
-- Substitute any image_id for the sample value below.
--
-- In practice, an MCP tool would combine these queries or use UNION ALL
-- to return a single unified result set describing the image contents.

-- Replace this with any valid image_id from the dataset.
-- This example uses a placeholder; pick an image_id known to have
-- relationships for the richest output.

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
WHERE image_id = 'SAMPLE_IMAGE_ID'
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
WHERE image_id = 'SAMPLE_IMAGE_ID'
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
WHERE image_id = 'SAMPLE_IMAGE_ID'
ORDER BY display_name_1, relationship_label;
