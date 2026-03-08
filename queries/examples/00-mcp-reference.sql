-- =============================================================================
-- 00-mcp-reference.sql
-- MCP Reference Resource: Open Images V7 (Validation Set)
--
-- Purpose: Dense, LLM-optimized reference for MCP code mode context injection.
-- An LLM reading only this file can write correct SQL queries against the
-- Open Images database. Inject this as system/tool context before SQL generation.
--
-- Database placeholder: __DATABASE__ (replace with `open_images`)
-- Engine: AWS Athena (Trino SQL dialect) over Apache Iceberg tables
-- =============================================================================


-- =============================================================================
-- Section 1: Schema with Semantics
-- =============================================================================
--
-- BASE TABLES (7 tables)
-- ----------------------
--
-- images
--   image_id            VARCHAR   -- Open Images image identifier (e.g., "000a1249af2bc5f0")
--   original_url        VARCHAR   -- Full URL to original image
--   original_landing_url VARCHAR  -- Flickr landing page URL
--   license             VARCHAR   -- License URL (Creative Commons)
--   author              VARCHAR   -- Photographer / uploader name
--   title               VARCHAR   -- Image title (often NULL)
--   original_size       BIGINT    -- Original file size in bytes
--   thumbnail_300k_url  VARCHAR   -- URL to ~300KB thumbnail (most reliable for display)
--   rotation            DOUBLE    -- EXIF rotation in degrees (0.0, 90.0, 180.0, 270.0)
--
-- labels
--   image_id            VARCHAR   -- FK to images
--   label_name          VARCHAR   -- MID identifier (e.g., /m/01g317) -- NOT human-readable
--   source              VARCHAR   -- "verification" (human) or "machine" (model-generated)
--   confidence          DOUBLE    -- Confidence score (1.0 for human-verified, 0.0-1.0 for machine)
--
-- bounding_boxes (aliased as "boxes" in queries)
--   image_id            VARCHAR   -- FK to images
--   label_name          VARCHAR   -- MID identifier
--   source              VARCHAR   -- Annotation source
--   confidence          DOUBLE    -- Confidence score
--   x_min               DOUBLE    -- Left edge (normalized 0.0-1.0)
--   x_max               DOUBLE    -- Right edge (normalized 0.0-1.0)
--   y_min               DOUBLE    -- Top edge (normalized 0.0-1.0)
--   y_max               DOUBLE    -- Bottom edge (normalized 0.0-1.0)
--   is_occluded         BOOLEAN   -- Object partially hidden
--   is_truncated        BOOLEAN   -- Object extends beyond frame
--   is_group_of         BOOLEAN   -- Box contains a group of objects
--   is_depiction        BOOLEAN   -- Object is a drawing/painting, not real
--   is_inside           BOOLEAN   -- Object is inside another object
--
-- masks
--   image_id            VARCHAR   -- FK to images
--   label_name          VARCHAR   -- MID identifier
--   mask_path           VARCHAR   -- S3 path to segmentation mask PNG
--   box_id              VARCHAR   -- Associated bounding box ID
--   box_x_min           DOUBLE    -- Bounding box coordinates (same semantics as bounding_boxes)
--   box_x_max           DOUBLE
--   box_y_min           DOUBLE
--   box_y_max           DOUBLE
--   predicted_iou       DOUBLE    -- Predicted intersection-over-union quality score
--   clicks              VARCHAR   -- Semicolon-delimited click annotations (VARCHAR, not JSON)
--
-- relationships
--   image_id            VARCHAR   -- FK to images
--   label_name_1        VARCHAR   -- MID of subject entity (e.g., /m/04yx4 = Man)
--   label_name_2        VARCHAR   -- MID of object entity (e.g., /m/03k3r = Horse)
--   relationship_label  VARCHAR   -- Relationship type (e.g., "ride", "on", "wears")
--   x_min_1             DOUBLE    -- Bounding box of entity 1 (normalized 0.0-1.0)
--   x_max_1             DOUBLE
--   y_min_1             DOUBLE
--   y_max_1             DOUBLE
--   x_min_2             DOUBLE    -- Bounding box of entity 2 (normalized 0.0-1.0)
--   x_max_2             DOUBLE
--   y_min_2             DOUBLE
--   y_max_2             DOUBLE
--
-- class_descriptions
--   label_name          VARCHAR   -- MID identifier (e.g., /m/01g317)
--   display_name        VARCHAR   -- Human-readable name (e.g., "Person")
--   Note: 20,931 entries covering all annotation types
--
-- label_hierarchy
--   parent_mid          VARCHAR   -- Parent MID
--   child_mid           VARCHAR   -- Child MID
--   edge_type           VARCHAR   -- "subcategory" or "part"
--   Note: 602 distinct MIDs, 5 depth levels, single root "Entity"
--
--
-- VIEWS (6 views)
-- ---------------
--
-- labeled_images (labels + images + class_descriptions)
--   All labels columns + image metadata + display_name
--   Columns: image_id, original_url, original_landing_url, license, author,
--            title, original_size, thumbnail_300k_url, rotation,
--            source, label_name, display_name, confidence
--
-- labeled_boxes (bounding_boxes + images + class_descriptions)
--   All box columns + image metadata + display_name + computed geometry
--   Extra columns: box_area, box_width, box_height, box_center_x,
--                  box_center_y, aspect_ratio
--
-- labeled_masks (masks + images + class_descriptions)
--   All mask columns + image metadata + display_name + computed geometry
--   Extra columns: box_area, box_width, box_height, box_center_x,
--                  box_center_y, aspect_ratio, click_count
--
-- labeled_relationships (relationships + images + class_descriptions x2)
--   All relationship columns + image metadata + display_name_1, display_name_2
--   Note: INNER JOIN drops ~3.3% of rows (886 of 27,243) due to 3 orphan MIDs
--
-- class_hierarchy (recursive CTE over label_hierarchy + class_descriptions)
--   Columns: mid, display_name, parent_mid, parent_name, depth, edge_type,
--            root_path, is_leaf
--   Provides: full tree traversal with depth tracking and path strings
--   Root node: "Entity" at depth 0
--   Max depth: 5 (but only 5 levels exist in practice)
--
-- hierarchy_relationships (relationships expanded through class hierarchy)
--   All labeled_relationships columns PLUS:
--   ancestor_name_1, ancestor_name_2, depth_1, depth_2
--   Purpose: Query by parent class (e.g., "Person") and automatically match
--            all subclasses (Man, Woman, Boy, Girl)
--   Note: Each relationship row appears multiple times (once per ancestor pair)


-- =============================================================================
-- Section 2: Common Values Enumeration
-- =============================================================================
--
-- RELATIONSHIP TYPES (27 total, 27,243 instances in raw table)
-- ------------------------------------------------------------
--   is              22,292   (81.8% -- attribute/state, e.g., "Man is Standing")
--   wears            1,491   (clothing relationships)
--   at                 662   (spatial, e.g., "Chair at Table")
--   holds              566   (possession/interaction)
--   contain            540   (spatial containment)
--   on                 436   (spatial, e.g., "Man on Horse")
--   ride               361   (action)
--   hang               167   (spatial)
--   plays              158   (action)
--   interacts_with     121   (general interaction)
--   dance              109   (action)
--   inside_of           81   (spatial)
--   kiss                77   (action)
--   hug                 70   (action)
--   skateboard          42   (action)
--   surf                17   (action)
--   throw                9   (action)
--   read                 9   (action)
--   kick                 8   (action)
--   drink                8   (action)
--   hits                 7   (action)
--   catch                4   (action)
--   under                4   (spatial)
--   eat                  1   (action)
--   cut                  1   (action)
--   ski                  1   (action)
--   snowboard            1   (action)
--
--
-- CLASS HIERARCHY -- TOP BRANCHES (under root "Entity")
-- -----------------------------------------------------
--   Entity (root, depth 0)
--     Person (depth 1) -> Boy, Girl, Man, Woman (depth 2)
--     Animal (depth 1) -> Bird, Carnivore, Mammal, Invertebrate, Reptile, Fish (depth 2)
--       Bird -> Chicken, Duck, Eagle, Owl, Parrot, Penguin, ... (depth 3)
--       Carnivore -> Bear, Cat, Dog, Fox, Lion, Tiger, ... (depth 3)
--       Mammal -> Camel, Cattle, Deer, Elephant, Horse, ... (depth 3)
--     Clothing (depth 1) -> Hat, Helmet, Footwear, Trousers, ... (depth 2)
--     Food (depth 1) -> Baked goods, Fruit, Vegetable, Seafood, ... (depth 2)
--     Furniture (depth 1) -> Bed, Table, Couch, Chair, Bench, Desk, ... (depth 2)
--     Musical instrument (depth 1) -> Guitar, Drum, Piano, Violin, ... (depth 2)
--     Sports equipment (depth 1) -> Ball, Bicycle, Racket, ... (depth 2)
--     Tool (depth 1) -> Camera, Hammer, Screwdriver, Wrench, ... (depth 2)
--     Vehicle (depth 1) -> Aircraft, Land vehicle, Watercraft (depth 2)
--       Land vehicle -> Car, Bus, Truck, Motorcycle, ... (depth 3)
--     Weapon (depth 1) -> Axe, Cannon, Dagger, Rifle, Sword, ... (depth 2)
--     ... (90 total depth-1 branches)
--
--   Note: MIDs are internal identifiers like /m/01g317.
--   Always use display_name for human-readable queries, not label_name/MID.


-- =============================================================================
-- Section 3: Query Pattern Cookbook
-- =============================================================================

-- Pattern 1: Hierarchy expansion
-- Find all "Person on Horse" relationships by querying the parent class.
-- hierarchy_relationships automatically expands Person -> Man/Woman/Boy/Girl.

SELECT display_name_1, display_name_2, relationship_label,
       ancestor_name_1, ancestor_name_2
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Person'
  AND ancestor_name_2 = 'Horse'
  AND relationship_label IN ('on', 'ride', 'interacts_with')
ORDER BY display_name_1, relationship_label;

-- Pattern 2: Subtree listing
-- List all classes in a branch of the hierarchy with their full path.

SELECT display_name, depth, edge_type, root_path, is_leaf
FROM __DATABASE__.class_hierarchy
WHERE root_path LIKE 'Entity > Animal%'
ORDER BY depth, display_name;

-- Pattern 3: Multi-table join (image contents)
-- Combine labels, boxes, and relationships for a single image.

WITH img AS (SELECT 'SAMPLE_IMAGE_ID' AS id)
SELECT 'label' AS source_type, li.display_name, NULL AS relationship,
       NULL AS x_min, NULL AS y_min, NULL AS x_max, NULL AS y_max
FROM __DATABASE__.labeled_images li, img
WHERE li.image_id = img.id
UNION ALL
SELECT 'box', lb.display_name, NULL,
       lb.x_min, lb.y_min, lb.x_max, lb.y_max
FROM __DATABASE__.labeled_boxes lb, img
WHERE lb.image_id = img.id
UNION ALL
SELECT 'relationship', lr.display_name_1, lr.relationship_label || ' ' || lr.display_name_2,
       lr.x_min_1, lr.y_min_1, lr.x_max_1, lr.y_max_1
FROM __DATABASE__.labeled_relationships lr, img
WHERE lr.image_id = img.id;

-- Pattern 4: Relationship filtering by ancestor class
-- Find all relationships where any Animal subclass is involved.

SELECT ancestor_name_1, display_name_1, relationship_label,
       display_name_2, ancestor_name_2
FROM __DATABASE__.hierarchy_relationships
WHERE ancestor_name_1 = 'Animal'
  AND depth_1 > 0
ORDER BY relationship_label, display_name_1
LIMIT 20;

-- Pattern 5: Aggregation with window functions
-- Rank relationship types by count within each ancestor class pair.

SELECT ancestor_name_1, ancestor_name_2, relationship_label,
       instance_count,
       RANK() OVER (PARTITION BY ancestor_name_1, ancestor_name_2
                    ORDER BY instance_count DESC) AS type_rank
FROM (
  SELECT ancestor_name_1, ancestor_name_2, relationship_label,
         COUNT(*) AS instance_count
  FROM __DATABASE__.hierarchy_relationships
  WHERE depth_1 = 1 AND depth_2 = 1
  GROUP BY ancestor_name_1, ancestor_name_2, relationship_label
) sub
ORDER BY ancestor_name_1, ancestor_name_2, type_rank
LIMIT 30;

-- Pattern 6: CTE for complex analysis
-- Combine hierarchy structure with relationship counts per branch.

WITH branch_stats AS (
  SELECT ancestor_name_1 AS branch,
         COUNT(*) AS total_relationships,
         COUNT(DISTINCT relationship_label) AS distinct_types,
         COUNT(DISTINCT display_name_1) AS distinct_entities
  FROM __DATABASE__.hierarchy_relationships
  WHERE depth_1 > 0
  GROUP BY ancestor_name_1
),
branch_size AS (
  SELECT parent_name AS branch,
         COUNT(*) AS child_count
  FROM __DATABASE__.class_hierarchy
  WHERE parent_name IS NOT NULL
  GROUP BY parent_name
)
SELECT bs.branch, bs.total_relationships, bs.distinct_types,
       bs.distinct_entities, COALESCE(bz.child_count, 0) AS hierarchy_children
FROM branch_stats bs
LEFT JOIN branch_size bz ON bs.branch = bz.branch
ORDER BY bs.total_relationships DESC
LIMIT 15;


-- =============================================================================
-- Section 4: Known pitfalls
-- =============================================================================
--
-- Pitfall 1: Raw MIDs vs display names
--   label_name columns contain MIDs (e.g., /m/04yx4), NOT human-readable names.
--   Always use display_name columns from views, or JOIN class_descriptions:
--     JOIN __DATABASE__.class_descriptions cd ON t.label_name = cd.label_name
--   Then use cd.display_name in WHERE clauses and output.
--
-- Pitfall 2: INNER JOIN drops rows
--   labeled_relationships (and hierarchy_relationships) use INNER JOINs to
--   class_descriptions. This drops ~3.3% of rows (886 of 27,243) because
--   3 orphan MIDs in the relationships table have no class_descriptions entry.
--   All 886 dropped rows are "is" type relationships. Action/spatial
--   relationships (ride, on, wears, etc.) are 100% preserved.
--
-- Pitfall 3: edge_type filtering
--   label_hierarchy has an edge_type column: "subcategory" (is-a) or "part"
--   (has-part). Some nodes appear under multiple parents with different edge
--   types (e.g., Axe under both Tool and Weapon). Filter on edge_type if you
--   need strict is-a relationships only:
--     WHERE edge_type = 'subcategory'
--
-- Pitfall 4: Recursive CTE depth
--   class_hierarchy and hierarchy_relationships views cap recursion at 20
--   levels. In practice only 5 depth levels exist, so this is not limiting.
--
-- Pitfall 5: Leaf classes in relationships
--   The relationships table uses leaf-level classes only (e.g., Man, Woman,
--   Dog, Cat), never parent classes (Person, Animal). To query by parent
--   class, use the hierarchy_relationships view which expands ancestors:
--     WHERE ancestor_name_1 = 'Person'  -- matches Man, Woman, Boy, Girl
--   Do NOT use:
--     WHERE display_name_1 = 'Person'   -- returns zero rows
--
-- Pitfall 6: The "is" relationship dominates
--   The "is" relationship type accounts for 81.8% of all relationship rows
--   (22,292 of 27,243). It describes attributes/states (e.g., "Man is Standing",
--   "Table is Wood"), not actions or spatial relations.
--   For action/spatial analysis, filter it out:
--     WHERE relationship_label != 'is'
--   Or use an inclusion list:
--     WHERE relationship_label IN ('ride', 'on', 'wears', 'holds', 'at', ...)
--
-- Pitfall 7: Database placeholder
--   All queries use __DATABASE__ as a placeholder. Replace with the actual
--   database name: open_images
--   Example: __DATABASE__.labeled_images -> open_images.labeled_images
