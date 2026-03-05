# Pitfalls Research

**Domain:** Open Images V7 data pipeline (GCS to S3, Iceberg/Athena)
**Researched:** 2026-03-05
**Confidence:** MEDIUM (training data only -- no live verification available)

## Critical Pitfalls

### Pitfall 1: Open Images CSV Column Misalignment and Encoding Surprises

**What goes wrong:**
Open Images annotation CSVs have inconsistent structure across annotation types. The bounding box CSV has different column conventions than the segmentation mask CSV. Some CSVs use `/m/` prefixed MID identifiers that must be joined against a class descriptions file to get human-readable labels. Developers load CSVs assuming uniform structure and end up with broken joins or silently wrong data.

Specific traps:
- `oidv7-class-descriptions.csv` maps MIDs to display names -- without it, all label data is opaque `/m/0xyz` codes
- The relationships CSV references `LabelName1` and `LabelName2` as MIDs, plus a `RelationshipLabel` that is a human-readable string (not a MID) -- mixed identifier schemes in one file
- Segmentation mask CSVs reference mask image paths (`MaskPath`) that point to PNG files in a separate directory structure, not inline data
- Some CSVs have no header row or use inconsistent quoting

**Why it happens:**
Open Images evolved over 7 versions. Each annotation type was contributed by different teams. The CSV formats reflect this history rather than a unified schema.

**How to avoid:**
- Download and inspect every CSV file header before writing any transformation code
- Always join against `oidv7-class-descriptions.csv` to resolve MIDs to names
- Build the Iceberg schema from actual CSV inspection, not from documentation assumptions
- Write a validation step that counts rows and checks for nulls after every load

**Warning signs:**
- Queries return MID codes instead of readable labels
- Joins between tables produce zero rows or unexpectedly few rows
- NULL values in columns you expected to be populated

**Phase to address:**
Data download and schema design phase (early). Must inspect raw data before defining Iceberg table schemas.

---

### Pitfall 2: Iceberg Table Creation via Athena CTAS Losing Data or Schema

**What goes wrong:**
When using `CREATE TABLE ... AS SELECT` (CTAS) or `INSERT INTO` in Athena to populate Iceberg tables from staged Parquet/CSV, the schema inference can silently coerce types incorrectly. Common failures:
- Float bounding box coordinates (`XMin`, `XMax`, `YMin`, `YMax`) stored as strings
- Boolean confidence flags (`IsGroupOf`, `IsOccluded`, `IsTruncated`, `IsDepiction`) stored as integers (0/1 in CSV) but not cast to boolean in Iceberg
- JSON fields stored as plain strings without proper escaping, breaking `json_extract` queries later

**Why it happens:**
Athena's CSV SerDe and Iceberg type system have different type semantics. CSV has no types -- everything is a string. If you don't explicitly cast in your CTAS statement, Athena may preserve string types or infer incorrectly. Iceberg is strongly typed, so wrong types at creation time are painful to fix.

**How to avoid:**
- Define Iceberg tables with explicit `CREATE TABLE` DDL specifying exact column types before loading data
- Use explicit `CAST()` in all INSERT statements: `CAST(XMin AS double)`, `CAST(IsOccluded AS boolean)`
- For JSON fields, validate with `json_extract` immediately after load to confirm parseability
- Never rely on schema inference for production tables

**Warning signs:**
- `DESCRIBE table` shows `string` for columns that should be `double` or `boolean`
- `json_extract()` returns NULL on data you know exists
- Comparison queries (e.g., `WHERE XMin > 0.5`) return no results because comparing strings

**Phase to address:**
Schema design and data loading phase. Must get types right before any data goes in.

---

### Pitfall 3: Iceberg Table Location and Glue Catalog Namespace Misconfiguration

**What goes wrong:**
Iceberg tables on AWS require precise coordination between three things: (1) the S3 location for data files, (2) the S3 location for Iceberg metadata, and (3) the Glue Data Catalog database/table registration. Getting any of these wrong produces tables that appear to exist but return zero rows, or tables that can't be found at all.

Specific failure modes:
- Creating the Glue database but pointing Iceberg table location to a different S3 prefix than where data lands
- Forgetting that Iceberg metadata files (manifest lists, manifests, snapshots) are written alongside data -- if the S3 bucket policy doesn't allow Athena's service role to write metadata, inserts silently fail or hang
- Using `s3://bucket/path` in CDK but `s3://bucket/path/` (trailing slash) in Athena DDL -- Iceberg treats these as different locations
- Creating tables in the `default` Glue database when CDK provisions a custom database name

**Why it happens:**
Iceberg's metadata layer is an abstraction that most developers haven't internalized. They think of it like a traditional Hive table where data location is the only thing that matters. Iceberg additionally writes metadata files that track schema, partitions, and snapshots.

**How to avoid:**
- Use a single source of truth for all S3 paths: define them in CDK and output them as CloudFormation exports consumed by shell scripts
- Standardize on a layout: `s3://bucket/warehouse/database_name/table_name/` for data, with metadata colocated
- In CDK, output the Glue database name and Athena workgroup name so shell scripts don't hardcode
- Test table creation with a trivial INSERT + SELECT before loading real data

**Warning signs:**
- `SELECT count(*) FROM table` returns 0 after a seemingly successful INSERT
- Athena query fails with "Table not found" despite Glue console showing the table
- S3 console shows data files but in a different prefix than expected

**Phase to address:**
Infrastructure (CDK) phase. The S3 layout and Glue database must be defined before any data loading scripts are written.

---

### Pitfall 4: GCS to S3 Transfer -- Authentication, Bandwidth, and Cost Surprises

**What goes wrong:**
Cross-cloud transfer from GCS to S3 is not as simple as `gsutil cp gs://... s3://...`. Multiple failure modes:
- Open Images images are in a requester-pays bucket (`gs://open-images-dataset/`). You must pass `--billing-project` or `-u` flag or you get 403 errors
- Transferring ~42K images sequentially takes hours. Without parallelism, the pipeline is painfully slow
- GCS egress costs are real: ~$0.12/GB. The validation set images are roughly 10-15GB, so cost is manageable, but forgetting requester-pays setup means the transfer just fails
- `gsutil` or `gcloud storage` must be installed and authenticated on the machine running the pipeline (CloudShell has them, EC2 does not by default)

**Why it happens:**
Developers test with a few files, everything works, then the full transfer fails at scale or runs for hours. The requester-pays bucket is a GCS-specific concept that trips up AWS-focused developers.

**How to avoid:**
- For images: use `gsutil -m cp -r` (multi-threaded) with `-u YOUR_GCP_PROJECT` for requester-pays
- Alternative: download annotation CSVs only (small files, a few MB each) and skip image download initially -- annotations are the queryable data; images can be transferred later if needed
- For CSVs: they're hosted on the Open Images website as direct HTTP downloads (no requester-pays), so `curl`/`wget` works fine
- Estimate transfer time and cost before starting: `gsutil du gs://open-images-dataset/validation/` to check size
- Consider whether you actually need the image bytes in S3, or just the annotation metadata

**Warning signs:**
- 403 "Bucket is requester pays" errors on first gsutil attempt
- Transfer script running for 4+ hours with no progress indicator
- GCP billing alert for unexpected egress charges

**Phase to address:**
Data download phase. Must be the first phase validated, before any transformation work begins.

---

### Pitfall 5: Athena Query Performance Killed by Unpartitioned Iceberg Tables

**What goes wrong:**
Loading all annotation data into unpartitioned Iceberg tables means every Athena query does a full table scan. For 42K images this might be tolerable (seconds), but:
- Queries joining multiple unpartitioned tables (images + boxes + labels + masks) explode in cost and time
- Athena charges per TB scanned -- unpartitioned data scans everything even for selective queries
- If you later want to scale to the full 9M-image train set, unpartitioned tables become unusable

**Why it happens:**
At 42K images, developers think "it's small, partitioning is overkill." This is true for single-table scans but false for multi-table joins. Also, retrofitting partitions onto existing Iceberg tables requires rewriting all data.

**How to avoid:**
- For 42K validation set: partitioning is genuinely optional for most tables. The data is small enough that full scans cost fractions of a cent
- BUT: design the schema with partition columns identified even if you don't partition now. Document which columns would be partition keys for scale-up
- If you do partition: partition bounding boxes and labels by a hash bucket of `ImageID` (enables efficient joins). Do NOT partition by label name (too many distinct values, creates tiny files)
- Use Iceberg's hidden partitioning (e.g., `bucket(ImageID, 16)`) rather than Hive-style partitioning

**Warning signs:**
- Cross-table joins timing out or costing more than $0.01 per query on validation data
- Query plans in Athena showing "full table scan" on all tables in a join

**Phase to address:**
Schema design phase. Partition strategy must be decided before table creation, even if the decision is "no partitions for MVP."

---

### Pitfall 6: Segmentation Mask Data Requires Special Handling

**What goes wrong:**
Segmentation masks in Open Images V7 are not inline CSV data. The mask annotation CSV (`validation-annotations-object-segmentation.csv`) contains a `MaskPath` column pointing to actual PNG mask files stored in GCS. Developers who treat this like other annotation types discover:
- The mask CSV only has metadata (ImageID, LabelName, MaskPath, BoxID, etc.) -- the actual mask pixels are in separate PNG files
- Mask PNGs are organized in a directory hierarchy by ImageID prefix
- If you want mask data queryable in Athena, you need to decide: store the S3 path to the mask PNG (simple) or encode mask data somehow (complex and unnecessary)
- The mask CSV references BoxIDs from the bounding box CSV -- this is a foreign key relationship that must be preserved in your Iceberg schema

**Why it happens:**
Segmentation data is inherently binary/image data that doesn't fit in a CSV cell. Open Images stores it as separate files with CSV metadata. Developers expect all annotation types to be purely tabular.

**How to avoid:**
- Store mask metadata in Iceberg (ImageID, LabelName, BoxID, MaskPath as string pointing to S3 location)
- Transfer mask PNG files to S3 maintaining the directory structure
- Do NOT try to inline mask pixel data into Iceberg -- just store the S3 URI
- Ensure BoxID foreign keys align between mask and bounding box tables

**Warning signs:**
- Schema design that tries to store mask data as a BLOB or binary column
- Mask table with no way to join back to bounding boxes
- Mask PNG files not transferred to S3 (only the CSV metadata transferred)

**Phase to address:**
Data download phase (transfer PNGs) and schema design phase (model the relationship correctly).

---

### Pitfall 7: CDK Iceberg/Glue Integration Requires Manual DDL

**What goes wrong:**
AWS CDK can provision Glue databases and S3 buckets, but it cannot create Iceberg table schemas. Developers expect to define everything in CDK and discover that:
- CDK's `@aws-cdk/aws-glue` (or `aws-cdk-lib/aws-glue`) L2 constructs create Glue tables with Hive SerDe, not Iceberg table format
- Iceberg tables must be created via Athena DDL (`CREATE TABLE ... TBLPROPERTIES ('table_type'='ICEBERG')`) or the Iceberg API
- There's a gap between what CDK provisions (database, workgroup, S3 bucket, IAM roles) and what shell scripts must do (run DDL statements via `aws athena start-query-execution`)
- The Athena workgroup must have the correct engine version (v3) and result location configured, or DDL execution fails

**Why it happens:**
CDK is great for infrastructure but not for data-plane operations. Iceberg table creation is a data-plane operation. This boundary isn't obvious until you try.

**How to avoid:**
- Accept the split: CDK creates infrastructure (S3 bucket, Glue database, Athena workgroup, IAM roles); shell scripts create Iceberg tables via Athena DDL
- CDK should output all values shell scripts need: bucket name, database name, workgroup name, result location
- Shell scripts should use `aws athena start-query-execution` with `--work-group` and `--query-execution-context Database=...`
- Include a wait loop in shell scripts: `aws athena get-query-execution` until state is SUCCEEDED/FAILED

**Warning signs:**
- Trying to use CfnTable or GlueTable constructs for Iceberg and getting Hive tables
- Shell scripts with hardcoded bucket names or database names that don't match CDK outputs
- Athena DDL failing with "workgroup not found" or "database not found"

**Phase to address:**
Infrastructure phase (CDK) must explicitly document what it provisions vs. what shell scripts must do. This boundary is the most common source of confusion.

---

### Pitfall 8: JSON Fields in Iceberg -- Athena's String-Based JSON Parsing

**What goes wrong:**
Athena does not have a native JSON column type in Iceberg tables. When the project spec says "JSON fields in Iceberg," what actually happens is:
- You store JSON as a `string` column in Iceberg/Parquet
- You query it with `json_extract(column, '$.field')` or `json_extract_scalar()`
- If the JSON is malformed (trailing commas, single quotes, unescaped characters), `json_extract` returns NULL silently -- no error
- Building JSON strings in shell scripts via string concatenation is fragile and produces malformed JSON

**Why it happens:**
Developers assume "JSON field" means a structured JSON type like PostgreSQL's `jsonb`. Iceberg does support struct/list/map types natively, which is actually what you should use for known schemas. JSON-as-string is only appropriate for truly dynamic/unknown schemas.

**How to avoid:**
- For annotation data with known schemas (bounding boxes have known fields), use Iceberg struct types or just flat columns -- NOT JSON strings
- Only use JSON string columns for genuinely dynamic data
- If you must store JSON strings: generate them with `jq` in shell scripts, never with string concatenation
- Add a validation query after load: `SELECT count(*) FROM table WHERE json_extract(json_col, '$.expected_field') IS NULL` -- if this returns rows, your JSON is broken
- Consider: do you actually need JSON? Open Images annotations have fixed schemas. Flat columns are simpler and faster

**Warning signs:**
- Schema design with JSON columns for data that has a known, fixed structure
- `json_extract` queries returning NULL on data that should have values
- Shell scripts building JSON with `echo "{\"key\": \"$value\"}"` instead of `jq`

**Phase to address:**
Schema design phase. Decide JSON vs. flat columns before writing any DDL.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Store all annotations in one mega-table | Simpler schema, fewer joins | Impossible to query efficiently, schema becomes unwieldy | Never -- annotation types have fundamentally different schemas |
| Skip MID-to-label-name resolution | Faster pipeline, skip one join | All downstream queries return opaque codes; MCP server consumers can't use the data | Never -- resolve at load time |
| Hardcode S3 paths in shell scripts | Faster to write | Breaks when bucket name changes, can't redeploy to different account | Only for initial prototyping, must parameterize before milestone completion |
| Skip Iceberg, use raw Parquet with Hive tables | Simpler setup, no Iceberg concepts to learn | No schema evolution, no time travel, no ACID writes; if you need to fix data later, manual file management | Acceptable if truly one-time and schema is 100% finalized upfront |
| Use CSV instead of Parquet for Athena | No transformation step needed | 5-10x more expensive to query (Athena scans full CSV vs. columnar Parquet), no predicate pushdown | Never for any table with more than a few thousand rows |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| GCS requester-pays bucket | Running `gsutil cp` without `-u PROJECT_ID` flag, getting 403 | Always pass `-u` with your GCP billing project; verify GCP project has billing enabled |
| Athena workgroup engine version | Creating workgroup without specifying engine version, defaulting to v2 which has limited Iceberg support | Explicitly set `engineVersion: 'Athena engine version 3'` in CDK workgroup config |
| Glue database location | Setting database location URI that doesn't match table locations | Set database location to `s3://bucket/warehouse/db_name/` and create all tables under it |
| Athena query results location | Not configuring result output location, queries fail before running | Set `resultConfiguration.outputLocation` on workgroup to `s3://bucket/athena-results/` |
| IAM for Athena+Glue+S3 | Granting S3 access but not Glue `GetDatabase`/`GetTable` permissions | Athena needs: S3 read/write (data + results), Glue read/write (catalog), and Athena execution permissions |
| CloudShell limitations | Assuming CloudShell has unlimited storage/time for large transfers | CloudShell has 1GB persistent storage and sessions timeout. Use EC2 for image transfer, CloudShell for scripts/DDL only |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Unpartitioned multi-table joins | Queries take 30+ seconds on 42K images | Acceptable at validation scale; partition by ImageID bucket if scaling to full dataset | At full 9M images: minutes per query, dollars per query |
| Storing mask PNGs as S3 objects with random keys | S3 GET request throttling if querying many masks | Use prefixed keys matching ImageID structure; batch mask access | At >3,500 GET requests/sec to same prefix |
| Too many small Parquet files | Athena query planning overhead dominates execution time | Consolidate into files of 64-256MB each; for 42K images, aim for 1-5 files per table | At >1,000 small files per table |
| String columns where numeric would work | Full table scans can't use Parquet min/max statistics for predicate pushdown | Use `double` for coordinates, `int` for counts, `boolean` for flags | Noticeable at >1M rows per table |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| S3 bucket with public access for "easy testing" | Dataset exposure, S3 cost exploitation (anyone can query your data and you pay) | Block public access at account level; use bucket policy with explicit principal restrictions |
| Athena workgroup without query cost controls | Runaway query scanning TB of data | Set per-query data scan limit on workgroup (e.g., 1GB for this dataset) |
| GCP service account key in repository | GCP project compromise | Use `gcloud auth login` for interactive use; for automation, use workload identity or short-lived credentials |
| IAM role with `s3:*` and `glue:*` | Over-privileged role could affect other resources | Scope IAM to specific bucket ARN and Glue database ARN |

## "Looks Done But Isn't" Checklist

- [ ] **Class descriptions joined:** Verify label tables contain human-readable names (e.g., "Dog"), not just MIDs (`/m/0bt9lr`) -- query `SELECT DISTINCT LabelName FROM labels LIMIT 10`
- [ ] **Bounding box coordinates are numeric:** Verify `SELECT typeof(XMin) FROM boxes LIMIT 1` returns `double`, not `varchar`
- [ ] **Segmentation masks have S3 URIs:** Verify mask table's `MaskPath` column contains valid S3 paths, not GCS paths
- [ ] **Relationships reference valid entities:** Verify `SELECT count(*) FROM relationships r JOIN boxes b ON r.ImageID = b.ImageID` returns non-zero
- [ ] **Athena engine version is v3:** Verify with `aws athena get-work-group --work-group NAME` and check engine version
- [ ] **All tables are Iceberg format:** Run `SHOW CREATE TABLE tablename` and verify `TBLPROPERTIES` includes `'table_type'='ICEBERG'`
- [ ] **Athena result location is set:** Verify queries don't fail with "output location" errors on first run
- [ ] **Cross-table joins work:** Run at least one query joining images + boxes + labels -- don't assume tables work in isolation

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong column types in Iceberg table | MEDIUM | Drop table, recreate with correct DDL, re-run INSERT. Iceberg makes this easier than Hive (atomic table replacement) |
| Malformed JSON in string columns | MEDIUM | Run UPDATE query to fix JSON, or drop/recreate table with corrected transformation |
| Wrong S3 location for Iceberg data | HIGH | Must drop table, delete orphaned S3 data, recreate table at correct location, re-load |
| Missing class description join | LOW | Create a `class_descriptions` Iceberg table, join at query time instead of load time (less efficient but works) |
| GCS paths in mask table instead of S3 | LOW | Run UPDATE to string-replace `gs://` with `s3://` prefix. Or reload the mask metadata table |
| CDK and scripts out of sync on names | MEDIUM | Add CDK outputs, update scripts to read from CloudFormation outputs via `aws cloudformation describe-stacks` |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CSV column misalignment | Data download / schema design | Inspect every CSV header; document column names and types before writing DDL |
| CTAS type coercion | Schema design / data loading | `DESCRIBE` every table after creation; spot-check with typed queries |
| Glue/S3 location mismatch | Infrastructure (CDK) | CDK outputs consumed by scripts; trivial INSERT+SELECT test per table |
| GCS transfer failures | Data download (first phase) | Validate file counts in S3 match expected counts from GCS listing |
| Unpartitioned tables | Schema design | Document partition strategy (even if "none for MVP"); record decision rationale |
| Segmentation mask handling | Data download + schema design | Verify mask PNGs in S3; verify mask table has valid S3 URIs and BoxID foreign keys |
| CDK vs DDL boundary | Infrastructure phase | README documents exactly what CDK creates vs. what scripts create |
| JSON vs flat columns | Schema design | Decision documented with rationale; validation queries for any JSON columns |

## Sources

- Training knowledge of Apache Iceberg table format, AWS Athena v3, Glue Data Catalog (MEDIUM confidence -- based on extensive documentation up to early 2025)
- Training knowledge of Open Images V7 dataset structure and download procedures (MEDIUM confidence)
- Training knowledge of AWS CDK patterns for data lake infrastructure (MEDIUM confidence)
- Training knowledge of GCS requester-pays bucket behavior (HIGH confidence -- well-established feature)

Note: Web search and documentation verification were unavailable during this research session. All findings are based on training data. Specific Athena v3 Iceberg features or recent CDK construct changes should be verified against current documentation during implementation.

---
*Pitfalls research for: Open Images V7 data pipeline (GCS to S3, Iceberg/Athena)*
*Researched: 2026-03-05*
