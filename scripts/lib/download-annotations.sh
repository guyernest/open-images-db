#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# download-annotations.sh -- Download Open Images V7 validation annotation CSVs
# Requirement: DATA-01
# =============================================================================

# Source common.sh if not already loaded
if ! declare -f log_info >/dev/null 2>&1; then
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Annotation CSV URLs (Open Images V7 validation set)
readonly ANNOTATION_URLS=(
  "https://storage.googleapis.com/openimages/v7/oidv7-val-annotations-human-imagelabels.csv"
  "https://storage.googleapis.com/openimages/v7/oidv7-val-annotations-machine-imagelabels.csv"
  "https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv"
  "https://storage.googleapis.com/openimages/v5/validation-annotations-object-segmentation.csv"
  "https://storage.googleapis.com/openimages/v6/oidv6-validation-annotations-vrd.csv"
)

# -----------------------------------------------------------------------------
# Download all annotation CSVs and upload to S3
# Args: $1 = temp directory, $2 = S3 bucket name
# -----------------------------------------------------------------------------

download_annotations() {
  local temp_dir="$1"
  local bucket="$2"
  local dest_dir="$temp_dir/annotations"
  local total=${#ANNOTATION_URLS[@]}
  local count=0

  mkdir -p "$dest_dir"

  log_info "Downloading annotation CSVs..."

  for url in "${ANNOTATION_URLS[@]}"; do
    ((count++))
    local filename
    filename=$(basename "$url")
    log_info "Downloading annotations... $count/$total: $filename"
    download_file "$url" "$dest_dir/$filename"
  done

  log_info "All $total annotation CSVs downloaded"

  # Upload to S3 raw zone
  upload_to_s3 "$dest_dir" "s3://$bucket/raw/annotations/"
}
