# Technology Stack

**Project:** Open Images Athena Database
**Researched:** 2026-03-05
**Note:** Web search and npm verification tools were unavailable during research. Version numbers are based on training data (cutoff ~May 2025) and should be verified before use. Confidence adjusted accordingly.

## Recommended Stack

### Infrastructure as Code

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| AWS CDK v2 | ~2.170+ | All AWS resource provisioning | Project constraint. TypeScript-native IaC with L2 constructs for S3, Glue, Athena. Single dependency (`aws-cdk-lib`) ships all AWS modules. |
| TypeScript | ~5.5+ | CDK language | Project constraint. Type safety for CDK constructs, catches misconfiguration at compile time. |
| `constructs` | ~10.x | CDK construct base | Required peer dependency for aws-cdk-lib. |

**Confidence:** MEDIUM -- CDK v2 is stable and the right choice, but exact latest version not verified.

### Storage

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Amazon S3 | N/A (managed) | Image storage + Iceberg data/metadata | Only viable option for Athena-backed Iceberg tables. S3 is the data lake layer. |
| Apache Iceberg | v2 format | Table format over Parquet files | Project constraint. Schema evolution, time travel, partition evolution. Athena v3 has native Iceberg support. |
| Apache Parquet | N/A (underlying) | Columnar storage format | Iceberg's default file format. Columnar = fast analytical queries, excellent compression for annotation data. |

**Confidence:** HIGH -- these are well-established, unchanging choices.

### Query & Catalog

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Amazon Athena v3 | Engine v3 | SQL query engine | Project constraint. Native Iceberg support, JSON parsing functions (`json_extract`, `json_extract_scalar`), serverless pay-per-query. |
| AWS Glue Data Catalog | N/A (managed) | Iceberg metastore / catalog | Only supported Iceberg catalog for Athena. Stores table schemas, partition info, Iceberg metadata pointers. |

**Confidence:** HIGH -- Athena v3 + Glue Catalog is the standard (and only) path for Iceberg on Athena.

### Pipeline Scripts

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Bash/Shell | 5.x | Pipeline orchestration | Project constraint. Simple, one-time execution. No framework overhead for a run-once pipeline. |
| AWS CLI v2 | 2.x | S3 operations, Athena queries | `aws s3 cp/sync` for data transfer, `aws athena start-query-execution` for DDL/DML. Already available on CloudShell/EC2. |
| `gsutil` or `gcloud storage` | latest | Download from GCS | Required for GCS access. `gcloud storage cp` is the modern replacement for `gsutil`. Pre-installed on Cloud Shell; installable via Google Cloud SDK on EC2. |
| `jq` | 1.7+ | JSON processing in shell | Parse AWS CLI JSON responses (query execution IDs, status polling). Lightweight, ubiquitous. |
| `csvkit` or `miller` | latest | CSV-to-Parquet transformation | **See discussion below** -- CSV transformation is the key design decision. |

**Confidence:** MEDIUM -- shell + AWS CLI is correct, but CSV-to-Parquet tooling needs careful selection.

### CSV-to-Parquet Transformation (Critical Decision)

The pipeline must transform Open Images CSV annotation files into Parquet format for Iceberg table loading. Three viable approaches:

#### Recommended: Athena CTAS from CSV

**Use Athena itself to transform CSV to Iceberg/Parquet.** This is the simplest approach that stays within the project constraints (no Python, no EMR).

1. Upload raw CSVs to S3
2. Create temporary Glue external tables pointing at the CSVs (CSV SerDe)
3. Use Athena `CREATE TABLE ... AS SELECT` (CTAS) with Iceberg table format to transform and load

```sql
-- Step 1: External table over raw CSV
CREATE EXTERNAL TABLE raw_labels (
  ImageID string,
  Source string,
  LabelName string,
  Confidence double
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://bucket/raw/labels/';

-- Step 2: CTAS into Iceberg table
CREATE TABLE iceberg_labels
WITH (
  table_type = 'ICEBERG',
  location = 's3://bucket/iceberg/labels/',
  format = 'PARQUET'
) AS
SELECT * FROM raw_labels;
```

**Why this approach:**
- Zero additional tooling -- Athena does the CSV read and Parquet/Iceberg write
- No need for Python, Spark, or external Parquet libraries
- Athena handles type coercion, column mapping, and Iceberg metadata
- One-time cost: Athena charges per data scanned, but CSVs are small (annotation files are ~100MB total)
- JSON fields can be constructed with `CAST` or string functions during the CTAS

**Confidence:** HIGH -- CTAS into Iceberg is a well-documented Athena capability.

#### Alternative Considered: Python + PyArrow

Using Python with `pyarrow` to convert CSV to Parquet locally, then upload to S3.

**Why not:** Project explicitly chose shell scripts over Python to avoid complexity. PyArrow would require a Python environment, dependency management, and more code. Only justified if CSV transformation needs logic too complex for SQL.

#### Alternative Considered: AWS Glue ETL Jobs

Using Glue Spark jobs for transformation.

**Why not:** Project constraint explicitly excludes Glue ETL and EMR. Overkill for ~42K images of annotation data. Adds cost and complexity.

### Supporting Tools

| Tool | Purpose | Why |
|------|---------|-----|
| `aws s3 sync` | Bulk image download GCS-to-S3 | Efficient parallel transfer with retry logic built in. For GCS-to-S3, first download to local/EBS then upload, or use a GCS-to-S3 proxy pattern. |
| `gcloud storage cp -r` | Download from GCS | Modern replacement for `gsutil`. Supports parallel downloads, resumable transfers. |
| Athena query result polling | Wait for async queries | Athena queries are async. Script must poll `aws athena get-query-execution` until SUCCEEDED/FAILED. |

## CDK Constructs to Use

| CDK Module | Construct | Purpose |
|------------|-----------|---------|
| `aws-cdk-lib/aws-s3` | `Bucket` | S3 bucket for images + Iceberg data |
| `aws-cdk-lib/aws-glue` | `CfnDatabase` | Glue database for Iceberg catalog |
| `aws-cdk-lib/aws-athena` | `CfnWorkGroup` | Athena workgroup with engine v3, result location |
| `aws-cdk-lib/aws-iam` | `Role`, `Policy` | IAM roles for Athena/Glue access to S3 |
| `aws-cdk-lib/aws-lakeformation` | `CfnPermissions` | Lake Formation permissions (if Lake Formation is enabled on the account) |

**Important CDK note:** Glue tables for Iceberg are NOT created via CDK. Iceberg tables must be created via Athena DDL (`CREATE TABLE ... TBLPROPERTIES ('table_type'='ICEBERG')`), not via `CfnTable`, because Athena manages the Iceberg metadata lifecycle. CDK provisions the infrastructure; shell scripts create the tables.

**Confidence:** HIGH -- this separation (CDK for infra, Athena DDL for tables) is the standard pattern.

## Key Design Decisions

### S3 Bucket Layout

```
s3://open-images-data/
  images/
    validation/          # ~42K image files
  raw/
    annotations/         # Original CSV files (kept for reference)
      labels/
      boxes/
      masks/
      relationships/
  iceberg/
    labels/              # Iceberg table data + metadata
    bounding_boxes/
    segmentation_masks/
    visual_relationships/
    images/              # Image metadata table
  athena-results/        # Athena query results
```

### Athena Engine Version

Use Athena engine version 3. Set in CDK via workgroup configuration:

```typescript
new athena.CfnWorkGroup(this, 'WorkGroup', {
  name: 'open-images',
  workGroupConfiguration: {
    engineVersion: { selectedEngineVersion: 'Athena engine version 3' },
    resultConfiguration: {
      outputLocation: `s3://${bucket.bucketName}/athena-results/`,
    },
  },
});
```

Engine v3 is required for full Iceberg support including:
- `CREATE TABLE` with `table_type = 'ICEBERG'`
- CTAS into Iceberg format
- `INSERT INTO` Iceberg tables
- `MERGE INTO` for upserts
- `json_extract()` and `json_extract_scalar()` for JSON fields

### JSON Fields Strategy

For annotation fields with nested/complex structure (e.g., segmentation mask polygons, relationship attributes), store as `string` type in Iceberg containing JSON, then parse at query time:

```sql
-- At table creation
CREATE TABLE segmentation_masks (
  ImageID string,
  MaskPath string,
  LabelName string,
  BoxID string,
  attributes string  -- JSON string: {"IsOccluded": 1, "IsTruncated": 0}
) ...

-- At query time
SELECT
  ImageID,
  json_extract_scalar(attributes, '$.IsOccluded') as is_occluded
FROM segmentation_masks
WHERE json_extract_scalar(attributes, '$.IsOccluded') = '1';
```

**Why string-typed JSON over Iceberg struct types:** Simpler schema, easier to load from CSV, and Athena's JSON functions are performant on Parquet string columns. Struct types would require more complex transformation logic and make schema evolution harder.

**Confidence:** MEDIUM -- this works well but verify whether any annotation fields genuinely need struct types for query performance.

### GCS to S3 Transfer Strategy

Open Images V7 is on GCS at `gs://open-images-dataset/`. Two approaches:

**Recommended for CloudShell/EC2:** Two-hop transfer
1. `gcloud storage cp` from GCS to local/EBS volume
2. `aws s3 sync` from local to S3

**Why not direct GCS-to-S3:** There is no native cross-cloud transfer in AWS CLI or gsutil. Services like AWS DataSync support GCS-to-S3 but add complexity. For a one-time 42K image transfer, two-hop is simple and reliable.

**EC2 recommendation:** Use an EC2 instance in the same region as the target S3 bucket. Validation images are ~6GB total; annotation CSVs are ~100MB. An `m5.large` with 50GB EBS is sufficient. Use a spot instance to minimize cost.

**Confidence:** MEDIUM -- two-hop is standard, but verify current GCS-to-S3 direct transfer options exist in 2026.

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| IaC | AWS CDK (TypeScript) | Terraform, CloudFormation | Project constraint: CDK chosen for type safety and developer experience |
| Transformation | Athena CTAS | Python + PyArrow | Project constraint: shell-only pipeline. CTAS is simpler and zero-dependency. |
| Transformation | Athena CTAS | AWS Glue ETL | Project constraint: no Glue ETL/EMR. Cost and complexity unjustified for small dataset. |
| Table format | Apache Iceberg | Delta Lake, Apache Hudi | Iceberg has best Athena integration. Delta Lake support in Athena is limited. Hudi adds unnecessary complexity. |
| Catalog | Glue Data Catalog | Hive Metastore, Nessie | Glue is the only Iceberg catalog Athena supports natively. |
| Query engine | Athena v3 | Trino on EMR, Redshift Spectrum | Project constraint: serverless, no cluster management. Athena is pay-per-query. |
| Transfer | Two-hop (GCS->local->S3) | AWS DataSync, Storage Transfer Service | Adds service complexity for a one-time transfer of ~6GB. |
| Shell JSON | jq | Python, Node.js | jq is purpose-built for JSON in shell. Lightweight, no runtime dependency. |

## Installation / Setup

```bash
# CDK project initialization
npx aws-cdk@latest init app --language=typescript
# This installs aws-cdk-lib and constructs automatically

# Verify CDK CLI
npx cdk --version

# Pipeline script dependencies (on EC2/CloudShell)
# AWS CLI v2 -- pre-installed on CloudShell and Amazon Linux
aws --version

# Google Cloud SDK (for gcloud storage / gsutil)
# On Amazon Linux 2023:
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
tar -xf google-cloud-cli-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh
gcloud init  # No auth needed for public GCS buckets, but SDK must be installed

# jq (usually pre-installed, otherwise:)
sudo yum install -y jq
```

## Version Verification Checklist

These versions should be verified before starting development (could not verify via web during research):

| Package | Expected Version | Verify With |
|---------|-----------------|-------------|
| `aws-cdk-lib` | 2.170+ | `npm view aws-cdk-lib version` |
| `aws-cdk` CLI | 2.170+ | `npx cdk --version` |
| TypeScript | 5.5+ | `npx tsc --version` |
| AWS CLI | 2.x | `aws --version` |
| Athena engine | v3 | AWS Console or `aws athena list-engine-versions` |
| Node.js | 20.x LTS or 22.x | `node --version` |

## Sources

- Training data knowledge of AWS CDK v2, Athena v3, Apache Iceberg (cutoff ~May 2025)
- Project constraints from `.planning/PROJECT.md`
- Unable to verify with Context7, official docs, or web search due to tool restrictions
- **All version numbers should be verified before use**
