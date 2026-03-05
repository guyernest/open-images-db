#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# create-tables.sh -- Iceberg Table Creation Runner
#
# Executes SQL files from queries/tables/ against Athena to create Iceberg
# tables. Each SQL file may contain multiple statements separated by
# semicolons; each statement is executed individually via start-query-execution.
#
# Before creating tables, reorganizes raw CSVs into per-table S3 prefixes
# and flattens the label hierarchy JSON to CSV.
#
# Usage:
#   bash scripts/create-tables.sh [OPTIONS]
#
# Options:
#   --bucket NAME     Override S3 bucket (skip CloudFormation discovery)
#   --skip-reorg      Skip S3 reorganization (already done)
#   --skip-hierarchy  Skip hierarchy flattening (already done)
#   --dry-run         Show SQL statements without executing
#   --help            Show this help message
#
# Requirements: TBL-08, TBL-09
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library files
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/reorganize-raw.sh"
source "$SCRIPT_DIR/lib/flatten-hierarchy.sh"

# Athena configuration
readonly ATHENA_WORKGROUP="open-images"
readonly ATHENA_DATABASE="open_images"
readonly ATHENA_CATALOG="AwsDataCatalog"

# -----------------------------------------------------------------------------
# Argument parsing
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
      head -25 "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *)
      log_error "Unknown option: $1 (use --help for usage)"
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Execute a single SQL statement via Athena and wait for completion
# Args: $1 = SQL statement, $2 = description
# Returns: 0 on success, 1 on failure
# Sets: LAST_QUERY_ID (for result retrieval)
# -----------------------------------------------------------------------------

LAST_QUERY_ID=""

run_athena_query() {
  local sql="$1"
  local description="$2"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would execute: $description"
    log_info "  SQL: ${sql:0:120}..."
    return 0
  fi

  local query_id
  query_id=$(aws athena start-query-execution \
    --query-string "$sql" \
    --work-group "$ATHENA_WORKGROUP" \
    --query-execution-context "Database=${ATHENA_DATABASE},Catalog=${ATHENA_CATALOG}" \
    --profile "$AWS_PROFILE" \
    --output text \
    --query 'QueryExecutionId') || {
    log_error "Failed to start query: $description"
    return 1
  }

  LAST_QUERY_ID="$query_id"
  log_info "Started: $description (ID: $query_id)"

  # Poll until complete
  local status="RUNNING"
  while [[ "$status" == "RUNNING" || "$status" == "QUEUED" ]]; do
    sleep 2
    status=$(aws athena get-query-execution \
      --query-execution-id "$query_id" \
      --profile "$AWS_PROFILE" \
      --output text \
      --query 'QueryExecution.Status.State') || {
      log_error "Failed to check query status: $query_id"
      return 1
    }
  done

  if [[ "$status" == "SUCCEEDED" ]]; then
    log_info "Succeeded: $description"
    return 0
  else
    local reason
    reason=$(aws athena get-query-execution \
      --query-execution-id "$query_id" \
      --profile "$AWS_PROFILE" \
      --output text \
      --query 'QueryExecution.Status.StateChangeReason' 2>/dev/null || echo "Unknown reason")
    log_error "Failed ($status): $description -- $reason"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Process a single SQL file: split on semicolons, execute each statement
# Args: $1 = SQL file path, $2 = bucket name
# Returns: 0 if all statements succeed, 1 if any fail
# -----------------------------------------------------------------------------

process_sql_file() {
  local sql_file="$1"
  local bucket="$2"
  local filename
  filename=$(basename "$sql_file" .sql)
  local file_errors=0
  local stmt_count=0

  log_info "--------------------------------------------"
  log_info "Processing: $filename"
  log_info "--------------------------------------------"

  # Read the file and substitute the bucket placeholder
  local sql_content
  sql_content=$(sed "s|__BUCKET__|${bucket}|g" "$sql_file")

  # Split on semicolons, trim whitespace, skip empty statements
  local IFS=";"
  local statements=()
  for stmt in $sql_content; do
    # Trim leading/trailing whitespace
    stmt=$(echo "$stmt" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    # Skip empty statements and comment-only blocks
    if [[ -n "$stmt" ]] && ! echo "$stmt" | grep -qE '^(--.*)?$'; then
      statements+=("$stmt")
    fi
  done
  unset IFS

  local total=${#statements[@]}
  if [[ $total -eq 0 ]]; then
    log_warn "No SQL statements found in $filename"
    return 0
  fi

  log_info "Found $total statement(s) in $filename"

  for stmt in "${statements[@]}"; do
    stmt_count=$((stmt_count + 1))

    # Build a description from the first meaningful line
    local desc
    desc=$(echo "$stmt" | grep -v '^--' | grep -v '^$' | head -1 | sed 's/[[:space:]]*$//' | cut -c1-80)

    if ! run_athena_query "$stmt" "$filename [$stmt_count/$total]: $desc"; then
      file_errors=$((file_errors + 1))
    fi
  done

  if [[ $file_errors -gt 0 ]]; then
    log_error "$filename: $file_errors of $total statements failed"
    return 1
  fi

  log_info "$filename: all $total statements succeeded"
  return 0
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

main() {
  local start_time
  start_time=$(date +%s)

  log_info "============================================"
  log_info "Iceberg Table Creation Pipeline"
  log_info "============================================"

  # Step 1: Check prerequisites (jq also needed for hierarchy flattener)
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

  # Step 5: Find and execute SQL files in order
  local sql_dir="$SCRIPT_DIR/../queries/tables"
  if [[ ! -d "$sql_dir" ]]; then
    log_error "SQL directory not found: $sql_dir"
    log_error "Create queries/tables/ with SQL files first"
    exit 1
  fi

  local sql_files=()
  while IFS= read -r -d '' file; do
    sql_files+=("$file")
  done < <(find "$sql_dir" -name '*.sql' -type f -print0 | sort -z)

  if [[ ${#sql_files[@]} -eq 0 ]]; then
    log_warn "No SQL files found in $sql_dir"
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

  # Step 6: Report summary
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "Table Creation Complete"
  log_info "============================================"
  log_info "SQL files processed: $total_files"
  log_info "Succeeded:           $((total_files - failed_files))"
  if [[ $failed_files -gt 0 ]]; then
    log_error "Failed:              $failed_files"
  fi
  log_info "Elapsed time:        ${elapsed}s"

  if [[ $failed_files -gt 0 ]]; then
    log_error "$failed_files file(s) had failures -- check logs above"
    exit 1
  fi
}

main "$@"
