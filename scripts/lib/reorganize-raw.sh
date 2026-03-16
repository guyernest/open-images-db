#!/usr/bin/env bash
# =============================================================================
# reorganize-raw.sh -- Copy raw CSVs to per-table S3 sub-prefixes
#
# Athena external tables use LOCATION as a directory prefix and read ALL files
# under it. Since multiple CSVs share raw/annotations/ and raw/metadata/,
# each CSV must be copied to its own sub-prefix so external tables only see
# the correct file.
#
# Idempotent: checks if destination already exists before copying.
# Uses 'cp' (not 'mv') to keep originals intact.
# =============================================================================

# Source common.sh if not already loaded (for standalone testing)
if ! declare -f log_info >/dev/null 2>&1; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/common.sh"
fi

# -----------------------------------------------------------------------------
# Copy a single file to a per-table S3 sub-prefix (idempotent)
# Args: $1 = bucket, $2 = source key, $3 = dest key
# -----------------------------------------------------------------------------

copy_raw_file() {
  local bucket="$1"
  local src_key="$2"
  local dest_key="$3"

  log_info "  Copying: s3://${bucket}/${src_key} -> s3://${bucket}/${dest_key}"
  aws s3 cp \
    "s3://${bucket}/${src_key}" \
    "s3://${bucket}/${dest_key}" \
    "${AWS_PROFILE_FLAG[@]}" \
    --no-progress || {
    log_error "Failed to copy ${src_key} -> ${dest_key}"
    return 1
  }
}

# -----------------------------------------------------------------------------
# Reorganize all raw CSVs into per-table S3 sub-prefixes
# Args: $1 = bucket name
# -----------------------------------------------------------------------------

reorganize_raw_data() {
  local bucket="$1"
  local errors=0

  log_info "============================================"
  log_info "Reorganizing raw CSVs into per-table prefixes"
  log_info "============================================"

  # Metadata files
  copy_raw_file "$bucket" \
    "raw/metadata/validation-images-with-rotation.csv" \
    "raw/tables/images/validation-images-with-rotation.csv" \
    || errors=$((errors + 1))

  copy_raw_file "$bucket" \
    "raw/metadata/oidv7-class-descriptions.csv" \
    "raw/tables/class_descriptions/oidv7-class-descriptions.csv" \
    || errors=$((errors + 1))

  # Annotation files
  copy_raw_file "$bucket" \
    "raw/annotations/oidv7-val-annotations-human-imagelabels.csv" \
    "raw/tables/labels_human/oidv7-val-annotations-human-imagelabels.csv" \
    || errors=$((errors + 1))

  copy_raw_file "$bucket" \
    "raw/annotations/oidv7-val-annotations-machine-imagelabels.csv" \
    "raw/tables/labels_machine/oidv7-val-annotations-machine-imagelabels.csv" \
    || errors=$((errors + 1))

  copy_raw_file "$bucket" \
    "raw/annotations/validation-annotations-bbox.csv" \
    "raw/tables/bounding_boxes/validation-annotations-bbox.csv" \
    || errors=$((errors + 1))

  copy_raw_file "$bucket" \
    "raw/annotations/validation-annotations-object-segmentation.csv" \
    "raw/tables/masks/validation-annotations-object-segmentation.csv" \
    || errors=$((errors + 1))

  copy_raw_file "$bucket" \
    "raw/annotations/oidv6-validation-annotations-vrd.csv" \
    "raw/tables/relationships/oidv6-validation-annotations-vrd.csv" \
    || errors=$((errors + 1))

  if [[ $errors -gt 0 ]]; then
    log_error "Reorganization failed with $errors error(s)"
    return 1
  fi

  log_info "Raw data reorganization complete (7 files -> per-table prefixes)"
}
