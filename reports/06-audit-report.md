# Open Images Validation Set: Relationship & Hierarchy Audit

**Date:** 2026-03-08
**Dataset:** Open Images V7 -- Validation Set
**Database:** open_images (AWS Athena / Iceberg)

## Executive Summary

- **Raw relationship rows:** 27,243 (relationships table)
- **View relationship rows:** 26,357 (labeled_relationships view)
- **Rows dropped by INNER JOIN:** 886 (3.3%) -- caused by 3 orphan MIDs missing from class_descriptions
- **Distinct relationship types:** 27 (same count in both raw and view)
- **Hierarchy edges:** 602 distinct MIDs across 5 depth levels, single root node
- **Class descriptions coverage:** 602 MIDs in hierarchy vs 20,931 total in class_descriptions (2.9%)

### Key Finding: "People on Horses"

**The data exists.** The validation set contains 149 relationship instances between people and horses:

| Entity 1 | Entity 2 | Relationship | Count |
|----------|----------|-------------|-------|
| Man | Horse | interacts_with | 46 |
| Man | Horse | ride | 34 |
| Man | Horse | on | 31 |
| Woman | Horse | interacts_with | 11 |
| Woman | Horse | ride | 11 |
| Woman | Horse | on | 10 |
| Girl | Horse | ride | 1 |
| Girl | Horse | interacts_with | 1 |
| Girl | Horse | on | 1 |
| Boy | Horse | ride | 1 |
| Boy | Horse | interacts_with | 1 |
| Boy | Horse | on | 1 |

**Why searching for "Person on Horse" fails:** Open Images uses specific sub-classes (Man, Woman, Girl, Boy) rather than the parent class "Person" in relationship annotations. A query for `display_name = 'Person'` returns zero results because no relationship row uses the Person MID directly. The hierarchy shows Person -> {Man, Woman, Girl, Boy} but the relationships table uses only the leaf-level classes. To find "people on horses" a user must search for Man/Woman/Girl/Boy individually, or the query layer needs to resolve Person to its children via the hierarchy.

---

## 1. Relationship Types Inventory (AUDIT-01)

### 1.1 All Relationship Types from Raw Table

| Relationship Label | Instance Count |
|-------------------|---------------|
| is | 22,292 |
| wears | 1,491 |
| at | 662 |
| holds | 566 |
| contain | 540 |
| on | 436 |
| ride | 361 |
| hang | 167 |
| plays | 158 |
| interacts_with | 121 |
| dance | 109 |
| inside_of | 81 |
| kiss | 77 |
| hug | 70 |
| skateboard | 42 |
| surf | 17 |
| throw | 9 |
| read | 9 |
| kick | 8 |
| drink | 8 |
| hits | 7 |
| catch | 4 |
| under | 4 |
| eat | 1 |
| cut | 1 |
| ski | 1 |
| snowboard | 1 |

**Total:** 27 distinct relationship types, 27,243 total instances.

The `is` relationship dominates at 81.8% of all rows (e.g., "Man is Standing", "Table is Wood"). The remaining 26 types represent actions and spatial relationships.

### 1.2 Relationship Types from labeled_relationships View

| Relationship Label | Raw Count | View Count | Delta |
|-------------------|-----------|------------|-------|
| is | 22,292 | 21,406 | -886 |
| wears | 1,491 | 1,491 | 0 |
| at | 662 | 662 | 0 |
| holds | 566 | 566 | 0 |
| contain | 540 | 540 | 0 |
| on | 436 | 436 | 0 |
| ride | 361 | 361 | 0 |
| hang | 167 | 167 | 0 |
| plays | 158 | 158 | 0 |
| interacts_with | 121 | 121 | 0 |
| dance | 109 | 109 | 0 |
| inside_of | 81 | 81 | 0 |
| kiss | 77 | 77 | 0 |
| hug | 70 | 70 | 0 |
| skateboard | 42 | 42 | 0 |
| surf | 17 | 17 | 0 |
| throw | 9 | 9 | 0 |
| read | 9 | 9 | 0 |
| kick | 8 | 8 | 0 |
| drink | 8 | 8 | 0 |
| hits | 7 | 7 | 0 |
| catch | 4 | 4 | 0 |
| under | 4 | 4 | 0 |
| eat | 1 | 1 | 0 |
| cut | 1 | 1 | 0 |
| ski | 1 | 1 | 0 |
| snowboard | 1 | 1 | 0 |

**All 886 dropped rows are `is` relationships.** No other relationship type loses data through the INNER JOIN. This means all action/spatial relationships (ride, on, at, etc.) are fully preserved in the view.

---

## 2. Hierarchy Structure (AUDIT-02)

### 2.1 Root Node

| MID | Display Name |
|-----|-------------|
| /m/0bl9f | *(no class_descriptions entry)* |

There is a **single root node** (`/m/0bl9f`). This MID has no entry in class_descriptions, so it displays as its raw MID. In the Open Images hierarchy it represents the top-level "Entity" or "Object" category.

### 2.2 Depth and Size

| Metric | Value |
|--------|-------|
| Max depth | 5 |
| Distinct MIDs in hierarchy | 602 |
| Total class_descriptions entries | 20,931 |
| Hierarchy coverage | 2.9% of all known labels |
| Total tree traversal rows | 1,360 |

The 1,360 traversal rows vs 602 distinct MIDs means many nodes appear at multiple positions -- this is because the flattened hierarchy CSV merges both Subcategory (is-a) and Part (has-part) edge types into a single parent-child format. A node like "Axe" appears under both "Tool" (Subcategory) and "Weapon" (Subcategory), producing duplicate tree paths.

### 2.3 Depth Distribution

| Depth | Node Count (with duplicates) |
|-------|------------------------------|
| 0 | 1 (root) |
| 1 | 90 |
| 2 | 404 |
| 3 | 633 |
| 4 | 225 |
| 5 | 7 |

The tree is widest at depth 3 with 633 entries. Depth 5 has only 7 entries, indicating the hierarchy is broad and shallow.

### 2.4 Tree Visualization (Top 3 Levels)

```
/m/0bl9f (root -- "Entity")
+-- Animal (6 direct children)
|   +-- Bird (17 children: Chicken, Duck, Eagle, Owl, Parrot, Penguin, ...)
|   +-- Carnivore (13 children: Bear, Cat, Dog, Fox, Lion, Tiger, ...)
|   +-- Mammal (30 children: Camel, Cattle, Deer, Elephant, Horse, ...)
|   +-- Invertebrate (9 children: Insect, Shellfish, Spider, ...)
|   +-- Reptile (6 children: Crocodile, Lizard, Snake, Turtle, ...)
|   +-- Fish (4 children)
+-- Clothing (19 direct children)
|   +-- Hat (8), Helmet (6), Footwear (4), Trousers (1), ...
+-- Food (21 direct children)
|   +-- Baked goods (6), Fruit (16), Vegetable (13), Seafood (2), ...
+-- Furniture (20 direct children)
|   +-- Bed (2), Table (2), Couch (2), Chair, Bench, Desk, ...
+-- Musical instrument (40 direct children)
|   +-- Accordion, Banjo, Cello, Drum, Flute, Guitar, Harp, ...
+-- Person (5 direct children)
|   +-- Boy, Girl, Man, Woman, Human body parts...
+-- Sports equipment (58 direct children)
|   +-- Ball (10 sub-types), Bicycle (3), Racket (4), ...
+-- Tool (46 direct children)
|   +-- Camera, Binoculars, Hammer, Screwdriver, Wrench, ...
+-- Vehicle (3 direct children)
|   +-- Aircraft (3), Land vehicle (16), Watercraft (3)
+-- Weapon (24 direct children)
|   +-- Axe, Bomb, Cannon, Dagger, Rifle, Sword, ...
+-- ... (80 more depth-1 branches)
```

### 2.5 Branch Density

**Richest branches** (most direct children):

| Parent | Children |
|--------|----------|
| /m/0bl9f (root) | 90 |
| Sports equipment | 58 |
| Tool | 46 |
| Musical instrument | 40 |
| Kitchen utensil | 39 |
| Mammal | 30 |
| Building | 29 |
| Human body | 26 |
| Weapon | 24 |
| Food | 21 |

**Sparsest branches** (1 child):

| Parent | Children |
|--------|----------|
| Trousers | 1 |
| Traffic sign | 1 |
| Door | 1 |
| Beetle | 1 |
| Glove | 1 |
| Skirt | 1 |

### 2.6 Coverage Gap

The hierarchy covers only **602 of 20,931** labels in class_descriptions (2.9%). This is expected: the hierarchy is derived from `bbox_labels_600_hierarchy.json` which covers only the ~600 "boxable" label classes. The remaining ~20K labels are for image-level labels, segmentation masks, and other annotation types that don't participate in the bounding-box hierarchy.

**Note:** The Subcategory vs Part distinction from the original JSON is NOT preserved in the flattened CSV. Both edge types are stored as undifferentiated parent-child rows in label_hierarchy. This causes some nodes to appear under multiple parents (e.g., Axe under both Tool and Weapon).

---

## 3. Entity-Class Pair Analysis (AUDIT-03)

### 3.1 Top 20 Entity Pairs by Instance Count

| Entity 1 | Entity 2 | Relationship | Count |
|----------|----------|-------------|-------|
| Man | Standing | is | 4,865 |
| Woman | Standing | is | 2,674 |
| Girl | Standing | is | 1,886 |
| Man | Sitting | is | 1,672 |
| Woman | Smile | is | 1,388 |
| Girl | Smile | is | 1,329 |
| Man | Smile | is | 1,127 |
| Woman | Sitting | is | 888 |
| Girl | Sitting | is | 641 |
| Table | Wood | is | 550 |
| Boy | Standing | is | 490 |
| Man | Walking | is | 400 |
| Boy | Sitting | is | 311 |
| Chair | Wood | is | 249 |
| Girl | Walking | is | 236 |
| Man | Running | is | 229 |
| Chair | Table | at | 225 |
| Table | Plastic | is | 218 |
| Boy | Smile | is | 206 |
| Woman | Walking | is | 198 |

The top pairs are dominated by `is` relationships describing people's poses/states (Standing, Sitting, Smile) and object materials (Wood, Plastic, Leather).

### 3.2 Distribution of Entity Pair Counts

| Threshold | Pairs | Percentage |
|-----------|-------|-----------|
| > 1,000 instances | 7 | 1.2% |
| > 100 instances | 29 | 5.1% |
| > 10 instances | 158 | 28.0% |
| <= 10 instances | 406 | 72.0% |
| **Total distinct pairs** | **564** | 100% |

The distribution is heavily skewed: 7 pairs account for the bulk of data while 72% of pairs have 10 or fewer instances. This long tail is typical of annotation datasets.

### 3.3 Person-Horse Analysis

As detailed in the Executive Summary, there are **149 Person-Horse relationship instances** in the validation set across Man, Woman, Girl, and Boy paired with Horse via `ride`, `on`, and `interacts_with` relationships.

The discoverability problem: searching for "Person" + "Horse" returns nothing because relationship annotations use the specific sub-classes (Man, Woman, Girl, Boy), not the parent "Person" class. Resolving this requires either:

1. **Query-side fix:** A view or function that resolves parent classes to their children via the hierarchy
2. **Documentation:** Documenting that relationship queries should use leaf-level class names

This is a **query gap**, not a source data gap -- the data exists but isn't easily discoverable through the current query surface.

---

## 4. Dropped Row Analysis

### 4.1 Summary

| Metric | Value |
|--------|-------|
| Total dropped rows | 886 |
| Percentage of raw data | 3.3% |
| Affected relationship types | 1 (only `is`) |
| Cause | 3 MIDs in relationships.label_name_2 with no class_descriptions match |

### 4.2 Orphan MIDs

The 886 dropped rows are caused by exactly **3 MIDs** that appear on the `label_name_2` side of relationships but have no entry in class_descriptions:

| Orphan MID | Occurrences | Likely Meaning |
|------------|-------------|---------------|
| /m/01lhf | 339 | Attribute/property (used in `is` relationships) |
| /m/051_dmw | 288 | Attribute/property (used in `is` relationships) |
| /m/02gy9n | 259 | Material/property (used in `is` relationships) |

These MIDs are NOT the same as the MIDs for similar concepts that DO exist in class_descriptions. For example, class_descriptions has entries for Standing (/m/02wzbmj), Sitting (/m/015c4z), and Wood (/m/083vt), but the relationships table sometimes uses different MIDs for what appear to be the same or similar concepts.

### 4.3 Affected Entity Pairs

| Entity 1 | Orphan MID | Dropped Count |
|----------|-----------|---------------|
| Bottle (/m/04dr76w) | /m/02gy9n | 211 |
| Man (/m/04yx4) | /m/01lhf | 194 |
| Man (/m/04yx4) | /m/051_dmw | 91 |
| Woman (/m/03bt1vf) | /m/01lhf | 80 |
| Woman (/m/03bt1vf) | /m/051_dmw | 79 |
| Girl (/m/05r655) | /m/051_dmw | 77 |
| Girl (/m/05r655) | /m/01lhf | 62 |
| Boy (/m/01bl7v) | /m/051_dmw | 41 |
| Table (/m/04bcr3) | /m/02gy9n | 23 |
| Coffee cup (/m/02p5f1q) | /m/02gy9n | 10 |
| Coffee table (/m/078n6m) | /m/02gy9n | 8 |
| Mug (/m/02jvh9) | /m/02gy9n | 7 |
| Boy (/m/01bl7v) | /m/01lhf | 3 |

### 4.4 Classification

These dropped rows are a **pipeline gap**: the class_descriptions file (oidv7-class-descriptions.csv) does not include entries for these 3 MIDs, but the relationships annotations reference them. The Open Images V7 relationships CSV was authored with a broader MID vocabulary than what class_descriptions covers.

**This is NOT a validation-subset issue** -- adding train/test data would not fix it. The 3 orphan MIDs would still lack class_descriptions entries regardless of which split is loaded.

---

## 5. Gap Classification

| # | Gap | Type | Severity | Fixable? |
|---|-----|------|----------|----------|
| 1 | "Person on Horse" not directly queryable | **Query gap** | Medium | Yes -- resolve hierarchy parents to children in queries |
| 2 | 886 rows (3.3%) dropped by INNER JOIN | **Pipeline gap** | Low | Partially -- could add 3 MIDs to class_descriptions or use LEFT JOIN |
| 3 | Hierarchy covers only 602 of 20,931 labels | **Source gap** | Informational | No -- by design (boxable labels only) |
| 4 | Subcategory vs Part edge types merged | **Pipeline gap** | Low | Yes -- add edge_type column to label_hierarchy table |
| 5 | Relationship MIDs use different MIDs than class_descriptions for same concepts | **Source gap** | Low | Partially -- could create MID alias mapping |

### Gap Details

**Gap 1 (Query gap):** The most impactful for users. The hierarchy data exists to resolve "Person" -> {Man, Woman, Girl, Boy}, but no view or function currently uses it. A hierarchy-aware relationship view would solve this completely.

**Gap 2 (Pipeline gap):** 886 rows lost because 3 MIDs in the relationships source file don't have matching entries in class_descriptions. Options: (a) add the 3 MIDs manually, (b) switch labeled_relationships to LEFT JOIN (shows MID instead of display name for unmatched), (c) accept the 3.3% loss as tolerable.

**Gap 3 (Source gap):** Expected behavior. The hierarchy JSON covers ~600 boxable label classes; class_descriptions covers all ~21K labels from all annotation types. No action needed.

**Gap 4 (Pipeline gap):** The flatten-hierarchy.sh script processes both Subcategory and Part arrays but outputs them identically. Adding an `edge_type` column would preserve this distinction and reduce duplicate tree paths.

**Gap 5 (Source gap):** The Open Images V7 relationships CSV occasionally uses MIDs that differ from class_descriptions for the same concept. This is an upstream data quality issue. A MID alias table could bridge the gap but requires manual mapping.

---

## 6. Recommendations for Phase 7

### Priority 1: Hierarchy-Aware Relationship View (fixes Gap 1)

Create a view or materialized query that resolves parent class names to their children via the hierarchy. This would allow `WHERE entity = 'Person'` to automatically include Man, Woman, Girl, Boy results. This is the highest-impact fix because it directly addresses the user's "people on horses" use case.

**Approach:** Create a recursive CTE view that expands any queried class name to include all descendant classes, then joins against relationships.

### Priority 2: Preserve Edge Type in Hierarchy (fixes Gap 4)

Modify the label_hierarchy table to include an `edge_type` column (`subcategory` or `part`). Update flatten-hierarchy.sh to output this column. This reduces tree ambiguity and enables more precise hierarchy queries.

### Priority 3: Address Dropped Rows (fixes Gap 2)

Options (choose one):
- **Option A:** Add the 3 orphan MIDs to class_descriptions with best-guess display names
- **Option B:** Change labeled_relationships to use LEFT JOIN (shows raw MID when no display name available)
- **Option C:** Accept 3.3% loss (all dropped rows are `is` attribute relationships, not action/spatial)

**Recommended:** Option C (accept loss) unless the 3 orphan MIDs can be definitively identified. The dropped rows are all `is` type attribute relationships and don't affect action queries like "ride", "on", etc.

### Priority 4: Document Query Patterns (no code change)

Document that relationship queries should use leaf-level class names (Man, Woman, Girl, Boy) rather than parent classes (Person), and provide example queries showing how to search effectively.

---

*Report generated from live Athena queries against open_images database.*
*Queries: queries/audit/01-relationship-types.sql through 04-dropped-rows-analysis.sql*
*Runner: scripts/run-audit.sh*
