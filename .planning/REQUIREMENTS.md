# Requirements: Open Images Athena Database

**Defined:** 2026-03-05
**Core Value:** A fully queryable SQL interface over Open Images V7 annotations via Athena/Iceberg

## v1 Requirements

### Infrastructure

- [x] **INFRA-01**: CDK stack provisions S3 bucket with two-zone layout (raw/ and warehouse/)
- [x] **INFRA-02**: CDK stack provisions Glue database configured as Iceberg catalog
- [x] **INFRA-03**: CDK stack provisions Athena workgroup with per-query scan cost limits
- [x] **INFRA-04**: CDK stack supports clean teardown via `cdk destroy` (auto-delete objects, removal policy)
- [x] **INFRA-05**: CDK stack provisions necessary IAM roles for Athena-to-S3 and Glue access

### Data Acquisition

- [x] **DATA-01**: Shell script downloads Open Images V7 validation set annotation CSVs from GCS to S3 raw zone
- [x] **DATA-02**: Shell script downloads validation image list/metadata from GCS to S3 raw zone
- [x] **DATA-03**: Shell script downloads segmentation mask PNGs from GCS to S3 raw zone
- [x] **DATA-04**: Pipeline scripts are idempotent (safe to re-run without data corruption or duplication)
- [x] **DATA-05**: Pipeline scripts handle GCS requester-pays authentication correctly
- [x] **DATA-06**: Pipeline scripts include clear execution instructions (prerequisites, step-by-step)

### Iceberg Tables

- [x] **TBL-01**: Image metadata Iceberg table (ImageID, OriginalURL, License, Author, dimensions, rotation)
- [x] **TBL-02**: Class descriptions Iceberg table (MID to DisplayName mapping)
- [x] **TBL-03**: Image labels Iceberg table (ImageID, LabelName/MID, Confidence, Source)
- [x] **TBL-04**: Bounding boxes Iceberg table (ImageID, LabelName, XMin/XMax/YMin/YMax, IsOccluded, IsTruncated, IsGroupOf, IsDepiction, IsInside)
- [x] **TBL-05**: Segmentation masks Iceberg table (ImageID, LabelName, BoxID/coordinates, MaskPath, predicted IoU, mask metadata as JSON)
- [x] **TBL-06**: Visual relationships Iceberg table (ImageID, LabelName1, LabelName2, RelationshipLabel, box coordinates for both objects)
- [x] **TBL-07**: Label hierarchy Iceberg table (parent-child class relationships for hierarchical queries)
- [x] **TBL-08**: All Iceberg tables created via Athena DDL (not CDK Glue constructs)
- [x] **TBL-09**: CSV data transformed to Iceberg/Parquet via Athena CTAS with correct type casting
- [x] **TBL-10**: JSON-typed string columns parseable by Athena `json_extract` functions where annotation data has nested structure

### Convenience Views

- [ ] **VIEW-01**: Athena view joining images with human-readable labels (images + labels + class descriptions)
- [ ] **VIEW-02**: Athena view joining images with bounding boxes and label names
- [ ] **VIEW-03**: Athena view joining images with segmentation masks and label names
- [ ] **VIEW-04**: Athena view joining images with visual relationships and label names

### Mask Enrichment

- [ ] **MASK-01**: Pre-computed mask metadata (area, bounding polygon) stored alongside raw RLE data for SQL-queryable mask geometry

### Validation

- [ ] **VAL-01**: Row count validation comparing source CSVs to Iceberg table counts
- [ ] **VAL-02**: Spot-check validation of known values across tables

### Query Surface

- [ ] **QUERY-01**: 8-12 example SQL queries covering single-table queries for each annotation type
- [ ] **QUERY-02**: Example SQL queries demonstrating cross-table joins (e.g., find images with specific label AND bounding box)
- [ ] **QUERY-03**: Example SQL queries demonstrating JSON field parsing for mask and relationship data
- [ ] **QUERY-04**: Schema documentation with column names, types, semantics, and source CSV mapping for every table

## v2 Requirements

### Scale

- **SCALE-01**: Support for full Open Images dataset (train + test sets, ~9M images)
- **SCALE-02**: Iceberg partitioning optimization for large-scale query performance
- **SCALE-03**: Automated Iceberg compaction scheduling

### Documentation

- **DOC-01**: Cost estimation guide for downstream team (expected Athena costs per query pattern)
- **DOC-02**: Point-in-time query documentation (Iceberg time travel)

## Out of Scope

| Feature | Reason |
|---------|--------|
| MCP server | Built by another team consuming this SQL interface |
| Image binary storage in S3 | Images are ~300GB; Athena can't process image bytes. Store URLs only |
| Streaming/CDC pipeline | Open Images V7 is a static dataset -- no update stream |
| Python/Spark ETL (EMR/Glue ETL) | 42K images of CSV data is <500MB; shell + Athena CTAS sufficient |
| Custom visualization dashboard | Downstream MCP server handles presentation |
| ML model inference | This is a data pipeline, not an ML platform |
| Image download to S3 | Only metadata and annotations stored; images referenced by URL |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-04 | Phase 1 | Complete |
| INFRA-05 | Phase 1 | Complete |
| DATA-01 | Phase 2 | Complete |
| DATA-02 | Phase 2 | Complete |
| DATA-03 | Phase 2 | Complete |
| DATA-04 | Phase 2 | Complete |
| DATA-05 | Phase 2 | Complete |
| DATA-06 | Phase 2 | Complete |
| TBL-01 | Phase 3 | Complete |
| TBL-02 | Phase 3 | Complete |
| TBL-03 | Phase 3 | Complete |
| TBL-04 | Phase 3 | Complete |
| TBL-05 | Phase 3 | Complete |
| TBL-06 | Phase 3 | Complete |
| TBL-07 | Phase 3 | Complete |
| TBL-08 | Phase 3 | Complete |
| TBL-09 | Phase 3 | Complete |
| TBL-10 | Phase 3 | Complete |
| VIEW-01 | Phase 4 | Pending |
| VIEW-02 | Phase 4 | Pending |
| VIEW-03 | Phase 4 | Pending |
| VIEW-04 | Phase 4 | Pending |
| MASK-01 | Phase 4 | Pending |
| VAL-01 | Phase 5 | Pending |
| VAL-02 | Phase 5 | Pending |
| QUERY-01 | Phase 5 | Pending |
| QUERY-02 | Phase 5 | Pending |
| QUERY-03 | Phase 5 | Pending |
| QUERY-04 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 32 total
- Mapped to phases: 32
- Unmapped: 0

---
*Requirements defined: 2026-03-05*
*Last updated: 2026-03-05 after roadmap creation*
