#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# create-tables-full.sh -- Iceberg Table Creation for open_images_full database
#
# Wrapper around create-tables.sh that:
#   1. Sets ATHENA_DATABASE=open_images_full
#   2. Processes SQL files with warehouse/ -> warehouse-full/ prefix substitution
#      to ensure Iceberg table data lands in the correct S3 location
#
# This approach avoids modifying the shared SQL files in queries/tables/ —
# instead the warehouse prefix is substituted on-the-fly in a temp directory.
#
# Usage:
#   bash scripts/create-tables-full.sh [OPTIONS]
#
# Options:
#   --bucket NAME     Override S3 bucket (skip CloudFormation discovery)
#   --skip-reorg      Skip S3 reorganization (already done)
#   --skip-hierarchy  Skip hierarchy flattening (already done)
#   --dry-run         Show SQL statements without executing
#   --help            Show this help message
#
# Decision: create-tables-full.sh copies SQL files to a temp dir, substitutes
# warehouse/ -> warehouse-full/ in LOCATION paths, then runs with the patched
# SQL. This keeps the shared queries/tables/ SQL files unmodified and avoids
# introducing a new __WAREHOUSE__ placeholder in athena.sh.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Override ATHENA_DATABASE before sourcing athena.sh
# athena.sh uses: readonly ATHENA_DATABASE="${ATHENA_DATABASE:-open_images}"
# Setting it here before source causes athena.sh to pick it up.
export ATHENA_DATABASE="open_images_full"

# Source shared libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/athena.sh"
source "$SCRIPT_DIR/lib/reorganize-raw.sh"
source "$SCRIPT_DIR/lib/flatten-hierarchy.sh"

# -----------------------------------------------------------------------------
# Argument parsing (mirrors create-tables.sh)
# -----------------------------------------------------------------------------

BUCKET_OVERRIDE=""
SKIP_REORG=false
SKIP_HIERARCHY=false
DRY_RUN=false

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
    --skip-reorg)
      SKIP_REORG=true
      shift
      ;;
    --skip-hierarchy)
      SKIP_HIERARCHY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      sed -n '2,/^# ====/{/^# ====/d;s/^# \?//;p}' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1 (use --help for usage)"
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

main() {
  local start_time
  start_time=$(date +%s)

  log_info "============================================"
  log_info "Iceberg Table Creation Pipeline (Full Dataset)"
  log_info "Using database: $ATHENA_DATABASE (warehouse-full/ prefix)"
  log_info "============================================"

  # Step 1: Check prerequisites
  check_prerequisites

  # Step 2: Discover bucket
  local bucket
  bucket=$(discover_bucket "$BUCKET_OVERRIDE")

  # Step 3: Reorganize raw CSVs into per-table S3 prefixes
  if [[ "$SKIP_REORG" == false ]]; then
    reorganize_raw_data "$bucket"
  else
    log_info "Skipping S3 reorganization (--skip-reorg)"
  fi

  # Step 4: Flatten label hierarchy JSON to CSV
  if [[ "$SKIP_HIERARCHY" == false ]]; then
    flatten_hierarchy "$bucket"
  else
    log_info "Skipping hierarchy flattening (--skip-hierarchy)"
  fi

  # Step 5: Copy SQL files to temp dir and substitute warehouse/ -> warehouse-full/
  local original_sql_dir="$SCRIPT_DIR/../queries/tables"
  if [[ ! -d "$original_sql_dir" ]]; then
    log_error "SQL directory not found: $original_sql_dir"
    log_error "Create queries/tables/ with SQL files first"
    exit 1
  fi

  local temp_sql_dir
  temp_sql_dir=$(mktemp -d /tmp/open-images-tables-full-XXXXXX)
  trap 'rm -rf "${temp_sql_dir:-}"' EXIT

  log_info "Patching SQL files: warehouse/ -> warehouse-full/"
  for sql_file in "$original_sql_dir"/*.sql; do
    [[ -f "$sql_file" ]] || continue
    local dest="$temp_sql_dir/$(basename "$sql_file")"
    sed 's|warehouse/|warehouse-full/|g' "$sql_file" > "$dest"
  done

  # Step 6: Find and execute patched SQL files in order
  local sql_files=()
  while IFS= read -r -d '' file; do
    sql_files+=("$file")
  done < <(find "$temp_sql_dir" -name '*.sql' -type f -print0 | sort -z)

  if [[ ${#sql_files[@]} -eq 0 ]]; then
    log_warn "No SQL files found in $original_sql_dir"
    log_warn "Create SQL files (e.g., 01-images.sql) and re-run"
    exit 0
  fi

  log_info "============================================"
  log_info "Executing ${#sql_files[@]} SQL file(s)"
  log_info "============================================"

  local total_files=${#sql_files[@]}
  local failed_files=0
  local file_count=0

  for sql_file in "${sql_files[@]}"; do
    file_count=$((file_count + 1))
    log_info "File $file_count/$total_files: $(basename "$sql_file")"

    if ! process_sql_file "$sql_file" "$bucket"; then
      failed_files=$((failed_files + 1))
      # Continue processing remaining files (don't fail fast)
    fi
  done

  # Step 7: Report summary
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "Table Creation Complete"
  log_info "============================================"
  log_info "Database:              $ATHENA_DATABASE"
  log_info "SQL files processed:   $total_files"
  log_info "Succeeded:             $((total_files - failed_files))"
  if [[ $failed_files -gt 0 ]]; then
    log_error "Failed:                $failed_files"
  fi
  log_info "Elapsed time:          ${elapsed}s"

  if [[ $failed_files -gt 0 ]]; then
    log_error "$failed_files file(s) had failures -- check logs above"
    exit 1
  fi
}

main "$@"
