#!/usr/bin/env bash
# =============================================================================
# reorganize-raw-full.sh -- Copy full-dataset CSVs to per-table S3 sub-prefixes
#
# The full-load pipeline (download-annotations-full.sh) uploads CSVs to
# category sub-prefixes: raw/annotations/{labels-human,labels-machine,...}/
# This script copies them to the per-table prefixes that Athena external
# tables expect: raw/tables/{images,labels_human,...}/
#
# For tables that merge multiple source CSVs (e.g., labels = human + machine),
# all CSVs go into the same raw/tables/ prefix — Athena reads all files.
#
# Idempotent: uses aws s3 sync (skips unchanged files).
# =============================================================================

if ! declare -f log_info >/dev/null 2>&1; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/common.sh"
fi

# -----------------------------------------------------------------------------
# Sync a source prefix to a per-table destination prefix
# Args: $1 = bucket, $2 = source prefix, $3 = dest prefix
# -----------------------------------------------------------------------------

sync_raw_prefix() {
  local bucket="$1"
  local src_prefix="$2"
  local dest_prefix="$3"

  log_info "  Syncing: s3://${bucket}/${src_prefix} -> s3://${bucket}/${dest_prefix}"
  aws s3 sync \
    "s3://${bucket}/${src_prefix}" \
    "s3://${bucket}/${dest_prefix}" \
    "${AWS_PROFILE_FLAG[@]}" \
    --no-progress || {
    log_error "Failed to sync ${src_prefix} -> ${dest_prefix}"
    return 1
  }
}

# -----------------------------------------------------------------------------
# Reorganize full-dataset CSVs into per-table S3 sub-prefixes
# Args: $1 = bucket name
# -----------------------------------------------------------------------------

reorganize_raw_data() {
  local bucket="$1"
  local errors=0

  log_info "============================================"
  log_info "Reorganizing full-dataset CSVs into per-table prefixes"
  log_info "============================================"

  # Images metadata (3 splits: validation, train, test)
  sync_raw_prefix "$bucket" \
    "raw/annotations/metadata/" \
    "raw/tables/images/" \
    || errors=$((errors + 1))

  # Class descriptions (shared across splits — already in metadata/)
  # Copy just the class description files to their own prefix
  aws s3 cp "s3://${bucket}/raw/annotations/metadata/oidv7-class-descriptions.csv" \
    "s3://${bucket}/raw/tables/class_descriptions/oidv7-class-descriptions.csv" \
    "${AWS_PROFILE_FLAG[@]}" --no-progress || errors=$((errors + 1))

  # Labels: human + machine go to same prefix (UNION ALL in SQL)
  sync_raw_prefix "$bucket" \
    "raw/annotations/labels-human/" \
    "raw/tables/labels_human/" \
    || errors=$((errors + 1))

  sync_raw_prefix "$bucket" \
    "raw/annotations/labels-machine/" \
    "raw/tables/labels_machine/" \
    || errors=$((errors + 1))

  # Bounding boxes (3 splits)
  sync_raw_prefix "$bucket" \
    "raw/annotations/bbox/" \
    "raw/tables/bounding_boxes/" \
    || errors=$((errors + 1))

  # Segmentation masks (3 splits)
  sync_raw_prefix "$bucket" \
    "raw/annotations/segmentation/" \
    "raw/tables/masks/" \
    || errors=$((errors + 1))

  # Visual relationships (3 splits)
  sync_raw_prefix "$bucket" \
    "raw/annotations/vrd/" \
    "raw/tables/relationships/" \
    || errors=$((errors + 1))

  if [[ $errors -gt 0 ]]; then
    log_error "Reorganization failed with $errors error(s)"
    return 1
  fi

  log_info "Full-dataset reorganization complete"
}
