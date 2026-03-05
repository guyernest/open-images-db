# Feature Research

**Domain:** Open Images V7 data pipeline to S3/Iceberg with Athena SQL interface
**Researched:** 2026-03-05
**Confidence:** MEDIUM (based on training data; Open Images V7 schema stable since 2022, Athena/Iceberg well-documented but web verification unavailable)

## Feature Landscape

### Table Stakes (Users Expect These)

Features the downstream MCP team and any SQL consumer will assume exist. Missing these means the pipeline is not usable.

#### Data Completeness

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| All 4 annotation types loaded | Downstream queries need labels, boxes, masks, relationships | MEDIUM | Each annotation type is a separate CSV with distinct schema; masks have a RunLength-encoded format that needs special handling |
| Image metadata table | Every query starts from "which images"; need ImageID, OriginalURL, License, Author, dimensions | LOW | `oidv7-validation-images-with-rotation.csv` is the source; straightforward columnar mapping |
| Class/label description lookup | Raw data uses MIDs (e.g., `/m/01g317`); without human-readable names, SQL results are meaningless | LOW | `oidv6-class-descriptions.csv` maps MID to DisplayName; must be a dimension table |
| Hierarchy metadata table | Label hierarchy (IsGroupOf, parent-child relationships) needed for semantic queries | LOW | `bbox_labels_600_hierarchy.json` defines the label tree; flatten to a lookup table |
| Cross-table join capability | "Find images with label X AND bounding box Y" is the core use case for a queryable dataset | MEDIUM | Requires consistent ImageID foreign keys across all tables; partition alignment matters |
| Verification/confidence columns preserved | Labels have Confidence scores, boxes have IsOccluded/IsTruncated/IsGroupOf; dropping these makes the data useless for ML | LOW | Direct column mapping from source CSVs |

#### Pipeline Reliability

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Idempotent pipeline scripts | Running the script twice should not corrupt data or double-load | MEDIUM | Use `aws s3 sync` for downloads; for Iceberg loads, drop-and-recreate or use MERGE |
| Error handling and resumability | GCS-to-S3 transfer of ~42K images can fail midway; must resume, not restart | LOW | `aws s3 sync` handles this natively; annotation CSVs are small enough to re-download |
| Data validation after load | Row counts should match source; spot-check known values | LOW | Compare `wc -l` of source CSV to Athena `COUNT(*)` per table |
| Clear execution instructions | Downstream team needs to reproduce the pipeline without guessing | LOW | README or inline script comments with prerequisites and step-by-step |

#### Query Surface

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Athena workgroup with cost controls | Athena charges per TB scanned; uncontrolled queries on poorly partitioned data get expensive fast | LOW | CDK creates workgroup with per-query and workgroup-level byte limits |
| JSON field parsing works in SQL | Masks and relationships have nested data stored as JSON strings; Athena must parse these | MEDIUM | Use Athena `json_extract` / `json_extract_scalar`; requires STRING column type with valid JSON |
| Example queries for each annotation type | Downstream team needs working SQL to validate the interface and build their MCP server | LOW | Provide 8-12 example queries covering single-table and cross-table patterns |
| Schema documentation | Column names, types, semantics, and source CSV mappings for every table | LOW | Critical for the downstream MCP team to write correct queries |

#### Infrastructure as Code

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| CDK provisions all AWS resources | S3 bucket, Glue database, Glue tables (Iceberg), Athena workgroup -- all from `cdk deploy` | MEDIUM | Iceberg tables in Glue require specific table properties (`table_type=ICEBERG`, `metadata_location`) |
| Teardown support | `cdk destroy` should clean up everything; no orphaned resources billing you | LOW | S3 bucket needs `autoDeleteObjects` + `removalPolicy: DESTROY` for clean teardown |

### Differentiators (Competitive Advantage)

Features that make this pipeline notably better than "just dump CSVs in S3 and query with Athena."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Iceberg table format (not raw CSV/Parquet) | Schema evolution, time travel, compaction -- future-proofs the dataset; downstream team can evolve queries without reloading | MEDIUM | The main reason to use Iceberg over plain Glue tables; worth the setup cost |
| Partitioning strategy for common query patterns | Partition images by first character of ImageID or by source (validation); reduces Athena scan costs 5-10x on filtered queries | MEDIUM | Iceberg hidden partitioning avoids the "partition column in WHERE" footgun of Hive-style tables |
| Denormalized convenience views | Pre-joined views like `images_with_labels`, `images_with_boxes_and_labels` save downstream team from writing complex JOINs every time | LOW | Create as Athena views (no data duplication); 3-4 views covering the most common join patterns |
| Segmentation mask decoding helpers | RLE-encoded masks stored as JSON; provide SQL UDFs or documented decode patterns so downstream can actually use mask data | HIGH | Athena does not have native RLE decode; may need to store pre-decoded mask metadata (bounding polygon, area) alongside raw RLE |
| Visual relationship queryability | "Find images where person rides horse" -- relationship triples (subject-predicate-object) as first-class queryable entities | MEDIUM | Relationship annotations have LabelName1, LabelName2, RelationshipLabel; join with class descriptions for human-readable queries |
| Cost estimation documentation | Document expected Athena costs per query pattern so downstream team can budget | LOW | At ~42K images, data is small (<1GB Parquet); most queries will cost fractions of a cent |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Image binary storage in S3 with Athena queries | "Query images directly" | Images are ~300GB for validation set; storing them doubles S3 cost, and Athena cannot process image bytes. The downstream MCP server can fetch images by URL on demand | Store only `OriginalURL` and `Thumbnail300KURL` in the image metadata table; downstream fetches as needed |
| Real-time / streaming pipeline | "Keep data fresh" | Open Images V7 is a static dataset -- there is no update stream. A streaming pipeline adds complexity for zero value | One-time batch load scripts; if V8 is released, re-run pipeline |
| Python/Spark ETL jobs (EMR/Glue ETL) | "More processing power" | 42K images of CSV annotation data is <500MB; shell scripts + AWS CLI handle this in minutes. EMR/Glue adds cost, infra, and debugging complexity | Shell scripts with `aws s3 sync` + Athena CTAS or INSERT INTO for transformations |
| Full dataset (train + test) support | "Completeness" | Train set is 9M images; pipeline, storage costs, and query times scale dramatically. Proves nothing that validation set does not | Build for validation set first; document what changes for full dataset scale-up (partitioning becomes essential, costs go from dollars to hundreds) |
| Custom visualization dashboard | "See results visually" | Out of scope; the downstream MCP server handles presentation. Building a dashboard duplicates effort and creates a maintenance burden | Provide SQL results; downstream team renders |
| Incremental / CDC pipeline | "Only load changes" | Static dataset has no changes. Incremental logic adds complexity (merge keys, dedup, watermarks) for a dataset that loads once | One-time load; Iceberg's time travel provides historical snapshots if you ever re-load |
| ML model inference in the pipeline | "Enrich annotations with custom models" | Scope creep; this is a data pipeline, not an ML platform. Adding inference couples the pipeline to model versions and GPU infrastructure | Store raw Open Images annotations only; downstream teams run their own inference |

## Feature Dependencies

```
[Class Descriptions Table]
    └──required by──> [Image Labels Table] (labels reference MID codes)
    └──required by──> [Bounding Boxes Table] (boxes reference MID codes)
    └──required by──> [Visual Relationships Table] (relationships reference MID codes)

[Image Metadata Table]
    └──required by──> [Image Labels Table] (FK: ImageID)
    └──required by──> [Bounding Boxes Table] (FK: ImageID)
    └──required by──> [Segmentation Masks Table] (FK: ImageID)
    └──required by──> [Visual Relationships Table] (FK: ImageID)

[Bounding Boxes Table]
    └──required by──> [Segmentation Masks Table] (masks reference MaskPath + box coordinates)

[S3 Bucket + Glue Catalog (CDK)]
    └──required by──> [All Iceberg Tables]
    └──required by──> [Athena Workgroup]
    └──required by──> [Data Load Scripts]

[All Iceberg Tables]
    └──required by──> [Convenience Views]
    └──required by──> [Example Queries]

[Schema Documentation]
    └──enhances──> [Example Queries]
    └──enhances──> [Convenience Views]
```

### Dependency Notes

- **Class Descriptions required by annotation tables:** Without the MID-to-name mapping, all annotation tables return opaque identifiers. Load class descriptions first.
- **Image Metadata required by all annotation tables:** ImageID is the universal foreign key. The images table must exist before annotation tables can be meaningfully joined.
- **Bounding Boxes required by Segmentation Masks:** In Open Images V7, segmentation masks are associated with specific bounding box annotations (via ImageID + LabelName + box coordinates). The masks table references box data.
- **CDK infrastructure required by everything:** S3 bucket, Glue database, and Athena workgroup must exist before any data loading or table creation.

## MVP Definition

### Launch With (v1)

Minimum viable: the downstream MCP team can write and execute SQL queries across all annotation types.

- [ ] CDK stack: S3 bucket, Glue database (Iceberg catalog), Athena workgroup with cost controls
- [ ] Image metadata Iceberg table (ImageID, OriginalURL, License, Author, dimensions)
- [ ] Class descriptions Iceberg table (MID to DisplayName mapping)
- [ ] Image labels Iceberg table (ImageID, LabelName/MID, Confidence, Source)
- [ ] Bounding boxes Iceberg table (ImageID, LabelName, XMin/XMax/YMin/YMax, IsOccluded, IsTruncated, IsGroupOf, IsDepiction, IsInside)
- [ ] Segmentation masks Iceberg table (ImageID, LabelName, BoxID/coordinates, MaskPath, predicted IoU -- mask RLE as JSON string column)
- [ ] Visual relationships Iceberg table (ImageID, LabelName1, LabelName2, RelationshipLabel, box coordinates for both objects)
- [ ] Shell scripts: download annotations from GCS, download images list, load into Iceberg via Athena INSERT
- [ ] 8-12 example SQL queries covering each table and cross-table joins
- [ ] Schema documentation (column reference for every table)

### Add After Validation (v1.x)

Features to add once the downstream team confirms the SQL interface works for their MCP server.

- [ ] Convenience views (pre-joined tables for common query patterns) -- trigger: downstream team reports writing same JOINs repeatedly
- [ ] Iceberg partitioning optimization -- trigger: Athena scan costs exceed expectations or query times are slow
- [ ] Mask metadata enrichment (pre-computed area, bounding polygon from RLE) -- trigger: downstream team needs mask geometry in SQL without client-side RLE decoding
- [ ] Label hierarchy table (parent-child relationships between classes) -- trigger: downstream team needs "find all animals" type hierarchical queries
- [ ] Query cost estimation guide -- trigger: downstream team asks about budgeting

### Future Consideration (v2+)

- [ ] Full dataset support (train + test sets) -- defer until validation pipeline is proven and cost model is understood
- [ ] Automated Iceberg compaction scheduling -- defer until table sizes warrant it (42K images produces small Parquet files)
- [ ] Point-in-time query documentation (Iceberg time travel) -- defer until there is a use case for historical snapshots

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| CDK infrastructure (S3, Glue, Athena) | HIGH | MEDIUM | P1 |
| Image metadata table | HIGH | LOW | P1 |
| Class descriptions table | HIGH | LOW | P1 |
| Image labels table | HIGH | LOW | P1 |
| Bounding boxes table | HIGH | LOW | P1 |
| Segmentation masks table | HIGH | MEDIUM | P1 |
| Visual relationships table | HIGH | MEDIUM | P1 |
| Download/load shell scripts | HIGH | MEDIUM | P1 |
| Example SQL queries | HIGH | LOW | P1 |
| Schema documentation | HIGH | LOW | P1 |
| Cross-table join examples | HIGH | LOW | P1 |
| JSON field parsing (masks, relationships) | HIGH | MEDIUM | P1 |
| Idempotent pipeline execution | MEDIUM | LOW | P1 |
| Athena cost controls (workgroup limits) | MEDIUM | LOW | P1 |
| Convenience views | MEDIUM | LOW | P2 |
| Partitioning strategy | MEDIUM | MEDIUM | P2 |
| Mask metadata enrichment | MEDIUM | HIGH | P2 |
| Label hierarchy table | LOW | LOW | P2 |
| Cost estimation docs | LOW | LOW | P2 |
| Full dataset support | LOW | HIGH | P3 |
| Iceberg compaction scheduling | LOW | MEDIUM | P3 |

## Comparable Systems Feature Analysis

| Feature | FiftyOne (Voxel51) | CVAT Dataset Export | Our Approach |
|---------|-------------------|---------------------|--------------|
| Annotation browsing | Python SDK + GUI, MongoDB backend | Export-oriented, no query interface | SQL-first via Athena; no GUI, no custom SDK |
| Multi-annotation-type support | Yes, all types unified in document model | Primarily bounding boxes + segmentation | All 4 Open Images types as separate Iceberg tables with JOIN capability |
| Query language | Python filter expressions | N/A (file export) | Standard SQL (Athena); accessible to anyone who knows SQL |
| Scalability | Limited by single MongoDB instance | File-based, scales with disk | S3 + Iceberg + Athena: serverless, scales to petabytes |
| Infrastructure requirements | Self-hosted or cloud service | Local tool | Fully managed AWS services; CDK deploy and done |
| Data format | Proprietary MongoDB documents | COCO JSON, PASCAL VOC XML | Open standard: Parquet + Iceberg; queryable by any tool that speaks SQL or reads Parquet |

## Sources

- Open Images V7 dataset documentation (storage.googleapis.com/openimages/web/) -- training data knowledge, HIGH confidence on dataset structure (stable since 2022)
- AWS Athena Iceberg documentation (docs.aws.amazon.com/athena/) -- training data knowledge, MEDIUM confidence (features verified through early 2025)
- Open Images V7 annotation format specifications -- training data knowledge, HIGH confidence (CSV schemas are well-documented and unchanged)

---
*Feature research for: Open Images V7 data pipeline to Athena/Iceberg*
*Researched: 2026-03-05*
