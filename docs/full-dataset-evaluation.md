# Full Open Images V7 Dataset Loading Evaluation

**Date:** 2026-03-15
**Status:** Ready to execute
**Decision:** Approved — proceed with full load via `just launch-full-load`

---

## Overview

This document evaluates the cost, time, and risk of loading the full Open Images V7 dataset
(1.9M images, 561 GB) into the `open_images_full` Athena/Iceberg database. The dataset is
hosted in a public CVDF S3 bucket (`s3://open-images-dataset`) in `us-east-1`. Using S3-to-S3
sync via an EC2 instance in the same region incurs **zero data transfer egress cost**.

The full dataset loads into a new Glue database (`open_images_full`) alongside the existing
`open_images` validation-only database. Both databases share the same `OpenImagesStack` S3
bucket, using separate warehouse prefixes to prevent Iceberg metadata conflicts.

---

## Dataset Scope

| Split      | Images        | Size   | S3 Path                                |
|------------|---------------|--------|----------------------------------------|
| train      | 1,743,042     | 513 GB | `s3://open-images-dataset/train/`      |
| validation | 41,620        | 12 GB  | `s3://open-images-dataset/validation/` |
| test       | 125,436       | 36 GB  | `s3://open-images-dataset/test/`       |
| **Total**  | **1,910,098** | **561 GB** | —                                 |

**Image format:** Individual JPEG files (no tar extraction required — direct S3-to-S3 sync)

---

## Transfer Approach

1. **Image sync:** `aws s3 sync --no-sign-request` from `s3://open-images-dataset/{split}/`
   to `s3://{OUR_BUCKET}/images/{split}/` — no local disk required for S3-to-S3 transfers.

2. **Annotation CSVs:** Downloaded from Google Cloud Storage to EC2 local disk, then uploaded
   to `s3://{OUR_BUCKET}/raw/annotations/`. Approximately 15 CSV files, ~5-10 GB total.

3. **EC2 instance:** `c5n.large` (2 vCPU, 5.25 GB RAM, up to 25 Gbps network) — optimized for
   network-throughput workloads. Self-terminating via EXIT trap and
   `--instance-initiated-shutdown-behavior terminate`.

---

## Cost Estimates

| Component                    | Rate               | Amount                | Cost              |
|------------------------------|--------------------|-----------------------|-------------------|
| S3 storage — images          | $0.023/GB/month    | 561 GB                | ~$12.90/month     |
| S3 storage — annotation Parquet | $0.023/GB/month | ~5 GB                 | ~$0.12/month      |
| EC2 c5n.large compute        | $0.096/hour        | ~5 hours              | ~$0.48 one-time   |
| EC2 EBS gp3 20 GB            | $0.08/GB/month     | 20 GB × 5 hrs         | ~$0.01 one-time   |
| S3 PUT requests (1.9M files) | $0.005/1,000       | 1,910,098 files       | ~$9.55 one-time   |
| Athena CTAS (annotation tables) | $5/TB scanned   | ~10 GB scanned        | ~$0.05 one-time   |
| Data transfer egress         | $0/GB              | 561 GB (same region)  | **$0.00**         |
| **Total one-time**           | —                  | —                     | **~$10**          |
| **Monthly recurring**        | —                  | —                     | **~$13/month**    |

Notes:
- S3 storage is the dominant ongoing cost ($12.90/month for 561 GB at standard tier).
- S3 PUT requests ($9.55) are the dominant one-time cost — 1.9M individual JPEG files.
- Zero egress: CVDF bucket (`s3://open-images-dataset`) is in `us-east-1`; our bucket is also
  `us-east-1`. S3-to-S3 same-region transfers have no egress charges.
- Athena 1 GB scan cutoff is already set on the `open-images` workgroup — queries after loading
  will not incur unexpected costs.

---

## Time Estimates

| Step                          | Size         | Estimated Time | Notes                                          |
|-------------------------------|--------------|----------------|------------------------------------------------|
| Annotation CSV download       | ~5-10 GB     | ~15 min        | ~15 CSV files from GCS                         |
| Validation split sync         | 12 GB        | ~5 min         | Smallest split — good early validation signal  |
| Test split sync               | 36 GB        | ~15 min        | Linear scale from validation                   |
| Train split sync              | 513 GB       | ~3.5-4 hours   | Main bottleneck; 1.7M files                    |
| Table creation (Athena CTAS)  | ~10 GB scanned | ~30 min      | ~7 SQL files, sequential execution             |
| View creation                 | —            | ~5 min         | 9 DDL statements, no data scan                 |
| **Total EC2 runtime**         | —            | **~4-5 hours** | Including all steps above                      |

**Throughput basis:** `aws s3 sync` default concurrency is 10 threads. Real-world S3-to-S3
throughput for small-file workloads: ~40-50 MB/s aggregate on c5n-class instances. These are
MEDIUM confidence estimates — actual speed depends on CVDF bucket throughput and S3 prefix
distribution.

---

## Database Strategy

| Aspect            | Existing Database (`open_images`)       | Full Dataset (`open_images_full`)          |
|-------------------|-----------------------------------------|--------------------------------------------|
| Glue database     | `open_images`                           | `open_images_full`                         |
| S3 warehouse      | `s3://{BUCKET}/warehouse/`              | `s3://{BUCKET}/warehouse-full/`            |
| Image data        | None (validation metadata only)         | `s3://{BUCKET}/images/{train,val,test}/`   |
| Images            | 41,620 (validation metadata only)       | 1,910,098 (all splits)                     |
| Athena workgroup  | `open-images`                           | `open-images` (same)                       |
| CDK stack         | `OpenImagesStack`                       | `OpenImagesStack` (same)                   |

The `warehouse-full/` prefix separation ensures Iceberg table metadata and data files for the
full dataset do not intermingle with the validation-only `warehouse/` prefix. Both databases
exist in the same S3 bucket and the same Glue catalog.

---

## Risks and Mitigations

| Risk                                                  | Likelihood | Impact   | Mitigation                                                                                  |
|-------------------------------------------------------|------------|----------|---------------------------------------------------------------------------------------------|
| S3 sync of 1.7M small files is throughput-limited    | Certain    | Medium   | Expected ~4 hours — acceptable; c5n.large is network-optimized                             |
| Re-sync lists all destination objects first (10-15 min) | Certain  | Low      | First run is fine; use `--size-only` flag for subsequent re-runs                           |
| Annotation CSV download fails if GCS becomes requester-pays | Low  | Medium   | CVDF S3 mirror exists as fallback; URLs in download-annotations-full.sh can be updated     |
| `common.sh` profile handling on EC2                  | Fixed      | High     | FIXED in Plan 06-01: `OPEN_IMAGES_NO_PROFILE=1` support added to common.sh                |
| `discover_bucket()` fails with `--profile` on EC2    | Fixed      | High     | FIXED in Plan 06-01: same `AWS_PROFILE_FLAG` array now empty in no-profile mode            |
| Train split sync interrupted (network blip)          | Low        | Low      | `aws s3 sync` is idempotent — re-run resumes from where it left off                       |
| Annotation CSV overwrite conflict during re-run      | Low        | Low      | `download_file()` uses `curl -z` (conditional download — skips if unchanged)               |
| Glue `open_images_full` permissions missing          | Handled    | High     | EC2 role in CDK (Plan 06-01) includes explicit `open_images_full` Glue resource ARNs       |
| S3 PUT cost underestimate                            | Low        | Low      | 1.9M files × $0.005/1000 = $9.55 — well within expected range                             |

---

## Execution Steps

1. **Deploy CDK stack** (adds `open_images_full` database + EC2 instance profile):
   ```bash
   just deploy
   ```

2. **Launch full load pipeline** (EC2 syncs all 3 splits + downloads annotations):
   ```bash
   just launch-full-load
   ```
   Returns instance ID immediately. Instance self-terminates when complete (~4-5 hours).

3. **Monitor progress:**
   ```bash
   just instance-status <instance-id>
   just console-output <instance-id>
   ```

4. **Create Iceberg tables** in `open_images_full` database (run locally after EC2 completes):
   ```bash
   just create-tables-full
   # Dry-run first: just dry-run-tables-full
   ```

5. **Create views** in `open_images_full` database:
   ```bash
   just create-views-full
   ```

---

## Scope Exclusions

The following are explicitly out of scope for this evaluation and pipeline:

- **Segmentation mask PNGs:** The train split has ~2.8M segmentation mask PNGs (~200+ GB).
  Annotation CSV metadata is sufficient (`train-annotations-object-segmentation.csv`). PNG masks
  can be added in a future pipeline iteration if needed.

- **Partitioning:** No S3 prefix partitioning by split. Iceberg + Parquet + Snappy handles
  1.9M rows without partitioning. Re-evaluate after measuring actual query performance.

- **Preemptive query optimization:** Evaluate at runtime after loading. The 1 GB Athena
  workgroup scan limit is already in place as a cost guard.

- **Cross-dataset JOINs:** JOIN capability between `open_images_full` and MSR-VTT tables is
  a future milestone and requires schema alignment work beyond this phase.
