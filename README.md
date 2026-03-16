# Open Images Athena

A fully queryable SQL interface over [Open Images V7](https://storage.googleapis.com/openimages/web/index.html) annotations, built on Amazon Athena with Apache Iceberg tables.

Supports two modes:
- **Full dataset** (~1.9M images, all splits) — annotations downloaded via EC2, images served from [CVDF public bucket](https://github.com/cvdfoundation/open-images-dataset)
- **Validation subset** (~42K images) — annotations downloaded locally

## What's Included

| Component | Description |
|-----------|-------------|
| **7 Iceberg tables** | images, class_descriptions, labels, bounding_boxes, masks, relationships, label_hierarchy |
| **9 convenience views** | labeled_images, labeled_boxes, labeled_masks, labeled_relationships, class_hierarchy, hierarchy_relationships, entity_image_counts, relationship_summary, class_hierarchy_resolved |
| **2 Glue databases** | `open_images` (validation only) and `open_images_full` (all splits) |
| **Justfile recipes** | One-command pipeline orchestration for all steps |

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| AWS CLI | v2 | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Node.js | 18+ | [nodejs.org](https://nodejs.org/) |
| jq | any | `brew install jq` |
| just | any | `brew install just` or [install guide](https://github.com/casey/just#installation) |

Configure AWS credentials:

```bash
assume <profile-name>
# or: export AWS_PROFILE=<profile-name>
```

## Full Dataset (Recommended)

Loads all 1.9M images across train/validation/test splits into the `open_images_full` database. Images are served directly from the CVDF public S3 bucket — no image copying needed.

```bash
# 1. Deploy infrastructure (one-time)
just deploy

# 2. Download annotation CSVs on EC2 (~4 min, self-terminates)
just launch-full-load

# 3. Monitor EC2 progress
just instance-status <instance-id>
just console-output <instance-id>

# 4. Create Iceberg tables (~30 min)
just create-tables-full

# 5. Create views (~1 min)
just create-views-full

# 6. Verify
just verify-tables-full
just verify-cvdf-url
```

### Full Dataset Table Counts

| Table | Rows |
|-------|------|
| images | 1,931,630 |
| class_descriptions | 20,931 |
| labels | 228,956,112 |
| bounding_boxes | 15,851,536 |
| masks | 2,785,498 |
| relationships | 3,284,280 |
| label_hierarchy | 847 |

### Cost

| Component | One-time | Monthly |
|-----------|----------|---------|
| EC2 annotation download (~4 min) | ~$0.02 | — |
| S3 annotation storage (~5 GB) | — | ~$0.12 |
| Image storage | **$0** | **$0** (CVDF bucket) |
| **Total** | **~$0.10** | **~$0.12** |

## Validation Subset Only

Loads only the validation split (~42K images) into the `open_images` database. Runs locally — no EC2 needed.

```bash
# 1. Deploy infrastructure (one-time)
just deploy

# 2. Download annotations locally
just download-all

# 3. Create tables + views
just create-tables
just create-views
```

## Image Access

Images are **not** stored in our S3 bucket. They are served directly from the CVDF public bucket:

```
https://open-images-dataset.s3.amazonaws.com/{split}/{image_id}.jpg
```

The `images` table includes a `cvdf_url` derived column with the direct URL for each image. This replaces the Flickr URLs (`original_url`) which break over time as users delete photos.

## Querying

```sql
-- Find images labeled "Dog" with bounding boxes
SELECT li.image_id, li.display_name, li.cvdf_url
FROM open_images_full.labeled_images li
WHERE li.display_name = 'Dog'
LIMIT 10;

-- Count annotations by type
SELECT source, COUNT(*) as label_count
FROM open_images_full.labels
GROUP BY source;

-- Relationship search
SELECT subject_name, predicate, object_name, occurrence_count
FROM open_images_full.relationship_summary
WHERE subject_name = 'Person'
ORDER BY occurrence_count DESC
LIMIT 10;
```

See [docs/examples.md](docs/examples.md) for more queries and [docs/SCHEMA.md](docs/SCHEMA.md) for full schema documentation.

## Just Recipes

```
just                        Show all available recipes

Infrastructure:
  just deploy               Deploy CDK stack

Validation subset:
  just download-all         Download validation annotations locally
  just create-tables        Create tables in open_images
  just create-views         Create views in open_images

Full dataset:
  just launch-full-load     Download annotations on EC2 (~4 min)
  just create-tables-full   Create tables in open_images_full
  just create-views-full    Create views in open_images_full
  just verify-tables-full   Verify row counts
  just verify-cvdf-url      Check image URL resolves

EC2 monitoring:
  just instance-status <id> Check instance state
  just console-output <id>  View script logs
  just list-instances       List all instances
```

## Project Structure

```
infra/                CDK infrastructure (S3, Athena, Glue, IAM, EC2 profile)
scripts/
  launch-pipeline.sh  Launch EC2 for annotation download
  ec2-userdata-full-load.sh  EC2 bootstrap (full dataset)
  download-all.sh     Download validation data locally
  create-tables.sh    Create tables (validation)
  create-tables-full.sh  Create tables (full dataset, warehouse-full/)
  create-views.sh     Create views (validation)
  create-views-full.sh   Create views (full dataset)
  lib/
    common.sh         Logging, prerequisites, bucket discovery
    athena.sh         Athena query execution helpers
    download-annotations-full.sh  Full dataset annotation URLs
    reorganize-raw.sh       Validation CSV reorganization
    reorganize-raw-full.sh  Full dataset CSV reorganization
queries/
  tables/             7 table DDL files (CREATE EXTERNAL + CTAS)
  views/              9 view SQL files (CREATE OR REPLACE VIEW)
docs/
  full-dataset-evaluation.md  Cost/time analysis for full load
  SCHEMA.md           Column-level schema documentation
  examples.md         Example SQL queries
justfile              Pipeline orchestration recipes
```

## License

Open Images V7 annotations are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Images have individual licenses listed in the `images` table.
