# Open Images V7 Data Pipeline

Downloads Open Images V7 annotation CSVs and creates Athena/Iceberg tables for querying. Supports both the validation subset (~42K images) and the full dataset (~1.9M images across train/validation/test splits).

Images are served directly from the [CVDF public S3 bucket](https://github.com/cvdfoundation/open-images-dataset) — no image copying needed.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| AWS CLI | v2 | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| jq | any | `brew install jq` or [download](https://jqlang.github.io/jq/download/) |
| just | any | `brew install just` or [install guide](https://github.com/casey/just#installation) |
| curl | any | Pre-installed on macOS/Linux |

### AWS Configuration

Configure AWS credentials using your preferred method:

```bash
# Option 1: assume (recommended)
assume <profile-name>

# Option 2: environment variable
export AWS_PROFILE=<profile-name>

# Option 3: default credentials
aws configure
```

Deploy the CDK stack (creates S3 bucket, Glue databases, Athena workgroup, EC2 instance profile):

```bash
just deploy
```

## Quick Start

### Full Dataset (1.9M images, recommended)

```bash
# 1. Deploy infrastructure (one-time)
just deploy

# 2. Download annotations on EC2 (~4 min, self-terminates)
just launch-full-load

# 3. Monitor EC2 progress
just instance-status <instance-id>
just console-output <instance-id>

# 4. Create Iceberg tables in open_images_full database (~30 min)
just create-tables-full

# 5. Create views (~1 min)
just create-views-full

# 6. Verify
just verify-tables-full
just verify-cvdf-url
```

### Validation Subset Only (~42K images)

```bash
# Download annotations locally
just download-all

# Create tables + views in open_images database
just create-tables
just create-views
```

## Databases

The pipeline creates two Glue databases in the same S3 bucket:

| Database | Images | Description | Warehouse Prefix |
|----------|--------|-------------|-----------------|
| `open_images` | 41,620 | Validation split only | `warehouse/` |
| `open_images_full` | 1,931,630 | All splits (train + val + test) | `warehouse-full/` |

Both share the same Athena workgroup (`open-images`) and S3 bucket. The MCP server can point to either database.

## Image Access

Images are **not** stored in our S3 bucket. They are served directly from the CVDF public bucket:

```
https://open-images-dataset.s3.amazonaws.com/{split}/{image_id}.jpg
```

The `images` Iceberg table includes a `cvdf_url` derived column with the full URL for each image. This replaces the Flickr URLs (`original_url`) which break over time as users delete photos.

## Tables (7)

| Table | Full Count | Description |
|-------|-----------|-------------|
| `images` | 1,931,630 | Image metadata + cvdf_url + rotation |
| `class_descriptions` | 20,931 | Class taxonomy (label_name → display_name) |
| `labels` | 228,956,112 | Human + machine image-level labels |
| `bounding_boxes` | 15,851,536 | Object detection boxes with confidence |
| `masks` | 2,785,498 | Segmentation mask metadata |
| `relationships` | 3,284,280 | Visual relationships (subject-predicate-object) |
| `label_hierarchy` | 847 | Class hierarchy edges (parent → child) |

## Views (9)

| View | Description |
|------|-------------|
| `labeled_images` | Images + labels + class names (includes cvdf_url) |
| `labeled_boxes` | Bounding boxes + images + class names + geometry |
| `labeled_masks` | Masks + images + class names + click counts |
| `labeled_relationships` | Relationships with both entity names resolved |
| `class_hierarchy` | Recursive hierarchy with depth, root_path, is_leaf |
| `hierarchy_relationships` | Relationships expanded through ancestor hierarchy |
| `entity_image_counts` | Pre-computed image count per entity (~601 rows) |
| `relationship_summary` | Pre-aggregated relationship triples with counts |
| `class_hierarchy_resolved` | Hierarchy edges with display names (~600 rows) |

## Just Recipes

```bash
just                      # Show all available recipes

# Infrastructure
just deploy               # Deploy CDK stack

# Validation subset
just download-all         # Download validation annotations
just create-tables        # Create tables in open_images
just create-views         # Create views in open_images
just dry-run-tables       # Dry-run table creation

# Full dataset
just launch-full-load     # Launch EC2 for annotation download
just create-tables-full   # Create tables in open_images_full
just create-views-full    # Create views in open_images_full
just dry-run-tables-full  # Dry-run full table creation
just verify-tables-full   # Verify row counts
just verify-cvdf-url      # Check sample image URL resolves

# EC2 monitoring
just instance-status <id> # Check instance state
just console-output <id>  # View script logs
just console-output-raw <id>  # Full console output
just list-instances       # List all open-images EC2 instances
```

## Cost

### Full Dataset

| Component | One-time | Monthly |
|-----------|----------|---------|
| EC2 (annotation download, ~4 min) | ~$0.02 | — |
| S3 (annotation Parquet, ~5 GB) | — | ~$0.12 |
| Images | **$0** | **$0** (served from CVDF) |
| **Total** | **~$0.10** | **~$0.12** |

## Idempotency

All pipeline steps are safe to re-run:

- **Downloads:** `curl -z` only re-downloads if remote file is newer
- **S3 uploads:** `aws s3 sync` skips unchanged files
- **Table creation:** `DROP TABLE IF EXISTS` before `CREATE`
- **View creation:** `CREATE OR REPLACE VIEW`

## Troubleshooting

### "AWS credentials not configured"

```bash
# Check current credentials
aws sts get-caller-identity

# Set credentials
assume <profile-name>
# or
export AWS_PROFILE=<profile-name>
```

### "Could not discover bucket from stack"

Deploy the CDK stack first:

```bash
just deploy
```

Or bypass discovery:

```bash
bash scripts/create-tables.sh --bucket your-bucket-name
```

### EC2 instance terminates immediately

Check console output (may take a few minutes to appear):

```bash
just console-output <instance-id>
```

Common causes:
- `$HOME` unbound in cloud-init → fixed in current scripts
- `curl` conflicts with `curl-minimal` on AL2023 → removed from dnf install
- Instance profile missing → run `just deploy` first
