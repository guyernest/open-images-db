# Open Images Athena

A fully queryable SQL interface over [Open Images V7](https://storage.googleapis.com/openimages/web/index.html) annotations, built on Amazon Athena with Apache Iceberg tables.

The pipeline downloads the Open Images V7 validation set (~42,000 images), loads it into S3, creates typed Iceberg tables in Athena, and builds convenience views that join annotations with human-readable class names. The result is 7 tables and 4 views you can query with standard SQL.

## What's Included

| Component | Description |
|-----------|-------------|
| **7 Iceberg tables** | images, class_descriptions, labels, bounding_boxes, masks, relationships, label_hierarchy |
| **4 convenience views** | labeled_images, labeled_boxes, labeled_masks, labeled_relationships |
| **Validation script** | Row count verification + spot-checks against live data |
| **12 example queries** | Single-table, cross-table joins, and string field parsing |
| **Schema docs** | Column types, semantics, and source CSV mapping for every table and view |

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| AWS CLI | v2 | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Node.js | 18+ | [nodejs.org](https://nodejs.org/) |
| jq | any | `brew install jq` |
| curl | any | Pre-installed on macOS/Linux |

Configure your AWS profile:

```bash
aws configure --profile ze-kasher-dev
```

## Setup

### 1. Deploy infrastructure

```bash
cd infra && npm install && npx cdk deploy --profile ze-kasher-dev && cd ..
```

This creates the S3 bucket, Athena workgroup (`open-images`), Glue database (`open_images`), and IAM policy.

### 2. Download data

```bash
bash scripts/download-all.sh
```

Downloads annotation CSVs, image metadata, and ~24,730 segmentation mask PNGs to S3. See [scripts/README.md](scripts/README.md) for options (`--skip-masks`, `--validate-only`, etc.).

### 3. Create tables

```bash
bash scripts/create-tables.sh
```

Creates raw external tables (CSV-backed) and typed Iceberg tables (Parquet/Snappy) via CTAS.

### 4. Create views

```bash
bash scripts/create-views.sh
```

Creates 4 convenience views that join annotations with class descriptions for human-readable labels.

### 5. Validate

```bash
bash scripts/validate-data.sh
```

Verifies row counts match between raw and Iceberg tables, and spot-checks value ranges across all annotation types.

## Querying

All queries target the `open_images` database in the `open-images` workgroup:

```sql
-- Find images labeled "Dog" with bounding boxes
SELECT image_id, display_name, x_min, y_min, x_max, y_max
FROM open_images.labeled_boxes
WHERE display_name = 'Dog'
LIMIT 10;

-- Count annotations by type
SELECT source, COUNT(*) as label_count
FROM open_images.labels
GROUP BY source;
```

See [docs/examples.md](docs/examples.md) for 12 example queries and [docs/SCHEMA.md](docs/SCHEMA.md) for full schema documentation.

## Project Structure

```
infra/              CDK infrastructure (S3, Athena, Glue, IAM)
scripts/
  download-all.sh   Download Open Images data to S3
  create-tables.sh  Create raw external + Iceberg tables
  create-views.sh   Create convenience views
  validate-data.sh  Verify data quality
  verify-tables.sh  Verify table structure
  verify-views.sh   Verify view structure
  lib/
    common.sh       Shared logging, prerequisites, bucket discovery
    athena.sh       Athena query execution helpers
queries/
  tables/           7 table DDL files (CREATE EXTERNAL + CTAS)
  views/            4 view SQL files (CREATE OR REPLACE VIEW)
docs/
  SCHEMA.md         Column-level schema documentation
  examples.md       12 example SQL queries
```

## Verification Scripts

| Script | Purpose |
|--------|---------|
| `verify-tables.sh` | Confirms all 7 Iceberg tables exist with correct columns |
| `verify-views.sh` | Confirms all 4 views exist and return rows |
| `validate-data.sh` | Row count matching + spot-check value validation |
| `validate-data.sh --quick` | Row counts only (skips spot-checks) |

## License

Open Images V7 annotations are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Images have individual licenses listed in the `images` table.
