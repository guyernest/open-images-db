# Open Images V7 Data Acquisition Pipeline

Downloads Open Images V7 validation set annotation CSVs, image metadata, and segmentation mask PNGs from public HTTPS URLs, then uploads everything to the project's S3 raw zone.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| curl | any | Pre-installed on macOS/Linux |
| AWS CLI | v2 | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| jq | any | `brew install jq` or [download](https://jqlang.github.io/jq/download/) |
| unzip | any | Pre-installed on most systems |

### AWS Configuration

The pipeline uses the `ze-kasher-dev` AWS profile. Configure it:

```bash
aws configure --profile ze-kasher-dev
```

The CDK infrastructure stack must be deployed first (Phase 1) so the S3 bucket exists:

```bash
cd infra && npx cdk deploy --profile ze-kasher-dev
```

### Disk Space

The pipeline downloads to a local temp directory before uploading to S3. Plan for approximately:

- Annotation CSVs: ~200 MB
- Metadata CSVs: ~50 MB
- Mask PNGs (16 zip archives): ~3-5 GB (extracted)
- **Total: ~5 GB recommended free space**

The temp directory defaults to `$HOME/open-images-tmp`. Override with:

```bash
export OPEN_IMAGES_TEMP=/path/to/large/disk
```

## Quick Start

```bash
# Full pipeline (annotations + metadata + masks)
bash scripts/download-all.sh

# Quick test (annotations + metadata only, skip masks)
bash scripts/download-all.sh --skip-masks

# Validate existing S3 data without downloading
bash scripts/download-all.sh --validate-only

# Use a specific bucket (skip CloudFormation discovery)
bash scripts/download-all.sh --bucket my-bucket-name
```

## Options

| Flag | Description |
|------|-------------|
| `--bucket NAME` | Override S3 bucket name (skips CloudFormation stack lookup) |
| `--validate-only` | Skip all downloads, just validate file counts in S3 |
| `--skip-masks` | Download annotations and metadata only (useful for quick testing) |
| `--help` | Show usage information |

## Running on EC2

Recommended setup for fastest downloads:

- **Instance type:** t3.medium or larger
- **Storage:** 20 GB+ EBS volume (for temp files during mask extraction)
- **Region:** us-east-1 (closest to Google's US storage endpoints)
- **IAM:** Attach the `OpenImagesPolicy` managed policy to the instance role

```bash
# SSH to EC2, clone repo, run pipeline
git clone <repo-url>
cd open-images
bash scripts/download-all.sh
```

## Running Locally

Works on macOS and Linux with the same prerequisites. Downloads may be slower depending on your internet connection. The mask download (16 zip archives with ~24,730 PNGs) is the longest step.

```bash
bash scripts/download-all.sh
```

## What Gets Created

After a successful run, the S3 bucket contains:

```
s3://<bucket>/
  raw/
    annotations/
      oidv7-val-annotations-human-imagelabels.csv
      oidv7-val-annotations-machine-imagelabels.csv
      validation-annotations-bbox.csv
      validation-annotations-object-segmentation.csv
      oidv6-validation-annotations-vrd.csv
    metadata/
      oidv7-class-descriptions.csv
      oidv7-class-descriptions-boxable.csv
      validation-images-with-rotation.csv
    masks/
      <ImageID>_<LabelMID>_<BoxID>.png   (x ~24,730)
    manifest.json
```

## Idempotency

The pipeline is safe to re-run at any time:

- **Downloads:** `curl -z` only re-downloads if the remote file is newer than the local copy
- **S3 uploads:** `aws s3 sync` only uploads files that differ (by size or modification time)
- **Mask extraction:** `unzip -o` overwrites existing files with identical content
- **Manifest:** Regenerated from current S3 contents on each run

## Troubleshooting

### "AWS credentials not configured"

Ensure the `ze-kasher-dev` profile is set up:

```bash
aws configure --profile ze-kasher-dev
aws sts get-caller-identity --profile ze-kasher-dev
```

### "Could not discover bucket from stack"

The CDK stack may not be deployed yet:

```bash
# Check if stack exists
aws cloudformation describe-stacks --stack-name OpenImagesStack --profile ze-kasher-dev

# Deploy if needed
cd infra && npx cdk deploy --profile ze-kasher-dev
```

Or bypass stack discovery entirely:

```bash
bash scripts/download-all.sh --bucket your-bucket-name
```

### "No space left on device"

The mask extraction requires several GB. Options:

1. Set a temp directory on a larger volume: `export OPEN_IMAGES_TEMP=/mnt/data/tmp`
2. Skip masks for now: `bash scripts/download-all.sh --skip-masks`
3. On EC2: attach a larger EBS volume

### "HTTP error downloading (possibly 403/404)"

The Open Images files are publicly accessible via HTTPS. If you get 403 errors:

1. Check if the URL is still valid (Google may have moved files)
2. The bucket may have switched to requester-pays -- install `gsutil` and authenticate with a GCS project

### Network timeouts

The pipeline uses `curl --retry 3 --retry-delay 5` for automatic retries. For persistent issues:

1. Check your internet connection
2. Try again later (Google's servers may be temporarily slow)
3. On EC2, ensure your security group allows outbound HTTPS
