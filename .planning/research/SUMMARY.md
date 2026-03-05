# Research Summary: Open Images Athena Database

**Domain:** Data pipeline (GCS to S3) + analytical data lake (Iceberg/Athena)
**Researched:** 2026-03-05
**Overall confidence:** MEDIUM (web verification tools unavailable; relying on training data for versions, HIGH confidence on architecture patterns)

## Executive Summary

This project builds a one-time data pipeline that downloads Open Images V7 validation set (~42K images and all annotation CSVs) from Google Cloud Storage, stores everything in Amazon S3, transforms annotation data into Apache Iceberg tables (Parquet-backed), and exposes a SQL interface via Amazon Athena v3. The downstream consumer is an MCP server team that will build on top of the Athena SQL interface.

The stack is constrained and well-defined: AWS CDK (TypeScript) for infrastructure, shell scripts with AWS CLI for the one-time pipeline, Athena v3 as query engine, Glue Data Catalog as the Iceberg metastore. The critical technical decision is using Athena CTAS (CREATE TABLE AS SELECT) to transform CSV data into Iceberg tables, eliminating the need for Python, Spark, or any external transformation tooling. This keeps the stack minimal: CDK, shell, AWS CLI, and Athena SQL.

The architecture has a clean separation: CDK provisions infrastructure (S3 bucket, Glue database, Athena workgroup, IAM roles), while shell scripts handle data-plane operations (downloading data, creating Iceberg tables via Athena DDL, loading data via CTAS). This separation is not optional -- Iceberg tables cannot be properly created via CDK's Glue constructs.

The primary risks are around the GCS-to-S3 transfer (requester-pays bucket, CloudShell timeout limits) and getting Iceberg table schemas right on the first attempt (type coercion from CSV, JSON field handling, segmentation mask data being PNG files rather than inline CSV data).

## Key Findings

**Stack:** AWS CDK v2 (TypeScript) + Shell/AWS CLI pipeline + Athena v3 CTAS for CSV-to-Iceberg transformation. No Python, no Spark, no Glue ETL.

**Architecture:** Four-phase pipeline (infra deploy, data download, Athena CTAS transformation, validation). CDK owns infrastructure, Athena DDL owns tables. Two-zone S3 layout (raw + warehouse).

**Critical pitfall:** Do NOT create Iceberg tables via CDK CfnTable -- they must be created via Athena DDL. This is the most common mistake and produces non-functional tables.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Infrastructure** - CDK stack provisioning S3, Glue DB, Athena workgroup, IAM
   - Addresses: All AWS resource provisioning, cost controls (workgroup scan limits)
   - Avoids: Premature table creation in CDK (Pitfall 7)
   - Deliverable: `cdk deploy` creates all infrastructure; outputs bucket name, database name, workgroup name

2. **Data Acquisition** - Shell scripts to download from GCS to S3
   - Addresses: Image download, annotation CSV download, raw data preservation
   - Avoids: CloudShell timeout (use EC2), GCS requester-pays errors (Pitfall 4)
   - Deliverable: All source data in S3 raw zone, verified file counts

3. **Schema Design + Table Creation** - Iceberg table DDL via Athena
   - Addresses: Table schemas for all 6 tables (images, class_descriptions, labels, bounding_boxes, masks, relationships)
   - Avoids: Type coercion errors (Pitfall 2), CSV header in data (Pitfall 3), JSON vs flat column decision (Pitfall 8)
   - Deliverable: All Iceberg tables created and populated via CTAS

4. **Validation + Query Library** - Data quality checks and example queries
   - Addresses: Row count validation, cross-table joins, JSON field parsing examples
   - Avoids: "Looks done but isn't" syndrome (silent data quality issues)
   - Deliverable: Validation script + 8-12 example SQL queries for downstream team

**Phase ordering rationale:**
- Infrastructure must precede everything (S3 bucket, Glue DB needed for all operations)
- Data must be in S3 before Athena can create external tables over it
- Schema design benefits from inspecting actual CSV data (downloaded in Phase 2)
- Validation confirms the end-to-end pipeline works before handing off to downstream team

**Research flags for phases:**
- Phase 2: Needs deeper research on exact GCS paths for V7 annotation files and requester-pays behavior
- Phase 3: Needs deeper research on segmentation mask data format (PNG files + CSV metadata)
- Phase 1 and 4: Standard patterns, unlikely to need additional research

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Core choices (CDK, Athena, Iceberg) are HIGH confidence. Exact version numbers not verified via web. |
| Features | HIGH | Open Images V7 schema is stable since 2022. Feature landscape well understood. |
| Architecture | HIGH | CDK-for-infra + Athena-DDL-for-tables is the established AWS pattern. |
| Pitfalls | MEDIUM | Pitfalls are based on well-known patterns, but GCS requester-pays behavior and Athena v3 edge cases should be verified. |

## Gaps to Address

- **Exact GCS paths for V7 validation annotations:** File names may differ between V6 and V7. Verify on the Open Images download page before writing download scripts.
- **Segmentation mask PNG format:** Need to inspect the actual mask directory structure in GCS to design the download and table schema correctly.
- **CDK version pinning:** `aws-cdk-lib` version should be checked at project init time. Research used ~2.170+ as estimate.
- **Athena CTAS behavior with CSV header rows:** Verify that `skip.header.line.count` works correctly with the OpenCSVSerDe or LazySimpleSerDe in Athena v3.
- **GCS requester-pays for Open Images:** Verify whether the Open Images bucket still requires requester-pays authentication or if public anonymous access works.
