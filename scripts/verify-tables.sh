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
source "$SCRIPT_DIR/lib/athena.sh"

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

# Type checks: table:column:expected_type
readonly TYPE_CHECKS=(
  "bounding_boxes:x_min:double"
  "bounding_boxes:is_occluded:boolean"
  "labels:confidence:double"
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

  # Discover bucket (validates stack is deployed)
  discover_bucket "$BUCKET_OVERRIDE" >/dev/null

  local total_checks=0
  local passed=0
  local failed=0

  # Phase 1: Table existence checks (SELECT 1 LIMIT 1 avoids full scan)
  log_info "--------------------------------------------"
  log_info "Phase 1: Table existence verification"
  log_info "--------------------------------------------"

  for table in "${EXPECTED_TABLES[@]}"; do
    total_checks=$((total_checks + 1))
    local sql="SELECT 1 FROM ${ATHENA_DATABASE}.${table} LIMIT 1"
    log_info "Checking: $table"

    local result
    if result=$(athena_query_scalar "$sql" "exists($table)") && [[ -n "$result" ]]; then
      log_info "PASS: $table has rows"
      passed=$((passed + 1))
    else
      log_error "FAIL: $table has no rows or does not exist"
      failed=$((failed + 1))
    fi
  done

  # Phase 2: Column type checks (skip in --quick mode)
  if [[ "$QUICK_MODE" == false ]]; then
    log_info "--------------------------------------------"
    log_info "Phase 2: Column type verification"
    log_info "--------------------------------------------"

    for check in "${TYPE_CHECKS[@]}"; do
      IFS=: read -r table col expected <<< "$check"
      total_checks=$((total_checks + 1))
      local sql="SELECT typeof(${col}) AS t FROM ${ATHENA_DATABASE}.${table} LIMIT 1"
      log_info "Checking type: $table.$col (expect $expected)"

      local actual
      if actual=$(athena_query_scalar "$sql" "typeof($table.$col)") && [[ "$actual" == "$expected" ]]; then
        log_info "PASS: $table.$col is $actual"
        passed=$((passed + 1))
      else
        log_error "FAIL: $table.$col is '${actual:-unknown}', expected '$expected'"
        failed=$((failed + 1))
      fi
    done
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
