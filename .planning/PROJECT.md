# Open Images Athena Database

## What This Is

A data pipeline that downloads the Open Images V7 validation set (~42K images with all annotation types) from Google Cloud Storage into Amazon S3, transforms the annotations into Apache Iceberg tables (Parquet-backed), and exposes a rich SQL interface via Amazon Athena. This provides a queryable dataset for downstream teams to build MCP servers for image/video dataset exploration.

## Core Value

A fully queryable SQL interface over Open Images annotations — labels, bounding boxes, segmentation masks, and visual relationships — that returns accurate, fast results and supports JSON field parsing for complex annotation data.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Download Open Images V7 validation set images from GCS to S3
- [ ] Download and store all annotation CSVs (labels, boxes, segments, relationships)
- [ ] Transform annotation data to Parquet format
- [ ] Provision S3 bucket, Glue/Iceberg catalog, and Athena workgroup via CDK (TypeScript)
- [ ] Create Iceberg tables for images, labels, bounding boxes, segmentation masks, and visual relationships
- [ ] Support JSON-typed fields in Iceberg tables parseable by Athena SQL
- [ ] Shell scripts for one-time data download and load (runnable on CloudShell/EC2)
- [ ] Rich SQL query examples covering all annotation types
- [ ] Cross-table joins (e.g., find images with specific labels AND bounding boxes)

### Out of Scope

- MCP server — built by another team consuming this SQL interface
- Full Open Images dataset (train/test) — validation set only for now
- Image processing/ML inference — just storage and metadata querying
- Ongoing data sync — one-time load, not a recurring pipeline
- Custom UI/dashboard — SQL interface only

## Context

- Open Images V7 is hosted on Google Cloud Storage with images and CSV annotation files
- Validation set is ~42K images — manageable for proving the pipeline
- Four annotation types: image-level labels, bounding boxes, segmentation masks, visual relationships
- Downstream team will build an MCP server on top of the Athena SQL interface
- Apache Iceberg on AWS uses Glue Data Catalog as the metastore
- Athena v3 supports Iceberg tables natively with JSON parsing functions

## Constraints

- **IaC**: AWS CDK with TypeScript — all infrastructure provisioned as code
- **Pipeline scripts**: Shell + AWS CLI — simple, one-time execution on CloudShell or EC2
- **Storage format**: Apache Iceberg tables backed by Parquet with JSON fields
- **Dataset scope**: Validation set only (~42K images) to keep costs and time manageable
- **AWS services**: S3, Glue Data Catalog, Athena — no additional compute (EMR, Glue ETL jobs)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Iceberg + Parquet over raw CSV | Columnar format is faster for Athena scans, Iceberg adds table management (schema evolution, time travel) | — Pending |
| Validation set only | Proves pipeline at manageable scale before committing to full 9M image dataset | — Pending |
| Shell scripts over Python | One-time pipeline doesn't justify Python complexity; AWS CLI sufficient for GCS→S3 transfer and data loading | — Pending |
| JSON fields in Iceberg | Some annotation data (masks, relationships) has nested structure; Athena SQL can parse JSON natively | — Pending |

---
*Last updated: 2026-03-05 after initialization*
