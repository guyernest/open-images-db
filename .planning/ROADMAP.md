# Roadmap: Open Images Athena Database

## Overview

This roadmap delivers a fully queryable SQL interface over the Open Images V7 validation set. The pipeline progresses from AWS infrastructure provisioning through data acquisition from GCS, Iceberg table creation via Athena DDL, convenience views and mask enrichment, to a validated query surface with example SQL and schema documentation. Each phase delivers a coherent, verifiable capability that unblocks the next.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Infrastructure** - CDK stack provisions S3, Glue, Athena, and IAM resources
- [x] **Phase 2: Data Acquisition** - Shell scripts download all annotation data from GCS to S3 (completed 2026-03-05)
- [ ] **Phase 3: Iceberg Tables** - Athena DDL/CTAS creates and populates all Iceberg tables
- [ ] **Phase 4: Views and Enrichment** - Convenience views and pre-computed mask metadata
- [ ] **Phase 5: Validation and Query Surface** - Data quality checks, example queries, and schema docs

## Phase Details

### Phase 1: Infrastructure
**Goal**: All AWS resources exist and are ready to receive data and serve queries
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05
**Success Criteria** (what must be TRUE):
  1. `cdk deploy` completes successfully and creates S3 bucket with raw/ and warehouse/ prefixes
  2. Glue database exists and is configured as an Iceberg catalog
  3. Athena workgroup exists with per-query scan cost limits enforced
  4. `cdk destroy` removes all resources including bucket contents (no manual cleanup)
  5. IAM roles allow Athena to read/write S3 and access Glue catalog
**Plans**: 2 plans

Plans:
- [ ] 01-01-PLAN.md — CDK project init with TDD assertion tests + full stack implementation (S3, Glue, Athena, IAM)
- [ ] 01-02-PLAN.md — Deploy stack to AWS and verify resources in console

### Phase 2: Data Acquisition
**Goal**: All Open Images V7 validation annotation data is in S3 and ready for Athena to query
**Depends on**: Phase 1
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06
**Success Criteria** (what must be TRUE):
  1. All annotation CSVs (labels, boxes, segments, relationships) exist in S3 raw zone with correct file sizes
  2. Validation image metadata (image list with URLs, dimensions, rotation) exists in S3 raw zone
  3. Segmentation mask PNGs exist in S3 raw zone
  4. Running any download script a second time completes without data corruption or duplication
  5. A user can follow the execution instructions to run the pipeline from scratch on CloudShell or EC2
**Plans**: 2 plans

Plans:
- [ ] 02-01-PLAN.md — Shell scripts for downloading annotations, metadata, and masks from GCS to S3
- [ ] 02-02-PLAN.md — Run pipeline and verify all data in S3 raw zone

### Phase 3: Iceberg Tables
**Goal**: All annotation data is stored in queryable Iceberg tables with correct schemas and types
**Depends on**: Phase 2
**Requirements**: TBL-01, TBL-02, TBL-03, TBL-04, TBL-05, TBL-06, TBL-07, TBL-08, TBL-09, TBL-10
**Success Criteria** (what must be TRUE):
  1. Seven Iceberg tables exist in Glue catalog (images, class_descriptions, labels, bounding_boxes, masks, relationships, label_hierarchy)
  2. All tables were created via Athena DDL/CTAS (not CDK Glue constructs) and are backed by Parquet in the warehouse zone
  3. A simple SELECT query against each table returns rows with correct column names and types
  4. JSON-typed string columns in mask and relationship tables are parseable by Athena `json_extract` functions
  5. CSV source data was correctly type-cast (numerics are numeric, booleans are boolean, strings are strings)
**Plans**: 3 plans

Plans:
- [ ] 03-01-PLAN.md — Runner script, S3 reorganization, hierarchy flattener, and verification script
- [ ] 03-02-PLAN.md — SQL files for all 7 Iceberg tables (external + CTAS with type casting)
- [ ] 03-03-PLAN.md — Execute pipeline and verify all tables in Athena

### Phase 4: Views and Enrichment
**Goal**: Users can query pre-joined views with human-readable labels and SQL-queryable mask geometry
**Depends on**: Phase 3
**Requirements**: VIEW-01, VIEW-02, VIEW-03, VIEW-04, MASK-01
**Success Criteria** (what must be TRUE):
  1. A user can query a single view to get images with human-readable label names (not just MIDs)
  2. Bounding box, segmentation mask, and visual relationship views each join correctly with image and class description data
  3. Pre-computed mask metadata (area, bounding polygon) is queryable via SQL without external processing
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

### Phase 5: Validation and Query Surface
**Goal**: Data quality is verified and downstream teams have everything needed to build on the SQL interface
**Depends on**: Phase 4
**Requirements**: VAL-01, VAL-02, QUERY-01, QUERY-02, QUERY-03, QUERY-04
**Success Criteria** (what must be TRUE):
  1. Row counts in every Iceberg table match the source CSV line counts (minus headers)
  2. Spot-check queries return known correct values for specific ImageIDs across all tables
  3. 8-12 example SQL queries exist covering single-table queries for each annotation type, cross-table joins, and JSON field parsing
  4. Schema documentation exists with column names, types, semantics, and source CSV mapping for every table
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Infrastructure | 0/2 | Planning complete | - |
| 2. Data Acquisition | 2/2 | Complete   | 2026-03-05 |
| 3. Iceberg Tables | 2/3 | In Progress|  |
| 4. Views and Enrichment | 0/? | Not started | - |
| 5. Validation and Query Surface | 0/? | Not started | - |
