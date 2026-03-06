#!/usr/bin/env bash
# =============================================================================
# flatten-hierarchy.sh -- Flatten Open Images label hierarchy JSON to CSV
#
# Downloads the bbox_labels_600_hierarchy.json from Google Storage and uses
# jq recursive descent to extract all parent-child edges from both
# Subcategory and Part arrays. Outputs a CSV with header: parent_mid,child_mid
#
# Uploads result to s3://BUCKET/raw/tables/label_hierarchy/label_hierarchy.csv
#
# Idempotent: always regenerates (fast operation, ~600 edges).
# =============================================================================

# Source common.sh if not already loaded (for standalone testing)
if ! declare -f log_info >/dev/null 2>&1; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/common.sh"
fi

# Hierarchy JSON URL (stable public URL from Open Images)
readonly HIERARCHY_URL="https://storage.googleapis.com/openimages/2018_04/bbox_labels_600_hierarchy.json"

# -----------------------------------------------------------------------------
# Flatten hierarchy JSON to parent-child CSV and upload to S3
# Args: $1 = bucket name
# -----------------------------------------------------------------------------

flatten_hierarchy() {
  local bucket="$1"

  log_info "============================================"
  log_info "Flattening label hierarchy to CSV"
  log_info "============================================"

  # Create temp files (X's must be at end of template on macOS)
  local temp_json
  temp_json=$(mktemp "${TMPDIR:-/tmp}/hierarchy_json_XXXXXX")
  local temp_csv
  temp_csv=$(mktemp "${TMPDIR:-/tmp}/hierarchy_csv_XXXXXX")

  # Ensure cleanup on exit from this function
  # Use double-quotes to eagerly expand paths (locals are gone when trap fires)
  trap "rm -f '$temp_json' '$temp_csv'" RETURN

  # Download hierarchy JSON (reuses common.sh download_file with retry + empty check)
  # Remove the mktemp empty file first — download_file uses curl -z which skips
  # download if file exists (conditional on modification time)
  rm -f "$temp_json"
  log_info "Downloading hierarchy JSON from $HIERARCHY_URL"
  download_file "$HIERARCHY_URL" "$temp_json"
  log_info "Downloaded hierarchy JSON ($(wc -c < "$temp_json" | tr -d ' ') bytes)"

  # Flatten using jq recursive descent
  # Extracts parent->child edges from both Subcategory and Part arrays
  log_info "Extracting parent-child edges with jq..."

  {
    echo "parent_mid,child_mid"
    jq -r '
      def edges:
        .LabelName as $parent |
        ((.Subcategory // [])[] | "\($parent),\(.LabelName)", edges),
        ((.Part // [])[] | "\($parent),\(.LabelName)", edges);
      edges
    ' "$temp_json"
  } > "$temp_csv" || {
    log_error "jq flattening failed"
    return 1
  }

  local edge_count
  edge_count=$(($(wc -l < "$temp_csv" | tr -d ' ') - 1))
  log_info "Extracted $edge_count parent-child edges"

  if [[ $edge_count -eq 0 ]]; then
    log_error "No edges extracted from hierarchy JSON"
    return 1
  fi

  # Upload to S3
  local s3_dest="s3://${bucket}/raw/tables/label_hierarchy/label_hierarchy.csv"
  log_info "Uploading to $s3_dest"

  aws s3 cp "$temp_csv" "$s3_dest" \
    --profile "$AWS_PROFILE" \
    --no-progress || {
    log_error "Failed to upload hierarchy CSV to S3"
    return 1
  }

  log_info "Label hierarchy CSV uploaded ($edge_count edges)"
}
