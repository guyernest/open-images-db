# Architecture Research

**Domain:** Data pipeline (GCS to S3) + analytical data lake (Iceberg/Athena)
**Researched:** 2026-03-05
**Confidence:** HIGH

## System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Source Layer (GCS)                            │
│  ┌──────────────┐  ┌──────────────────────────────────────────────┐  │
│  │  Images       │  │  Annotation CSVs (labels, boxes, masks,     │  │
│  │  (JPEG, ~42K) │  │  relationships, class descriptions)         │  │
│  └──────┬───────┘  └──────────────┬───────────────────────────────┘  │
│         │                         │                                  │
└─────────┼─────────────────────────┼──────────────────────────────────┘
          │  gsutil / gcloud        │  curl / wget
          ▼                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Pipeline Layer (Shell Scripts)                    │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐  │
│  │  download.sh │  │ transform.sh │  │  load.sh                  │  │
│  │  GCS → local │  │ CSV → Parquet│  │  Parquet → S3 + register  │  │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬───────────────┘  │
│         │                 │                        │                  │
└─────────┼─────────────────┼────────────────────────┼─────────────────┘
          ▼                 ▼                        ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      Storage Layer (S3)                              │
│  ┌────────────────────┐  ┌─────────────────────────────────────────┐ │
│  │  Raw Zone           │  │  Iceberg Zone                          │ │
│  │  s3://bucket/raw/   │  │  s3://bucket/warehouse/                │ │
│  │  ├── images/        │  │  ├── images/        (Parquet + meta)   │ │
│  │  ├── annotations/   │  │  ├── labels/        (Parquet + meta)   │ │
│  │  │   ├── labels.csv │  │  ├── boxes/         (Parquet + meta)   │ │
│  │  │   ├── boxes.csv  │  │  ├── masks/         (Parquet + meta)   │ │
│  │  │   ├── masks.csv  │  │  └── relationships/ (Parquet + meta)   │ │
│  │  │   └── rels.csv   │  │                                        │ │
│  │  └── metadata/      │  │  Each table has:                       │ │
│  │      └── classes.csv │  │    data/   (Parquet files)             │ │
│  └────────────────────┘  │    metadata/ (Iceberg manifests)        │ │
│                          └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
          │                                          │
          ▼                                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Catalog Layer (Glue Data Catalog)                  │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │  Database: open_images_v7                                      │   │
│  │  Tables: images, labels, bounding_boxes, masks, relationships  │   │
│  │  Table format: ICEBERG (managed by Glue)                       │   │
│  └────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Query Layer (Athena v3)                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐    │
│  │  Workgroup   │  │  Query       │  │  Results                 │    │
│  │  (cost ctrl) │  │  Engine v3   │  │  s3://bucket/athena-out/ │    │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────────────┐
│                   Consumer Layer (downstream)                        │
│  ┌──────────────────────────────────────────────────────────────┐     │
│  │  MCP Server (out of scope — consumes SQL via Athena SDK)    │     │
│  └──────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| **Download Scripts** | Fetch images and annotation CSVs from GCS to local/S3 raw zone | Shell: `gsutil -m cp` for images, `curl`/`wget` for annotation CSVs (hosted at known URLs) |
| **Transform Scripts** | Convert CSV annotations to Parquet, handle JSON field encoding for nested data | Shell + a lightweight tool (DuckDB CLI or `aws athena` CTAS) |
| **Load Scripts** | Upload Parquet to S3 Iceberg warehouse paths, register tables in Glue catalog | Shell: `aws s3 cp` + Athena `CREATE TABLE` DDL |
| **S3 Raw Zone** | Store original source files as downloaded (immutable archive) | Single S3 bucket, `raw/` prefix |
| **S3 Iceberg Zone** | Store Parquet data files + Iceberg metadata (manifests, snapshots) | Same bucket, `warehouse/` prefix, Iceberg-managed layout |
| **Glue Data Catalog** | Iceberg metastore -- tracks table schemas, partition specs, current snapshots | CDK `CfnDatabase` + tables registered via Athena DDL |
| **Athena Workgroup** | Query engine with cost controls, engine version pinning, output location | CDK `CfnWorkGroup` with engine v3, byte scan limits |
| **CDK Stack** | Provision all AWS infrastructure as code | TypeScript CDK: S3 bucket, Glue database, Athena workgroup, IAM roles |

## Recommended Project Structure

```
open-images/
├── infra/                      # CDK application
│   ├── bin/
│   │   └── app.ts              # CDK app entry point
│   ├── lib/
│   │   ├── storage-stack.ts    # S3 bucket with lifecycle rules
│   │   ├── catalog-stack.ts    # Glue database, IAM for Athena/Glue
│   │   └── athena-stack.ts     # Athena workgroup, named queries
│   ├── cdk.json
│   ├── tsconfig.json
│   └── package.json
├── pipeline/                   # Data pipeline shell scripts
│   ├── 01-download-images.sh   # GCS → S3 raw zone (images)
│   ├── 02-download-annotations.sh  # Download annotation CSVs
│   ├── 03-transform.sh         # CSV → Parquet conversion
│   ├── 04-create-tables.sh     # Athena DDL to create Iceberg tables
│   ├── 05-load-data.sh         # INSERT INTO from staging or CTAS
│   ├── config.sh               # Shared variables (bucket, region, db name)
│   └── lib/
│       ├── download-helpers.sh # Retry logic, progress reporting
│       └── athena-helpers.sh   # Query execution, polling for results
├── sql/                        # SQL definitions and queries
│   ├── ddl/
│   │   ├── images.sql          # CREATE TABLE for images
│   │   ├── labels.sql          # CREATE TABLE for labels
│   │   ├── bounding_boxes.sql  # CREATE TABLE for bounding boxes
│   │   ├── masks.sql           # CREATE TABLE for segmentation masks
│   │   └── relationships.sql   # CREATE TABLE for visual relationships
│   └── queries/
│       ├── examples.sql        # Example queries for downstream consumers
│       └── validation.sql      # Data quality checks
└── docs/
    └── schema.md               # Table schemas and relationship documentation
```

### Structure Rationale

- **infra/:** Isolated CDK app with its own `package.json` -- keeps infrastructure dependencies separate from data pipeline concerns. Split into multiple stacks for independent deployment.
- **pipeline/:** Numbered scripts enforce execution order. A shared `config.sh` prevents hardcoded values. Helper libraries reduce duplication.
- **sql/:** DDL separated from queries. DDL files are the source of truth for table schemas. Query examples serve as documentation for downstream MCP server team.

## Architectural Patterns

### Pattern 1: Two-Zone S3 Layout (Raw + Warehouse)

**What:** Separate raw source files from Iceberg-managed warehouse data within the same bucket using prefixes.
**When to use:** Always for data pipelines. Raw zone preserves originals for reprocessing; warehouse zone is Iceberg-managed.
**Trade-offs:** Slightly more S3 storage cost, but enables re-running transforms without re-downloading. Single bucket simplifies CDK and IAM.

```
s3://open-images-data/
├── raw/                    # Immutable source files
│   ├── images/validation/  # Original JPEGs
│   ├── annotations/        # Original CSVs
│   └── metadata/           # Class descriptions, etc.
└── warehouse/              # Iceberg-managed
    └── open_images_v7.db/
        ├── images/
        │   ├── data/       # Parquet files
        │   └── metadata/   # Iceberg manifests
        ├── labels/
        ...
```

### Pattern 2: Athena-as-ETL for CSV-to-Iceberg

**What:** Use Athena itself to transform CSV to Iceberg tables via CTAS (CREATE TABLE AS SELECT) or external table + INSERT INTO. No separate ETL engine needed.
**When to use:** When data volumes are small enough that Athena query costs are negligible (~42K rows per CSV, pennies in scan costs).
**Trade-offs:** Avoids adding DuckDB/Spark/Glue ETL complexity. Athena handles the Parquet writing and Iceberg metadata automatically. Slightly slower than local tooling but eliminates a dependency.

```sql
-- Step 1: Create external table over raw CSV
CREATE EXTERNAL TABLE staging_labels (
  ImageID STRING,
  Source STRING,
  LabelName STRING,
  Confidence DOUBLE
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://bucket/raw/annotations/labels/';

-- Step 2: CTAS into Iceberg table
CREATE TABLE open_images_v7.labels
WITH (
  table_type = 'ICEBERG',
  format = 'PARQUET',
  location = 's3://bucket/warehouse/open_images_v7.db/labels/'
)
AS SELECT * FROM staging_labels;
```

### Pattern 3: CDK Stack Separation by Lifecycle

**What:** Split CDK into stacks by how often they change and their deployment dependencies.
**When to use:** When infrastructure has components with different lifecycles (storage is permanent, workgroup config changes occasionally).
**Trade-offs:** More files but safer deployments -- destroying a workgroup config does not risk the S3 bucket.

**Recommended split:**
- **StorageStack:** S3 bucket (deployed once, never destroyed)
- **CatalogStack:** Glue database, IAM roles (deployed once, rarely updated)
- **AthenaStack:** Workgroup, named queries (updated as queries evolve)

## Data Flow

### Pipeline Flow (One-Time Execution)

```
Open Images GCS                    AWS
─────────────────                  ─────────────────────────────────────

images/*.jpg ──────gsutil──────►  s3://bucket/raw/images/
                                       │
annotations/*.csv ──curl/wget──►  s3://bucket/raw/annotations/
                                       │
                                       ▼
                                  Athena: CREATE EXTERNAL TABLE
                                  (CSV-backed staging tables)
                                       │
                                       ▼
                                  Athena: CTAS → Iceberg tables
                                  (writes Parquet to warehouse/)
                                       │
                                       ▼
                                  Glue Data Catalog updated
                                  (Iceberg metadata registered)
                                       │
                                       ▼
                                  Tables queryable via Athena v3
```

### Query Flow (Ongoing)

```
MCP Server / User
    │
    ▼
Athena SDK (StartQueryExecution)
    │
    ▼
Athena v3 Engine
    ├── Reads Iceberg metadata from Glue Data Catalog
    ├── Plans scan using Iceberg manifest files
    ├── Reads only necessary Parquet files from S3
    └── Returns results to s3://bucket/athena-results/
    │
    ▼
GetQueryResults → JSON response to caller
```

### Key Data Flows

1. **Image download:** GCS validation images (`gsutil -m cp`) directly to S3 raw zone. No local staging needed if running on EC2/CloudShell with good bandwidth. For large batches, use `gsutil -m` for parallel transfers.

2. **Annotation download:** CSV files are downloadable from known URLs (e.g., `https://storage.googleapis.com/openimages/v7/oidv7-val-annotations-bbox.csv`). Small files (MBs), simple `curl` downloads.

3. **CSV to Iceberg:** Athena reads CSVs from raw zone via external tables, writes Parquet to warehouse zone via CTAS. Iceberg metadata (manifests, snapshots) auto-generated by Athena.

4. **JSON field handling:** Some fields (segmentation mask paths, relationship attributes) store structured data. Encode as JSON strings in Parquet. Athena's `json_extract()` / `json_extract_scalar()` parse at query time.

## Open Images V7 Data Model

Understanding the source data is critical for table design.

### Source CSV Files (Validation Set)

| File | Rows (~) | Key Columns | Notes |
|------|----------|-------------|-------|
| `oidv7-class-descriptions.csv` | ~20K | LabelName, DisplayName | Lookup table, shared across sets |
| `oidv7-val-annotations-human-imagelabels.csv` | ~550K | ImageID, LabelName, Confidence, Source | Image-level labels |
| `oidv7-val-annotations-bbox.csv` | ~300K | ImageID, LabelName, XMin, XMax, YMin, YMax, Confidence, IsOccluded, IsTruncated, IsGroupOf, IsDepiction, IsInside | Bounding box annotations |
| `validation-annotations-object-segmentation.csv` | ~var | ImageID, LabelName, BoxID, BoxXMin..., MaskPath, PredictedIoU | Segmentation masks with paths to mask PNGs |
| `oidv7-val-annotations-vrd.csv` | ~var | ImageID, LabelName1, LabelName2, RelationshipLabel, XMin1, XMax1, YMin1, YMax1, XMin2, XMax2, YMin2, YMax2 | Visual relationships between object pairs |

### Iceberg Table Design

**Five tables:**

1. **images** -- One row per image in the validation set
   - `image_id STRING` (PK), `original_url STRING`, `author STRING`, `license STRING`, `width INT`, `height INT`
   - Source: image metadata CSV or derived from image list

2. **class_descriptions** -- Lookup table for label codes
   - `label_name STRING` (PK), `display_name STRING`

3. **labels** -- Image-level classification labels
   - `image_id STRING`, `label_name STRING`, `confidence DOUBLE`, `source STRING`

4. **bounding_boxes** -- Object detection annotations
   - `image_id STRING`, `label_name STRING`, `x_min DOUBLE`, `x_max DOUBLE`, `y_min DOUBLE`, `y_max DOUBLE`, `confidence DOUBLE`, `is_occluded INT`, `is_truncated INT`, `is_group_of INT`, `is_depiction INT`, `is_inside INT`

5. **relationships** -- Visual relationships between objects
   - `image_id STRING`, `label_name_1 STRING`, `label_name_2 STRING`, `relationship_label STRING`, `x_min_1 DOUBLE`, ... (bbox coords for both objects)
   - Alternatively: store both bboxes as JSON for cleaner schema

6. **masks** (if segmentation data is included)
   - `image_id STRING`, `label_name STRING`, `box_id STRING`, `mask_path STRING`, `predicted_iou DOUBLE`, plus bbox coordinates

### Table Relationships

```
class_descriptions
    │
    │ label_name
    ▼
labels ◄──── image_id ────► images
bounding_boxes ◄── image_id ────► images
masks ◄──── image_id ────► images
relationships ◄── image_id ────► images
    │
    │ (label_name_1, label_name_2 → class_descriptions)
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Validation set (42K images) | Current architecture is fine. Athena scans are small. Single bucket, no partitioning needed. |
| Full dataset (9M images) | Partition Iceberg tables by a hash of `image_id` or by source subset (train/val/test). Consider Iceberg's hidden partitioning for auto-optimization. |
| Multiple dataset versions | Iceberg time travel handles schema evolution. Tag snapshots per data load. |

### Scaling Priorities

1. **First concern (if going to full dataset):** Partition bounding_boxes and labels tables -- they grow to tens of millions of rows. Iceberg bucket partitioning on `image_id` would help Athena prune scans.
2. **Second concern:** Image storage costs at 9M images. Consider S3 Intelligent-Tiering or Glacier for images not actively queried.

## Anti-Patterns

### Anti-Pattern 1: Using Glue ETL Jobs for Small Data

**What people do:** Spin up Glue Spark jobs to convert 10MB CSV files to Parquet.
**Why it's wrong:** Glue jobs have minimum 1 DPU billing (10-minute minimum), cold start overhead, and complex debugging. For ~42K rows this is like using a bulldozer to plant a flower.
**Do this instead:** Use Athena CTAS or DuckDB CLI. Both handle small CSV-to-Parquet conversions instantly at near-zero cost.

### Anti-Pattern 2: Storing Images in the Iceberg Warehouse Zone

**What people do:** Put raw image JPEGs under the Iceberg-managed prefix.
**Why it's wrong:** Iceberg manages its own file layout under the warehouse prefix. Mixing in non-Iceberg files creates confusion and can interfere with Iceberg's garbage collection (expire_snapshots).
**Do this instead:** Keep images in `raw/images/` and store only the S3 key/URL as a string column in the images Iceberg table.

### Anti-Pattern 3: One Monolithic CDK Stack

**What people do:** Put S3 bucket, Glue database, Athena workgroup, and IAM roles in a single stack.
**Why it's wrong:** A failed Athena workgroup update could trigger a rollback that destroys the S3 bucket (if not protected). Different components have different lifecycles.
**Do this instead:** Separate stacks with cross-stack references. At minimum, isolate the S3 bucket in its own stack with `removalPolicy: RETAIN`.

### Anti-Pattern 4: Running Pipeline Scripts from Local Machine

**What people do:** Download 42K images to a laptop, then re-upload to S3.
**Why it's wrong:** Double network transit. GCS-to-laptop-to-S3 is slow and bandwidth-wasteful.
**Do this instead:** Run scripts on CloudShell or an EC2 instance in the target region. `gsutil` can copy directly from GCS to S3 (via the machine's memory, not local disk) using `gsutil -m cp gs://... s3://...` with the S3 transfer plugin, or download to instance storage then `aws s3 cp` to the bucket.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Google Cloud Storage | `gsutil` CLI or direct HTTPS URLs | No GCS auth needed for Open Images (public bucket) |
| S3 | AWS CLI (`aws s3 cp/sync`) | Bucket must be in same region as Athena workgroup |
| Glue Data Catalog | Athena DDL creates catalog entries automatically | CDK provisions the database; tables created by pipeline scripts |
| Athena v3 | AWS CLI (`aws athena start-query-execution`) | Must poll `get-query-execution` for completion |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| CDK infra --> Pipeline scripts | Pipeline reads CDK outputs (bucket name, database name) via `aws cloudformation describe-stacks` or a shared config file | Pipeline depends on infra being deployed first |
| Pipeline scripts --> SQL DDL | Scripts execute SQL files via `aws athena start-query-execution` | SQL files are the source of truth for schemas |
| Athena --> MCP Server (downstream) | MCP server uses AWS SDK `@aws-sdk/client-athena` | Out of scope but influences: table naming conventions, query patterns, output format |

## Build Order (Dependencies)

The architecture implies a strict build order:

```
Phase 1: Infrastructure (CDK)
    ├── S3 bucket
    ├── Glue database
    ├── Athena workgroup
    └── IAM roles/policies
         │
         ▼
Phase 2: Data Acquisition (Shell Scripts)
    ├── Download annotation CSVs to S3 raw zone
    └── Download validation images to S3 raw zone
         │
         ▼
Phase 3: Table Creation + Data Loading
    ├── Create staging external tables (CSV-backed)
    ├── Create Iceberg tables via CTAS
    └── Drop staging tables (cleanup)
         │
         ▼
Phase 4: Validation + Query Library
    ├── Data quality checks (row counts, null checks)
    ├── Example queries (joins, JSON parsing)
    └── Documentation for downstream consumers
```

**Why this order:**
- Phase 1 must come first because everything else depends on the S3 bucket and Glue database existing.
- Phase 2 (download) must precede Phase 3 (table creation) because Athena external tables need data in S3 to read.
- Phase 3 is where the core value is created -- queryable Iceberg tables.
- Phase 4 validates the result and creates the interface contract for the downstream MCP server.

## Sources

- AWS Athena Iceberg integration documentation (training data, HIGH confidence -- Athena v3 + Iceberg is well-established since 2022)
- AWS CDK TypeScript patterns for S3, Glue, Athena (training data, HIGH confidence)
- Open Images V7 dataset structure from Google storage.googleapis.com/openimages (training data, MEDIUM confidence -- file names may have minor variations)
- Apache Iceberg table format specification for S3 layout (training data, HIGH confidence)

---
*Architecture research for: Open Images V7 data pipeline to Athena/Iceberg*
*Researched: 2026-03-05*
