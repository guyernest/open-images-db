#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# download-masks.sh -- Download and extract Open Images V7 segmentation mask PNGs
# Requirement: DATA-03
# =============================================================================

# Source common.sh if not already loaded
if ! declare -f log_info >/dev/null 2>&1; then
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Hex characters for mask archive filenames (0-9, a-f)
readonly MASK_CHARS=(0 1 2 3 4 5 6 7 8 9 a b c d e f)

# Base URL for mask zip archives
readonly MASK_BASE_URL="https://storage.googleapis.com/openimages/v5/validation-masks/validation-masks"

# -----------------------------------------------------------------------------
# Download all mask zip archives, extract flat PNGs, upload to S3
# Args: $1 = temp directory, $2 = S3 bucket name
# -----------------------------------------------------------------------------

download_masks() {
  local temp_dir="$1"
  local bucket="$2"
  local zip_dir="$temp_dir/mask-zips"
  local masks_dir="$temp_dir/masks"
  local total=${#MASK_CHARS[@]}
  local count=0

  mkdir -p "$zip_dir" "$masks_dir"

  log_info "Downloading $total mask archives..."

  for char in "${MASK_CHARS[@]}"; do
    count=$((count + 1))
    local zip_file="$zip_dir/validation-masks-${char}.zip"
    local url="${MASK_BASE_URL}-${char}.zip"

    log_info "Downloading mask archives... $count/$total: validation-masks-${char}.zip"

    # Try lowercase first; if 404, try uppercase
    if ! download_file "$url" "$zip_file" 2>/dev/null; then
      local upper_char="${char^^}"
      local upper_url="${MASK_BASE_URL}-${upper_char}.zip"
      log_warn "Lowercase failed, trying uppercase: validation-masks-${upper_char}.zip"
      download_file "$upper_url" "$zip_file"
    fi

    # Extract flat (junk paths) to get PNGs without directory nesting
    unzip -o -j "$zip_file" -d "$masks_dir" >/dev/null

    # Clean up zip file after extraction to save disk space
    rm -f "$zip_file"
    log_info "Done: validation-masks-${char}.zip"
  done

  log_info "All $total mask archives downloaded and extracted"

  # Count extracted masks
  local mask_count
  mask_count=$(find "$masks_dir" -name '*.png' -type f | wc -l | tr -d ' ')
  log_info "Total mask PNGs extracted: $mask_count"

  if [[ "$mask_count" -lt 20000 ]]; then
    log_warn "Expected ~24,730 masks, found $mask_count (may be incomplete)"
  fi

  # Upload all masks to S3 raw zone
  upload_to_s3 "$masks_dir" "s3://$bucket/raw/masks/"
}
