#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# download-all.sh -- Open Images V7 Data Acquisition Pipeline
#
# Downloads validation set annotation CSVs, image metadata, and segmentation
# mask PNGs from public HTTPS URLs, then uploads to S3 raw zone.
#
# Usage:
#   bash scripts/download-all.sh [OPTIONS]
#
# Options:
#   --bucket NAME     Override S3 bucket (skip CloudFormation discovery)
#   --validate-only   Skip downloads, run S3 validation only
#   --skip-masks      Download annotations and metadata only (quick test)
#   --help            Show this help message
#
# Requirements: DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library files
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/download-annotations.sh"
source "$SCRIPT_DIR/lib/download-metadata.sh"
source "$SCRIPT_DIR/lib/download-masks.sh"

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

BUCKET_OVERRIDE=""
VALIDATE_ONLY=false
SKIP_MASKS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET_OVERRIDE="${2:-}"
      if [[ -z "$BUCKET_OVERRIDE" ]]; then
        log_error "--bucket requires a value"
        exit 1
      fi
      shift 2
      ;;
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    --skip-masks)
      SKIP_MASKS=true
      shift
      ;;
    --help)
      head -20 "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *)
      log_error "Unknown option: $1 (use --help for usage)"
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Post-download validation: check file counts and sizes in S3
# -----------------------------------------------------------------------------

validate_s3_data() {
  local bucket="$1"
  local errors=0

  log_info "============================================"
  log_info "Validating data in S3..."
  log_info "============================================"

  # Count annotation CSVs in S3
  local annotation_count
  annotation_count=$(aws s3 ls "s3://$bucket/raw/annotations/" \
    --profile "$AWS_PROFILE" 2>/dev/null | grep -c '\.csv$' || echo "0")
  if [[ "$annotation_count" -lt 5 ]]; then
    log_error "Expected 5 annotation CSVs in S3, found $annotation_count"
    ((errors++))
  else
    log_info "Annotations: $annotation_count CSV files (expected 5)"
  fi

  # Count metadata files in S3
  local metadata_count
  metadata_count=$(aws s3 ls "s3://$bucket/raw/metadata/" \
    --profile "$AWS_PROFILE" 2>/dev/null | grep -c '\.csv$' || echo "0")
  if [[ "$metadata_count" -lt 3 ]]; then
    log_error "Expected 3 metadata files in S3, found $metadata_count"
    ((errors++))
  else
    log_info "Metadata: $metadata_count CSV files (expected 3)"
  fi

  # Count mask PNGs in S3 (using summarize for total count)
  if [[ "$SKIP_MASKS" == false ]]; then
    local mask_summary
    mask_summary=$(aws s3 ls "s3://$bucket/raw/masks/" \
      --profile "$AWS_PROFILE" --summarize --recursive 2>/dev/null || echo "")
    local mask_count
    mask_count=$(echo "$mask_summary" | grep 'Total Objects:' | awk '{print $NF}' || echo "0")

    if [[ -z "$mask_count" || "$mask_count" == "0" ]]; then
      log_error "No mask PNGs found in S3"
      ((errors++))
    elif [[ "$mask_count" -lt 20000 ]]; then
      log_warn "Masks: $mask_count PNGs (expected ~24,730 -- may be incomplete)"
    else
      log_info "Masks: $mask_count PNGs (expected ~24,730)"
    fi

    # Report total size for masks
    local mask_size
    mask_size=$(echo "$mask_summary" | grep 'Total Size:' | sed 's/.*Total Size: *//' || echo "unknown")
    log_info "Mask total size: $mask_size bytes"
  fi

  # Report sizes per prefix
  log_info "--- Size summary ---"
  for prefix in annotations metadata; do
    local size_info
    size_info=$(aws s3 ls "s3://$bucket/raw/$prefix/" \
      --profile "$AWS_PROFILE" --summarize --recursive 2>/dev/null \
      | grep 'Total Size:' | sed 's/.*Total Size: *//' || echo "unknown")
    log_info "  raw/$prefix/: $size_info bytes"
  done

  if [[ $errors -gt 0 ]]; then
    log_error "Validation found $errors error(s)"
    return 1
  fi

  log_info "Validation passed"
  return 0
}

# -----------------------------------------------------------------------------
# Generate manifest.json listing all files in raw/ prefix
# -----------------------------------------------------------------------------

generate_manifest() {
  local bucket="$1"
  local temp_dir="$2"

  log_info "Generating manifest.json..."

  aws s3api list-objects-v2 \
    --bucket "$bucket" \
    --prefix "raw/" \
    --profile "$AWS_PROFILE" \
    --query 'Contents[].{Key:Key,Size:Size,LastModified:LastModified}' \
    --output json 2>/dev/null \
    | jq '.' > "$temp_dir/manifest.json"

  local entry_count
  entry_count=$(jq 'length' "$temp_dir/manifest.json" 2>/dev/null || echo "0")
  log_info "Manifest contains $entry_count entries"

  # Upload manifest to S3
  aws s3 cp "$temp_dir/manifest.json" "s3://$bucket/raw/manifest.json" \
    --profile "$AWS_PROFILE" \
    --no-progress
  log_info "Manifest uploaded to s3://$bucket/raw/manifest.json"
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

main() {
  local start_time
  start_time=$(date +%s)

  log_info "============================================"
  log_info "Open Images V7 Data Acquisition Pipeline"
  log_info "============================================"

  # Step 1: Check prerequisites
  check_prerequisites

  # Step 2: Discover or use provided bucket name
  local bucket
  bucket=$(discover_bucket "$BUCKET_OVERRIDE")

  # Step 3: Handle validate-only mode
  if [[ "$VALIDATE_ONLY" == true ]]; then
    log_info "Running in validate-only mode (skipping downloads)"
    validate_s3_data "$bucket"
    return $?
  fi

  # Step 4: Create temp directories
  mkdir -p "$TEMP_DIR"/{annotations,metadata,masks,mask-zips}
  log_info "Temp directory: $TEMP_DIR"

  # Step 5: Download annotations (DATA-01)
  log_info "============================================"
  log_info "Phase 1/3: Annotation CSVs"
  log_info "============================================"
  download_annotations "$TEMP_DIR" "$bucket"

  # Step 6: Download metadata (DATA-02)
  log_info "============================================"
  log_info "Phase 2/3: Metadata files"
  log_info "============================================"
  download_metadata "$TEMP_DIR" "$bucket"

  # Step 7: Download masks (DATA-03) unless skipped
  if [[ "$SKIP_MASKS" == false ]]; then
    log_info "============================================"
    log_info "Phase 3/3: Segmentation masks"
    log_info "============================================"
    download_masks "$TEMP_DIR" "$bucket"
  else
    log_warn "Skipping mask download (--skip-masks flag set)"
  fi

  # Step 8: Post-download validation
  validate_s3_data "$bucket"

  # Step 9: Generate manifest
  generate_manifest "$bucket" "$TEMP_DIR"

  # Step 10: Print summary
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "Pipeline complete"
  log_info "============================================"
  log_info "Bucket:        $bucket"
  log_info "Annotations:   5 CSV files -> s3://$bucket/raw/annotations/"
  log_info "Metadata:      3 CSV files -> s3://$bucket/raw/metadata/"
  if [[ "$SKIP_MASKS" == false ]]; then
    log_info "Masks:         ~24,730 PNGs -> s3://$bucket/raw/masks/"
  fi
  log_info "Manifest:      s3://$bucket/raw/manifest.json"
  log_info "Elapsed time:  ${elapsed}s"
}

main "$@"
