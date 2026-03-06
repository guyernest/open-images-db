# Phase 2: Data Acquisition - Research

**Researched:** 2026-03-05
**Domain:** Shell scripting, GCS/S3 data transfer, Open Images V7 dataset
**Confidence:** HIGH

## Summary

Phase 2 downloads Open Images V7 validation set annotation data from Google Cloud Storage to the project's S3 raw zone. The validation set is small (41,620 images, ~24,730 masks) -- all annotation CSVs and metadata are publicly accessible via direct HTTPS URLs from `storage.googleapis.com/openimages`, meaning `curl`/`wget` can handle most downloads without requiring `gsutil` or GCS authentication. The segmentation masks are distributed as 16 zip archives (~24,730 PNGs total), which must be downloaded, extracted, and uploaded to S3.

The download approach is: (1) `curl` annotation CSVs and metadata directly from HTTPS URLs to a local temp directory, (2) download and extract 16 mask zip archives, (3) upload everything to S3 via `aws s3 sync` (which provides natural idempotency). The `gsutil` requirement from CONTEXT.md can be relaxed to optional -- all files are available via public HTTPS. Requester-pays is NOT applicable to the annotation/mask files (they are served from Google's public storage bucket, not a requester-pays bucket).

**Primary recommendation:** Use `curl` for annotation CSVs and metadata, `curl` + `unzip` for mask archives, and `aws s3 sync` for idempotent upload to S3. Reserve gsutil only as an optional alternative.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Two-hop transfer: download from GCS, then upload to S3
- Single orchestrator script (download-all.sh) that calls per-type functions
- Download to local temp directory first, verify, then upload to S3
- Auto-detect requester-pays: try without first, if 403 then prompt for GCS project ID
- Rust CLI fallback: if gsutil/aws CLI can't handle the mask volume, escalate to Rust
- Download all masks in Phase 2 (don't defer)
- Store flat under raw/masks/ (no sharding)
- Resumable via skip-existing: check if mask already in S3 before downloading
- Parallel downloads using xargs -P or GNU parallel (16-32 threads)
- Primary target: EC2 instance; also work on local machine
- Progress summary output: per-type progress, mask count/total
- Post-download validation: file count + size checks per data type
- Prerequisites check at start: verify gsutil, aws CLI, jq installed
- S3 layout: raw/annotations/, raw/metadata/, raw/masks/
- Preserve original GCS filenames for annotation CSVs
- JSON manifest (raw/manifest.json) listing all downloaded files

### Claude's Discretion
- Exact gsutil flags and parallelism tuning
- Temp directory location and cleanup strategy
- Error retry logic and timeout values
- Whether to use gsutil -m (built-in parallelism) or external parallel tool

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DATA-01 | Download annotation CSVs from GCS to S3 raw zone | All CSV URLs identified below; curl + aws s3 sync pattern |
| DATA-02 | Download validation image list/metadata from GCS to S3 raw zone | Image metadata URL identified; same download pattern |
| DATA-03 | Download segmentation mask PNGs from GCS to S3 raw zone | 16 zip archives identified; extract + flat upload pattern |
| DATA-04 | Pipeline idempotent (safe to re-run) | aws s3 sync handles this; curl with -z flag for conditional download |
| DATA-05 | Handle GCS requester-pays authentication | Research shows public HTTPS access; requester-pays NOT needed for these files |
| DATA-06 | Clear execution instructions (prerequisites, steps) | Prerequisites check pattern documented; README section needed |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| curl | system | Download files from HTTPS URLs | Available everywhere, supports resume (-C), conditional (-z) |
| aws cli | v2 | Upload to S3 and manage S3 objects | Standard AWS tool, `s3 sync` is idempotent by default |
| jq | system | JSON manifest generation and parsing | Standard CLI JSON processor |
| unzip | system | Extract mask zip archives | Standard, handles the 16 mask archives |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| gsutil | optional | Alternative GCS download method | Only if curl fails or requester-pays bucket encountered |
| xargs | system | Parallel execution | Parallel mask upload to S3 |
| GNU parallel | optional | Advanced parallel execution | Alternative to xargs -P for mask upload |

### Not Needed
| Tool | Why Not |
|------|---------|
| gsutil (required) | Files are publicly accessible via HTTPS; gsutil is optional fallback |
| Rust CLI | Validation set has only ~24,730 masks (not 2.8M) -- shell tools handle this fine |
| gcloud auth | No requester-pays on the public openimages bucket |

**Installation (prerequisites check):**
```bash
# Required
command -v curl   || { echo "Install curl"; exit 1; }
command -v aws    || { echo "Install AWS CLI v2"; exit 1; }
command -v jq     || { echo "Install jq"; exit 1; }
command -v unzip  || { echo "Install unzip"; exit 1; }
```

## Open Images V7 Validation Set -- Complete File Inventory

### Annotation CSVs (raw/annotations/)

| File | URL | Description |
|------|-----|-------------|
| oidv7-val-annotations-human-imagelabels.csv | https://storage.googleapis.com/openimages/v7/oidv7-val-annotations-human-imagelabels.csv | Human-verified image-level labels |
| oidv7-val-annotations-machine-imagelabels.csv | https://storage.googleapis.com/openimages/v7/oidv7-val-annotations-machine-imagelabels.csv | Machine-generated image-level labels |
| validation-annotations-bbox.csv | https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv | Bounding box annotations |
| validation-annotations-object-segmentation.csv | https://storage.googleapis.com/openimages/v5/validation-annotations-object-segmentation.csv | Segmentation mask index (MaskPath, BoxID, coords) |
| oidv6-validation-annotations-vrd.csv | https://storage.googleapis.com/openimages/v6/oidv6-validation-annotations-vrd.csv | Visual relationships |

### Class Descriptions (raw/metadata/)

| File | URL | Description |
|------|-----|-------------|
| oidv7-class-descriptions.csv | https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions.csv | All class names (MID to DisplayName) |
| oidv7-class-descriptions-boxable.csv | https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv | Boxable class names |

### Image Metadata (raw/metadata/)

| File | URL | Description |
|------|-----|-------------|
| validation-images-with-rotation.csv | https://storage.googleapis.com/openimages/2018_04/validation/validation-images-with-rotation.csv | ImageID, OriginalURL, License, Author, dimensions, rotation |

### Segmentation Mask PNGs (raw/masks/)

**Source:** 16 zip archives, one per hex character (0-9, a-f)
**URL pattern:** `https://storage.googleapis.com/openimages/v5/validation-masks/validation-masks-{CHAR}.zip`
**Characters:** 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, a, b, c, d, e, f
**Total masks:** ~24,730 PNGs
**Naming convention:** `{ImageID}_{LabelMID}_{BoxID}.png`

### Validation Set Statistics

| Data Type | Count |
|-----------|-------|
| Images | 41,620 |
| Image-level labels | 618,184 |
| Bounding boxes | 303,980 |
| Segmentation masks | 24,730 |
| Visual relationships | 27,243 |

## Architecture Patterns

### Recommended Project Structure
```
scripts/
├── download-all.sh          # Orchestrator (DATA-06)
├── lib/
│   ├── common.sh            # Shared functions (logging, prereqs, S3 helpers)
│   ├── download-annotations.sh  # DATA-01
│   ├── download-metadata.sh     # DATA-02
│   └── download-masks.sh        # DATA-03
└── README.md                # Execution instructions (DATA-06)
```

### Pattern 1: Two-Hop Transfer with Verification
**What:** Download from HTTPS to local temp, verify file integrity, upload to S3
**When to use:** Every file type

```bash
# Download with conditional re-download (idempotent)
curl -fSL -o "$TEMP_DIR/$filename" -z "$TEMP_DIR/$filename" "$url"

# Verify non-empty
[[ -s "$TEMP_DIR/$filename" ]] || { echo "ERROR: Empty file $filename"; return 1; }

# Upload to S3 (sync handles idempotency)
aws s3 cp "$TEMP_DIR/$filename" "s3://$BUCKET/raw/annotations/$filename" \
  --profile ze-kasher-dev
```

### Pattern 2: Mask Archive Download and Extract
**What:** Download zip, extract flat PNGs, upload to S3
**When to use:** Segmentation masks (DATA-03)

```bash
for char in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
  url="https://storage.googleapis.com/openimages/v5/validation-masks/validation-masks-${char}.zip"
  zip_file="$TEMP_DIR/validation-masks-${char}.zip"

  curl -fSL -o "$zip_file" -z "$zip_file" "$url"
  unzip -o -j "$zip_file" -d "$TEMP_DIR/masks/"
done

# Bulk upload flat to S3
aws s3 sync "$TEMP_DIR/masks/" "s3://$BUCKET/raw/masks/" \
  --profile ze-kasher-dev
```

### Pattern 3: Idempotent Re-run (DATA-04)
**What:** Running the pipeline again does not corrupt or duplicate data
**How:**
- `curl -z` only downloads if remote file is newer than local
- `aws s3 sync` only uploads files that differ (size/timestamp)
- Mask extraction uses `unzip -o` (overwrite, but content is identical)
- Manifest regeneration is safe (overwrites with same content)

### Pattern 4: Bucket Name Discovery
**What:** Get the S3 bucket name from CDK stack outputs
```bash
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name OpenImagesStack \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text --profile ze-kasher-dev)
```

### Pattern 5: JSON Manifest Generation
**What:** Generate raw/manifest.json after all downloads complete
```bash
# List all objects in raw/ prefix, capture to manifest
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "raw/" \
  --profile ze-kasher-dev \
  --query 'Contents[].{Key:Key,Size:Size,LastModified:LastModified}' \
  --output json | jq '.' > "$TEMP_DIR/manifest.json"

# Add source URLs to manifest and upload
aws s3 cp "$TEMP_DIR/manifest.json" "s3://$BUCKET/raw/manifest.json" \
  --profile ze-kasher-dev
```

### Anti-Patterns to Avoid
- **Using gsutil as primary download tool:** These are public HTTPS URLs; curl is simpler and requires no GCS auth setup
- **Downloading masks individually:** Use the 16 zip archives, not individual PNG fetches
- **Uploading masks one-by-one with aws s3 cp:** Use `aws s3 sync` for bulk upload with built-in parallelism
- **Hardcoding bucket name:** Always discover from CloudFormation stack outputs
- **Skipping file size validation:** Always verify downloaded files are non-empty and match expected counts

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idempotent downloads | Custom checksum tracking | `curl -z` + `aws s3 sync` | Built-in conditional download and sync |
| Parallel S3 upload | Custom threading | `aws s3 sync` (multithreaded by default) | AWS CLI handles parallelism internally |
| JSON generation | String concatenation | `jq` + `aws s3api list-objects-v2` | Correct JSON formatting guaranteed |
| Progress display | Custom counters for every file | Simple counters per data type | 8 annotation files don't need per-file progress |
| Retry logic | Custom retry loops | `curl --retry 3 --retry-delay 5` | Built-in exponential backoff |

## Common Pitfalls

### Pitfall 1: Assuming Requester-Pays is Needed
**What goes wrong:** Scripts fail trying to authenticate with GCS or pass `--billing-project` flags
**Why it happens:** Open Images docs mention GCS but the annotation/mask files are on a PUBLIC bucket (`storage.googleapis.com/openimages`)
**How to avoid:** Use direct HTTPS URLs with curl. No GCS auth needed for annotation CSVs, metadata, or mask zips
**Warning signs:** 403 errors when using gsutil without project billing flag

### Pitfall 2: Expecting 2.8M Masks for Validation
**What goes wrong:** Scripts designed for massive parallelism, Rust fallback, etc. for a problem that doesn't exist
**Why it happens:** The 2.8M figure is for the TRAINING set. Validation has only ~24,730 masks
**How to avoid:** Download the 16 zip archives, extract locally, bulk sync to S3
**Warning signs:** Over-engineering the mask download pipeline

### Pitfall 3: Mask Zip Directory Structure
**What goes wrong:** Extracted PNGs land in nested directories instead of flat
**Why it happens:** Zip archives may contain directory structure
**How to avoid:** Use `unzip -j` (junk paths) to extract flat
**Warning signs:** S3 masks having unexpected prefixes

### Pitfall 4: AWS Profile Not Set
**What goes wrong:** Uploads go to wrong account or fail with auth errors
**Why it happens:** Forgetting `--profile ze-kasher-dev` on aws CLI calls
**How to avoid:** Set profile once in a variable, use consistently
**Warning signs:** "Unable to locate credentials" or wrong bucket name

### Pitfall 5: CloudFormation Stack Name Mismatch
**What goes wrong:** Can't discover bucket name from stack outputs
**Why it happens:** CDK stack ID vs CloudFormation stack name may differ
**How to avoid:** Verify stack name with `aws cloudformation list-stacks` first, or accept bucket name as a script parameter with stack lookup as default
**Warning signs:** Empty BUCKET variable

### Pitfall 6: Temp Directory Fills Disk
**What goes wrong:** Mask extraction fills /tmp on small EC2 instances
**Why it happens:** ~24,730 PNG files + 16 zip archives can be several GB
**How to avoid:** Use a dedicated temp directory (e.g., `$HOME/open-images-tmp`), clean up zips after extraction, or use instance with sufficient storage
**Warning signs:** "No space left on device" errors

## Code Examples

### Prerequisite Check (DATA-06)
```bash
check_prerequisites() {
  local missing=()
  command -v curl  >/dev/null 2>&1 || missing+=("curl")
  command -v aws   >/dev/null 2>&1 || missing+=("aws (AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)")
  command -v jq    >/dev/null 2>&1 || missing+=("jq (https://jqlang.github.io/jq/download/)")
  command -v unzip >/dev/null 2>&1 || missing+=("unzip")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
  fi

  # Verify AWS credentials
  aws sts get-caller-identity --profile ze-kasher-dev >/dev/null 2>&1 \
    || { echo "ERROR: AWS credentials not configured for profile 'ze-kasher-dev'"; exit 1; }
}
```

### Download with Progress (DATA-01)
```bash
download_file() {
  local url="$1" dest_dir="$2" filename
  filename=$(basename "$url")

  echo "  Downloading $filename..."
  curl -fSL --retry 3 --retry-delay 5 \
    -o "$dest_dir/$filename" \
    -z "$dest_dir/$filename" \
    "$url"

  if [[ ! -s "$dest_dir/$filename" ]]; then
    echo "ERROR: Downloaded file is empty: $filename"
    return 1
  fi
  echo "  OK: $filename ($(du -h "$dest_dir/$filename" | cut -f1))"
}
```

### Post-Download Validation
```bash
validate_downloads() {
  local temp_dir="$1"
  local errors=0

  echo "Validating downloads..."

  # Check annotation CSV count
  local csv_count
  csv_count=$(find "$temp_dir/annotations" -name '*.csv' | wc -l | tr -d ' ')
  if [[ "$csv_count" -lt 5 ]]; then
    echo "ERROR: Expected at least 5 annotation CSVs, found $csv_count"
    ((errors++))
  fi

  # Check metadata files
  [[ -s "$temp_dir/metadata/validation-images-with-rotation.csv" ]] \
    || { echo "ERROR: Missing image metadata"; ((errors++)); }

  # Check mask count
  local mask_count
  mask_count=$(find "$temp_dir/masks" -name '*.png' | wc -l | tr -d ' ')
  echo "  Masks: $mask_count PNGs"
  if [[ "$mask_count" -lt 20000 ]]; then
    echo "WARNING: Expected ~24,730 masks, found $mask_count"
  fi

  return $errors
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| gsutil for all GCS downloads | Direct HTTPS (curl/wget) for public buckets | Always available | No GCS SDK/auth needed |
| gsutil (Python) | gcloud storage (Go-based) | 2023 | Faster, but irrelevant since we use curl |
| aws s3 cp --recursive | aws s3 sync | Stable | sync is idempotent by default |

**Key insight:** The Open Images annotation files are served from a public Google Cloud Storage bucket accessible via HTTPS. No GCS-specific tooling is required.

## Open Questions

1. **Exact zip archive case sensitivity (uppercase vs lowercase hex chars)**
   - What we know: The download page references characters but case may vary
   - What's unclear: Whether archive names use 0-9,a-f or 0-9,A-F
   - Recommendation: Try lowercase first; if 404, try uppercase. The download page examples suggest lowercase for mask archives but uppercase for some training archives

2. **Mask zip archive total size**
   - What we know: ~24,730 PNGs across 16 archives
   - What's unclear: Total download size in GB
   - Recommendation: Monitor disk usage during download; expect 1-5 GB total for validation masks

3. **Manifest format details**
   - What we know: CONTEXT.md specifies paths, sizes, timestamps, source URLs
   - What's unclear: Exact JSON schema
   - Recommendation: Use aws s3api list-objects output as base, enrich with source URL mapping

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell script self-validation (no external test framework) |
| Config file | none -- validation is built into the download scripts |
| Quick run command | `bash scripts/download-all.sh --validate-only` |
| Full suite command | `bash scripts/download-all.sh` (includes post-download validation) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DATA-01 | Annotation CSVs exist in S3 raw zone | smoke | `aws s3 ls s3://$BUCKET/raw/annotations/ --profile ze-kasher-dev` | Wave 0 |
| DATA-02 | Image metadata exists in S3 raw zone | smoke | `aws s3 ls s3://$BUCKET/raw/metadata/ --profile ze-kasher-dev` | Wave 0 |
| DATA-03 | Mask PNGs exist in S3 raw zone | smoke | `aws s3 ls s3://$BUCKET/raw/masks/ --summarize --profile ze-kasher-dev` | Wave 0 |
| DATA-04 | Idempotent re-run | integration | Run download-all.sh twice, verify no size changes | manual |
| DATA-05 | Requester-pays handled | smoke | Verified by successful download (public HTTPS, no auth needed) | N/A |
| DATA-06 | Execution instructions | manual-only | Review scripts/README.md exists and is complete | manual |

### Sampling Rate
- **Per task commit:** Verify individual data type landed in S3 with correct file count
- **Per wave merge:** Full `aws s3 ls` validation of all raw/ prefixes
- **Phase gate:** All annotation CSVs, metadata, and masks present with expected counts

### Wave 0 Gaps
- [ ] `scripts/` directory -- does not exist yet
- [ ] `scripts/download-all.sh` -- orchestrator script
- [ ] `scripts/lib/` -- shared function library
- [ ] No external test framework needed -- validation built into scripts

## Sources

### Primary (HIGH confidence)
- [Open Images V7 Download Page](https://storage.googleapis.com/openimages/web/download_v7.html) - All download URLs verified
- [Open Images V7 Facts & Figures](https://storage.googleapis.com/openimages/web/factsfigures_v7.html) - Validation set counts (24,730 masks, 41,620 images, etc.)
- [validation-annotations-object-segmentation.csv](https://storage.googleapis.com/openimages/v5/validation-annotations-object-segmentation.csv) - Mask CSV schema and naming convention verified

### Secondary (MEDIUM confidence)
- [AWS CLI S3 sync documentation](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) - Idempotency behavior
- [AWS CLI S3 cp documentation](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html) - Upload patterns
- [Google Cloud public data access](https://cloud.google.com/storage/docs/access-public-data) - Public bucket access patterns

### Tertiary (LOW confidence)
- Mask zip archive sizes -- not verified, estimated at 1-5 GB total
- Hex character case in archive names -- needs runtime verification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - curl + aws cli are well-documented, URLs verified against official download page
- Architecture: HIGH - Two-hop pattern is straightforward; file inventory complete
- Pitfalls: HIGH - Requester-pays non-issue verified; mask count verified at official source
- File inventory: HIGH - All URLs fetched from official Open Images V7 download page

**Research date:** 2026-03-05
**Valid until:** 2026-06-05 (stable dataset, unlikely to change)
