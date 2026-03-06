# Open Images Athena Database

## What This Is

A complete data pipeline and SQL interface over the Open Images V7 validation set (~42K images). Downloads annotation data from Google Cloud Storage into Amazon S3, transforms it into 7 Apache Iceberg tables (Parquet-backed) with 4 convenience views, and provides a validated query surface via Amazon Athena. Built for downstream teams to build MCP servers for image/video dataset exploration.

## Core Value

A fully queryable SQL interface over Open Images annotations — labels, bounding boxes, segmentation masks, and visual relationships — that returns accurate, fast results with human-readable class names via convenience views.

## Requirements

### Validated

- Download and store all annotation CSVs and metadata — v1.0
- Download segmentation mask PNGs to S3 — v1.0
- Provision S3, Glue/Iceberg, Athena, IAM via CDK — v1.0
- 7 Iceberg tables with correct type casting via Athena CTAS — v1.0
- 4 convenience views with human-readable labels — v1.0
- Pre-computed mask geometry (area, bounding box, click count) — v1.0
- Data validation (row counts + spot-checks) — v1.0
- 12 example SQL queries covering all annotation types — v1.0
- Schema documentation with source CSV mapping — v1.0

### Active

(None — next milestone TBD)

### Out of Scope

- MCP server — built by another team consuming this SQL interface
- Full Open Images dataset (train/test) — validation set only for v1.0
- Image processing/ML inference — just storage and metadata querying
- Ongoing data sync — one-time load, not a recurring pipeline
- Custom UI/dashboard — SQL interface only

## Context

Shipped v1.0 with ~3,500 LOC across Bash, SQL, and TypeScript.
Tech stack: AWS CDK (TypeScript), Bash + AWS CLI, Athena SQL, Apache Iceberg/Parquet.
7 Iceberg tables, 4 views, 6 shell scripts, 11 SQL files.
All 32 v1 requirements validated. Row counts match exactly across all tables.

## Constraints

- **IaC**: AWS CDK with TypeScript
- **Pipeline scripts**: Shell + AWS CLI
- **Storage format**: Apache Iceberg tables backed by Parquet with Snappy compression
- **Dataset scope**: Validation set only (~42K images)
- **AWS services**: S3, Glue Data Catalog, Athena

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Iceberg + Parquet over raw CSV | Columnar format is faster for Athena scans, Iceberg adds schema evolution and time travel | Good — COUNT(*) is metadata-only, queries are fast |
| Validation set only | Proves pipeline at manageable scale before full 9M image dataset | Good — pipeline proven, ready to scale |
| Shell scripts over Python | One-time pipeline doesn't justify Python complexity | Good — simple, maintainable, idempotent |
| Athena CTAS for type casting | Creates typed Iceberg tables from raw CSV external tables | Good — clean separation of raw and typed data |
| INNER JOIN for views | Views join with class_descriptions; drops ~3.3% of relationships rows | Good — accepted tradeoff, documented |
| Clicks as VARCHAR not JSON | Semicolon-delimited, not JSON; parsed with split()/cardinality() | Good — matches actual data format |
| curl over gsutil | Public HTTPS URLs need no GCS auth | Good — simpler prerequisites |

---
*Last updated: 2026-03-06 after v1.0 milestone*
