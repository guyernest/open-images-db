#!/usr/bin/env bash
# =============================================================================
# download-annotations-full.sh -- Multi-split annotation URL inventory
#
# Defines annotation CSV URLs for all three Open Images V7 splits:
# train, validation, and test. Provides download_annotations_full() function
# that downloads all annotation categories and uploads to S3.
#
# Source: https://storage.googleapis.com/openimages/web/download_v7.html
# Confidence: HIGH (official Open Images V7 download page)
#
# Categories:
#   labels-human    -- Human-verified image-level labels (3 splits)
#   labels-machine  -- Machine-generated image-level labels (3 splits)
#   bbox            -- Bounding box annotations (3 splits)
#   segmentation    -- Instance segmentation CSV metadata (3 splits, no PNGs)
#   vrd             -- Visual relationship detection (3 splits)
#   metadata        -- Class descriptions + image rotation CSVs (shared)
# =============================================================================

# Source common.sh if not already loaded (guard pattern)
if ! declare -f log_info >/dev/null 2>&1; then
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# -----------------------------------------------------------------------------
# Image-level labels -- human-verified
# Source: oidv7-{train,val,test}-annotations-human-imagelabels.csv
# -----------------------------------------------------------------------------

LABEL_HUMAN_URLS=(
  "https://storage.googleapis.com/openimages/v7/oidv7-train-annotations-human-imagelabels.csv"
  "https://storage.googleapis.com/openimages/v7/oidv7-val-annotations-human-imagelabels.csv"
  "https://storage.googleapis.com/openimages/v7/oidv7-test-annotations-human-imagelabels.csv"
)

# -----------------------------------------------------------------------------
# Image-level labels -- machine-generated
# Source: oidv7-{train,val,test}-annotations-machine-imagelabels.csv
# -----------------------------------------------------------------------------

LABEL_MACHINE_URLS=(
  "https://storage.googleapis.com/openimages/v7/oidv7-train-annotations-machine-imagelabels.csv"
  "https://storage.googleapis.com/openimages/v7/oidv7-val-annotations-machine-imagelabels.csv"
  "https://storage.googleapis.com/openimages/v7/oidv7-test-annotations-machine-imagelabels.csv"
)

# -----------------------------------------------------------------------------
# Bounding box annotations
# Train: v6 (oidv6-train-annotations-bbox.csv)
# Val/Test: v5 (validation-annotations-bbox.csv, test-annotations-bbox.csv)
# -----------------------------------------------------------------------------

BBOX_URLS=(
  "https://storage.googleapis.com/openimages/v6/oidv6-train-annotations-bbox.csv"
  "https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv"
  "https://storage.googleapis.com/openimages/v5/test-annotations-bbox.csv"
)

# -----------------------------------------------------------------------------
# Instance segmentation -- CSV metadata only (NOT PNG masks)
# PNG masks are ~200+ GB for train split -- explicitly out of scope.
# Source: {train,validation,test}-annotations-object-segmentation.csv (v5)
# -----------------------------------------------------------------------------

SEGMENTATION_URLS=(
  "https://storage.googleapis.com/openimages/v5/train-annotations-object-segmentation.csv"
  "https://storage.googleapis.com/openimages/v5/validation-annotations-object-segmentation.csv"
  "https://storage.googleapis.com/openimages/v5/test-annotations-object-segmentation.csv"
)

# -----------------------------------------------------------------------------
# Visual relationship detection (VRD)
# Source: oidv6-{train,validation,test}-annotations-vrd.csv
# -----------------------------------------------------------------------------

VRD_URLS=(
  "https://storage.googleapis.com/openimages/v6/oidv6-train-annotations-vrd.csv"
  "https://storage.googleapis.com/openimages/v6/oidv6-validation-annotations-vrd.csv"
  "https://storage.googleapis.com/openimages/v6/oidv6-test-annotations-vrd.csv"
)

# -----------------------------------------------------------------------------
# Metadata -- class descriptions and image rotation CSVs
# These are shared across splits (no separate per-split metadata).
# Includes: class descriptions (v7), boxable descriptions (v7),
#           and rotation CSVs for validation, train, and test.
# -----------------------------------------------------------------------------

METADATA_URLS=(
  "https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions.csv"
  "https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv"
  "https://storage.googleapis.com/openimages/2018_04/validation/validation-images-with-rotation.csv"
  "https://storage.googleapis.com/openimages/2018_04/train/train-images-boxable-with-rotation.csv"
  "https://storage.googleapis.com/openimages/2018_04/test/test-images-with-rotation.csv"
)

# -----------------------------------------------------------------------------
# Download all annotation categories for all splits
# Args: $1 = temp directory for local download staging
#       $2 = S3 bucket name (destination)
# -----------------------------------------------------------------------------

download_annotations_full() {
  local temp_dir="$1"
  local bucket="$2"

  log_info "============================================"
  log_info "Downloading full dataset annotations (all splits)"
  log_info "============================================"
  log_info "Categories: labels-human, labels-machine, bbox, segmentation, vrd, metadata"
  log_info "Total URLs: $((${#LABEL_HUMAN_URLS[@]} + ${#LABEL_MACHINE_URLS[@]} + ${#BBOX_URLS[@]} + ${#SEGMENTATION_URLS[@]} + ${#VRD_URLS[@]} + ${#METADATA_URLS[@]}))"

  download_url_set "annotations/labels-human"   "$temp_dir" "$bucket" "${LABEL_HUMAN_URLS[@]}"
  download_url_set "annotations/labels-machine" "$temp_dir" "$bucket" "${LABEL_MACHINE_URLS[@]}"
  download_url_set "annotations/bbox"           "$temp_dir" "$bucket" "${BBOX_URLS[@]}"
  download_url_set "annotations/segmentation"   "$temp_dir" "$bucket" "${SEGMENTATION_URLS[@]}"
  download_url_set "annotations/vrd"            "$temp_dir" "$bucket" "${VRD_URLS[@]}"
  download_url_set "annotations/metadata"       "$temp_dir" "$bucket" "${METADATA_URLS[@]}"

  log_info "All annotation categories downloaded and uploaded to s3://$bucket/raw/"
}
