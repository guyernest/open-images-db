#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# verify-views.sh -- Smoke test for Athena views in open_images database
#
# Verifies that all 4 convenience views exist, return rows, and that computed
# columns produce non-null values. Optionally compares row counts to base
# tables and warns if the JOIN dropped rows.
#
# Usage:
#   bash scripts/verify-views.sh [OPTIONS]
#
# Options:
#   --quick         Only check view existence (skip column and count checks)
#   --help          Show this help message
#
# Requirements: VIEW-01, VIEW-02, VIEW-03, VIEW-04, MASK-01
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared functions
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/athena.sh"

# Expected views
readonly EXPECTED_VIEWS=(
  labeled_images
  labeled_boxes
  labeled_masks
  labeled_relationships
)

# Computed column checks: view:column pairs to verify are non-null
readonly COLUMN_CHECKS=(
  "labeled_boxes:box_area"
  "labeled_boxes:aspect_ratio"
  "labeled_masks:box_area"
  "labeled_masks:click_count"
  "labeled_relationships:display_name_1"
  "labeled_relationships:display_name_2"
)

# Row count comparisons: view:base_table pairs
readonly COUNT_CHECKS=(
  "labeled_images:labels"
  "labeled_boxes:bounding_boxes"
  "labeled_masks:masks"
  "labeled_relationships:relationships"
)

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

QUICK_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      QUICK_MODE=true
      shift
      ;;
    --help)
      head -19 "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
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
  log_info "Athena View Verification"
  log_info "============================================"

  # Check prerequisites
  check_prerequisites

  local total_checks=0
  local passed=0
  local failed=0
  local warnings=0

  # Phase 1: View existence checks
  log_info "--------------------------------------------"
  log_info "Phase 1: View existence verification"
  log_info "--------------------------------------------"

  for view in "${EXPECTED_VIEWS[@]}"; do
    total_checks=$((total_checks + 1))
    local sql="SELECT 1 FROM ${ATHENA_DATABASE}.${view} LIMIT 1"
    log_info "Checking: $view"

    local result
    if result=$(athena_query_scalar "$sql" "exists($view)") && [[ -n "$result" ]]; then
      log_info "PASS: $view exists and has rows"
      passed=$((passed + 1))
    else
      log_error "FAIL: $view has no rows or does not exist"
      failed=$((failed + 1))
    fi
  done

  # Phase 2: Computed column checks (skip in --quick mode)
  if [[ "$QUICK_MODE" == false ]]; then
    log_info "--------------------------------------------"
    log_info "Phase 2: Computed column verification"
    log_info "--------------------------------------------"

    for check in "${COLUMN_CHECKS[@]}"; do
      IFS=: read -r view col <<< "$check"
      total_checks=$((total_checks + 1))
      local sql="SELECT ${col} FROM ${ATHENA_DATABASE}.${view} WHERE ${col} IS NOT NULL LIMIT 1"
      log_info "Checking: $view.$col is non-null"

      local result
      if result=$(athena_query_scalar "$sql" "notnull($view.$col)") && [[ -n "$result" ]]; then
        log_info "PASS: $view.$col has non-null values (sample: $result)"
        passed=$((passed + 1))
      else
        log_error "FAIL: $view.$col is always null or query failed"
        failed=$((failed + 1))
      fi
    done

    # Phase 3: Row count comparisons (warn only, not fail)
    log_info "--------------------------------------------"
    log_info "Phase 3: Row count comparison (warnings only)"
    log_info "--------------------------------------------"

    for check in "${COUNT_CHECKS[@]}"; do
      IFS=: read -r view base_table <<< "$check"
      total_checks=$((total_checks + 1))

      local view_count base_count
      view_count=$(athena_query_scalar \
        "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.${view}" \
        "count($view)" 2>/dev/null) || view_count="error"
      base_count=$(athena_query_scalar \
        "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.${base_table}" \
        "count($base_table)" 2>/dev/null) || base_count="error"

      if [[ "$view_count" == "error" || "$base_count" == "error" ]]; then
        log_error "FAIL: Could not count rows for $view vs $base_table"
        failed=$((failed + 1))
      elif [[ "$view_count" -lt "$base_count" ]]; then
        log_warn "WARN: $view has $view_count rows but $base_table has $base_count rows (JOIN may have dropped rows)"
        warnings=$((warnings + 1))
        passed=$((passed + 1))  # Warnings still pass
      else
        log_info "PASS: $view has $view_count rows (base: $base_count)"
        passed=$((passed + 1))
      fi
    done
  else
    log_info "Skipping column and count checks (--quick mode)"
  fi

  # Report results
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "View Verification Complete"
  log_info "============================================"
  log_info "Total checks: $total_checks"
  log_info "Passed:       $passed"
  if [[ $warnings -gt 0 ]]; then
    log_warn "Warnings:     $warnings"
  fi
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
