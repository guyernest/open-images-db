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

download_metadata() {
  download_url_set "metadata" "$1" "$2" "${METADATA_URLS[@]}"
}
