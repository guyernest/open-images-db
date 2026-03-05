#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# verify-tables.sh -- Smoke test for Iceberg tables in open_images database
#
# Verifies that all 7 Iceberg tables exist, have rows, and that key columns
# have the correct types (doubles, booleans).
#
# Usage:
#   bash scripts/verify-tables.sh [OPTIONS]
#
# Options:
#   --bucket NAME   Override S3 bucket (skip CloudFormation discovery)
#   --quick         Only check row counts (skip type verification)
#   --help          Show this help message
#
# Requirements: TBL-01 through TBL-09
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared functions
source "$SCRIPT_DIR/lib/common.sh"

# Athena configuration
readonly ATHENA_WORKGROUP="open-images"
readonly ATHENA_DATABASE="open_images"
readonly ATHENA_CATALOG="AwsDataCatalog"

# Expected tables
readonly EXPECTED_TABLES=(
  images
  class_descriptions
  labels
  bounding_boxes
  masks
  relationships
  label_hierarchy
)

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

BUCKET_OVERRIDE=""
QUICK_MODE=false

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
    --quick)
      QUICK_MODE=true
      shift
      ;;
    --help)
      head -18 "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *)
      log_error "Unknown option: $1 (use --help for usage)"
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Execute an Athena query and return the result value
# Args: $1 = SQL statement, $2 = description
# Prints: the result value (first column, first data row)
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------

run_athena_query_with_result() {
  local sql="$1"
  local description="$2"

  # Start query execution
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

  if [[ "$status" != "SUCCEEDED" ]]; then
    local reason
    reason=$(aws athena get-query-execution \
      --query-execution-id "$query_id" \
      --profile "$AWS_PROFILE" \
      --output text \
      --query 'QueryExecution.Status.StateChangeReason' 2>/dev/null || echo "Unknown reason")
    log_error "Query failed ($status): $description -- $reason"
    return 1
  fi

  # Get the result (first data row, first column)
  local result
  result=$(aws athena get-query-results \
    --query-execution-id "$query_id" \
    --profile "$AWS_PROFILE" \
    --output text \
    --query 'ResultSet.Rows[1].Data[0].VarCharValue') || {
    log_error "Failed to get query results: $description"
    return 1
  }

  echo "$result"
}

# -----------------------------------------------------------------------------
# Verify a table has rows (count > 0)
# Args: $1 = table name
# Returns: 0 if count > 0, 1 otherwise
# -----------------------------------------------------------------------------

verify_row_count() {
  local table="$1"
  local sql="SELECT COUNT(*) AS cnt FROM ${ATHENA_DATABASE}.${table}"

  log_info "Checking row count: $table"

  local count
  count=$(run_athena_query_with_result "$sql" "count($table)") || return 1

  if [[ -z "$count" || "$count" == "0" || "$count" == "None" ]]; then
    log_error "FAIL: $table has 0 rows"
    return 1
  fi

  log_info "PASS: $table has $count rows"
  return 0
}

# -----------------------------------------------------------------------------
# Verify a column has the expected type
# Args: $1 = table, $2 = column, $3 = expected type (e.g., "double", "boolean")
# Returns: 0 if type matches, 1 otherwise
# -----------------------------------------------------------------------------

verify_column_type() {
  local table="$1"
  local column="$2"
  local expected_type="$3"
  local sql="SELECT typeof(${column}) AS t FROM ${ATHENA_DATABASE}.${table} LIMIT 1"

  log_info "Checking type: $table.$column (expect $expected_type)"

  local actual_type
  actual_type=$(run_athena_query_with_result "$sql" "typeof($table.$column)") || return 1

  if [[ "$actual_type" != "$expected_type" ]]; then
    log_error "FAIL: $table.$column is '$actual_type', expected '$expected_type'"
    return 1
  fi

  log_info "PASS: $table.$column is $actual_type"
  return 0
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

main() {
  local start_time
  start_time=$(date +%s)

  log_info "============================================"
  log_info "Iceberg Table Verification"
  log_info "============================================"

  # Check prerequisites
  check_prerequisites

  # Discover bucket (not strictly needed for queries, but validates stack)
  discover_bucket "$BUCKET_OVERRIDE" >/dev/null

  local total_checks=0
  local passed=0
  local failed=0

  # Phase 1: Row count checks for all tables
  log_info "--------------------------------------------"
  log_info "Phase 1: Row count verification"
  log_info "--------------------------------------------"

  for table in "${EXPECTED_TABLES[@]}"; do
    total_checks=$((total_checks + 1))
    if verify_row_count "$table"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  # Phase 2: Column type checks (skip in --quick mode)
  if [[ "$QUICK_MODE" == false ]]; then
    log_info "--------------------------------------------"
    log_info "Phase 2: Column type verification"
    log_info "--------------------------------------------"

    # Bounding boxes: coordinates should be double
    total_checks=$((total_checks + 1))
    if verify_column_type "bounding_boxes" "x_min" "double"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi

    # Bounding boxes: boolean flags
    total_checks=$((total_checks + 1))
    if verify_column_type "bounding_boxes" "is_occluded" "boolean"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi

    # Labels: confidence should be double
    total_checks=$((total_checks + 1))
    if verify_column_type "labels" "confidence" "double"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  else
    log_info "Skipping type checks (--quick mode)"
  fi

  # Report results
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "Verification Complete"
  log_info "============================================"
  log_info "Total checks: $total_checks"
  log_info "Passed:       $passed"
  if [[ $failed -gt 0 ]]; then
    log_error "Failed:       $failed"
  else
    log_info "Failed:       0"
  fi
  log_info "Elapsed time: ${elapsed}s"

  if [[ $failed -gt 0 ]]; then
    log_error "$failed check(s) failed"
    exit 1
  fi

  log_info "All checks passed"
}

main "$@"
