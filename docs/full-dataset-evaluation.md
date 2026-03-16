# Full Open Images V7 Dataset Loading Evaluation

**Date:** 2026-03-16
**Status:** Ready to execute
**Decision:** Approved — proceed with full load via `just launch-full-load`

---

## Overview

This document evaluates the cost, time, and risk of loading the full Open Images V7 dataset
(1.9M images) into the `open_images_full` Athena/Iceberg database.

**Key insight:** Images are served directly from the CVDF public S3 bucket
(`https://open-images-dataset.s3.amazonaws.com/{split}/{id}.jpg`) — no image copying needed.
The `images` table generates a `cvdf_url` derived column for reliable image access,
replacing the Flickr URLs that break over time as users delete their photos.

Only annotation CSVs (~5-10 GB) need to be downloaded and uploaded to our S3 bucket.

---

## Dataset Scope

| Split      | Images        | Source                                 |
|------------|---------------|----------------------------------------|
| train      | 1,743,042     | `s3://open-images-dataset/train/`      |
| validation | 41,620        | `s3://open-images-dataset/validation/` |
| test       | 125,436       | `s3://open-images-dataset/test/`       |
| **Total**  | **1,910,098** | Served directly from CVDF bucket       |

**Image access:** `https://open-images-dataset.s3.amazonaws.com/{split}/{image_id}.jpg`
- Public bucket, no auth required
- Permanent URLs (AWS-hosted, not dependent on Flickr users)
- Max 1024px on longest side, JPEG format

---

## Transfer Approach

1. **Images: NOT copied** — served directly from the CVDF public bucket via `cvdf_url`
   derived column in the images Iceberg table. This eliminates:
   - 561 GB S3 storage ($12.90/month)
   - 1.9M S3 PUT requests ($9.55 one-time)
   - 4-5 hours EC2 transfer time

2. **Annotation CSVs:** Downloaded from Google Cloud Storage to EC2 local disk, then
   uploaded to `s3://{OUR_BUCKET}/raw/annotations/`. ~20 CSV files, ~5-10 GB total.

3. **EC2 instance:** `t3.medium` (2 vCPU, 4 GB RAM) — sufficient for annotation
   download only. Self-terminating via EXIT trap.

---

## Cost Estimates

| Component                        | Rate               | Amount          | Cost              |
|----------------------------------|--------------------|-----------------|--------------------|
| EC2 t3.medium compute            | $0.0416/hour       | ~30 min         | ~$0.02 one-time   |
| EC2 EBS gp3 20 GB                | $0.08/GB/month     | 20 GB × 30 min  | ~$0.01 one-time   |
| S3 storage — annotation Parquet  | $0.023/GB/month    | ~5 GB           | ~$0.12/month      |
| Athena CTAS (annotation tables)  | $5/TB scanned      | ~10 GB scanned  | ~$0.05 one-time   |
| S3 PUT requests (annotation CSVs)| $0.005/1,000       | ~100 files      | ~$0.01 one-time   |
| Image storage                    | —                  | CVDF bucket     | **$0.00**         |
| Data transfer egress             | —                  | Same region     | **$0.00**         |
| **Total one-time**               | —                  | —               | **~$0.10**        |
| **Monthly recurring**            | —                  | —               | **~$0.12/month**  |

**vs. original plan (with image copying):**
- Saved: $10 one-time (S3 PUT) + $13/month (image storage) + 4-5 hours EC2 time
- The CVDF bucket is free, permanent, and public

---

## Time Estimates

| Step                          | Size         | Estimated Time | Notes                              |
|-------------------------------|--------------|----------------|------------------------------------|
| Annotation CSV download       | ~5-10 GB     | ~15 min        | ~20 CSV files from GCS             |
| Annotation CSV upload to S3   | ~5-10 GB     | ~5 min         | Same-region S3 upload              |
| Table creation (Athena CTAS)  | ~10 GB scan  | ~30 min        | ~7 SQL files, sequential           |
| View creation                 | —            | ~5 min         | 9+ DDL statements, no data scan   |
| **Total EC2 runtime**         | —            | **~30 min**    | Annotations only (no image sync)  |
| **Total pipeline (including local)** | —    | **~1 hour**    | EC2 + table/view creation         |

---

## Database Strategy

| Aspect            | Existing (`open_images`)              | Full Dataset (`open_images_full`)          |
|-------------------|---------------------------------------|--------------------------------------------|
| Glue database     | `open_images`                         | `open_images_full`                         |
| S3 warehouse      | `s3://{BUCKET}/warehouse/`            | `s3://{BUCKET}/warehouse-full/`            |
| Image access      | Flickr URLs (some broken)             | CVDF URLs (permanent, public)              |
| Images            | 41,620 (validation only)              | 1,910,098 (all splits)                     |
| Athena workgroup  | `open-images`                         | `open-images` (same)                       |
| CDK stack         | `OpenImagesStack`                     | `OpenImagesStack` (same)                   |

---

## Risks and Mitigations

| Risk                                                  | Likelihood | Impact   | Mitigation                                                |
|-------------------------------------------------------|------------|----------|-----------------------------------------------------------|
| CVDF bucket becomes unavailable/requester-pays        | Very Low   | High     | AWS-hosted public dataset; can copy images then if needed |
| Annotation CSV download fails (GCS issue)             | Low        | Medium   | Retry logic in download_file(); re-run is idempotent      |
| 1.9M row Athena queries hit scan limits               | Medium     | Low      | 1 GB scan cutoff already set; Iceberg + Parquet is compact |
| Flickr URLs in existing views confused with cvdf_url  | Low        | Low      | Both columns present; MCP can switch to cvdf_url          |

---

## Execution Steps

1. **Deploy CDK stack** (adds `open_images_full` database + EC2 instance profile):
   ```bash
   just deploy
   ```

2. **Launch annotation download** (EC2 downloads CSVs, ~30 min):
   ```bash
   just launch-full-load
   ```

3. **Monitor progress:**
   ```bash
   just instance-status <instance-id>
   just console-output <instance-id>
   ```

4. **Create Iceberg tables** in `open_images_full` (run locally after EC2 completes):
   ```bash
   just create-tables-full
   ```

5. **Create views** in `open_images_full`:
   ```bash
   just create-views-full
   ```

---

## Scope Exclusions

- **Image copying:** Images served from CVDF bucket — no S3 sync needed
- **Segmentation mask PNGs:** ~200+ GB, out of scope. CSV metadata is sufficient.
- **Partitioning:** Not needed at 1.9M row scale with Iceberg + Parquet
- **Cross-dataset JOINs:** Future milestone
