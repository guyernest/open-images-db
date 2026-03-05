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

download_annotations() {
  download_url_set "annotations" "$1" "$2" "${ANNOTATION_URLS[@]}"
}
