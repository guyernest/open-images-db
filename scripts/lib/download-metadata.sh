#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# download-metadata.sh -- Download Open Images V7 class descriptions and image metadata
# Requirement: DATA-02
# =============================================================================

# Source common.sh if not already loaded
if ! declare -f log_info >/dev/null 2>&1; then
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Metadata file URLs
readonly METADATA_URLS=(
  "https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions.csv"
  "https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv"
  "https://storage.googleapis.com/openimages/2018_04/validation/validation-images-with-rotation.csv"
)

# -----------------------------------------------------------------------------
# Download all metadata files and upload to S3
# Args: $1 = temp directory, $2 = S3 bucket name
# -----------------------------------------------------------------------------

download_metadata() {
  local temp_dir="$1"
  local bucket="$2"
  local dest_dir="$temp_dir/metadata"
  local total=${#METADATA_URLS[@]}
  local count=0

  mkdir -p "$dest_dir"

  log_info "Downloading metadata files..."

  for url in "${METADATA_URLS[@]}"; do
    ((count++))
    local filename
    filename=$(basename "$url")
    log_info "Downloading metadata... $count/$total: $filename"
    download_file "$url" "$dest_dir/$filename"
  done

  log_info "All $total metadata files downloaded"

  # Upload to S3 raw zone
  upload_to_s3 "$dest_dir" "s3://$bucket/raw/metadata/"
}
