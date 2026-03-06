#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-data.sh -- Data quality validation for Open Images Iceberg tables
#
# Compares row counts between Iceberg tables and their raw external table
# counterparts, then performs spot-check validations on sampled rows to verify
# column value ranges and non-null constraints.
#
# Usage:
#   bash scripts/validate-data.sh [OPTIONS]
#
# Options:
#   --quick         Only run row count validation (skip spot-checks)
#   --help          Show this help message
#
# Requirements: VAL-01, VAL-02
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared functions
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/athena.sh"

# Table-to-raw mappings (parallel arrays)
readonly ICEBERG_TABLES=(
  images
  class_descriptions
  labels
  bounding_boxes
  masks
  relationships
  label_hierarchy
)

# Sentinel for labels (sum of two raw tables instead of single raw table)
readonly LABELS_SPECIAL="__labels_special__"

# Raw table counterparts (labels uses sentinel: sum of two raw tables)
readonly RAW_TABLES=(
  raw_images
  raw_class_descriptions
  "$LABELS_SPECIAL"
  raw_bounding_boxes
  raw_masks
  raw_relationships
  raw_label_hierarchy
)

# Tolerance threshold for row count comparison (1%)
readonly TOLERANCE_PERCENT=1

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

# Run a spot-check: count rows violating a condition (0 = all valid)
# Args: $1 = table name, $2 = WHERE clause for invalid rows, $3 = description
# Prints: PASS/FAIL log line
# Returns: 0 on pass, 1 on fail
run_spot_check() {
  local table="$1" invalid_where="$2" description="$3"

  local violation_count
  violation_count=$(athena_query_scalar \
    "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.${table} WHERE ${invalid_where}" \
    "spotcheck($table)") || { echo "ERROR"; return 1; }

  if [[ "$violation_count" -eq 0 ]]; then
    log_info "PASS: $description (all rows valid)"
    return 0
  else
    log_error "FAIL: $description ($violation_count violation(s))"
    return 1
  fi
}

main() {
  local start_time
  start_time=$(date +%s)

  log_info "============================================"
  log_info "Open Images Data Validation"
  log_info "============================================"

  # Check prerequisites
  check_prerequisites

  local total_checks=0
  local passed=0
  local failed=0
  local warnings=0

  # -------------------------------------------------------------------------
  # Phase 1: Row count validation (VAL-01)
  # -------------------------------------------------------------------------
  log_info "--------------------------------------------"
  log_info "Phase 1: Row count validation"
  log_info "--------------------------------------------"

  for i in "${!ICEBERG_TABLES[@]}"; do
    local table="${ICEBERG_TABLES[$i]}"
    local raw="${RAW_TABLES[$i]}"
    total_checks=$((total_checks + 1))

    log_info "Checking row counts: $table"

    # Get Iceberg table count
    local iceberg_count
    iceberg_count=$(athena_query_scalar \
      "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.${table}" \
      "count($table)") || {
      log_error "FAIL: Could not count $table"
      failed=$((failed + 1))
      continue
    }

    # Get raw table count (labels is special: sum of human + machine)
    local raw_count
    if [[ "$raw" == "$LABELS_SPECIAL" ]]; then
      raw_count=$(athena_query_scalar \
        "SELECT (SELECT COUNT(*) FROM ${ATHENA_DATABASE}.raw_labels_human) + (SELECT COUNT(*) FROM ${ATHENA_DATABASE}.raw_labels_machine)" \
        "count(raw_labels_human+raw_labels_machine)") || {
        log_error "FAIL: Could not count raw labels tables"
        failed=$((failed + 1))
        continue
      }
    else
      raw_count=$(athena_query_scalar \
        "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.${raw}" \
        "count($raw)") || {
        log_error "FAIL: Could not count $raw"
        failed=$((failed + 1))
        continue
      }
    fi

    # Compare counts with tolerance
    local abs_diff
    if [[ "$iceberg_count" -ge "$raw_count" ]]; then
      abs_diff=$((iceberg_count - raw_count))
    else
      abs_diff=$((raw_count - iceberg_count))
    fi

    local threshold=0
    if [[ "$raw_count" -gt 0 ]]; then
      threshold=$((raw_count * TOLERANCE_PERCENT / 100))
    fi

    if [[ "$abs_diff" -eq 0 ]]; then
      log_info "PASS: $table = $iceberg_count rows (exact match with raw)"
      passed=$((passed + 1))
    elif [[ "$abs_diff" -le "$threshold" ]]; then
      log_warn "WARN: $table = $iceberg_count rows, raw = $raw_count rows (diff: $abs_diff, within ${TOLERANCE_PERCENT}% tolerance)"
      warnings=$((warnings + 1))
      passed=$((passed + 1))
    else
      log_error "FAIL: $table = $iceberg_count rows, raw = $raw_count rows (diff: $abs_diff, exceeds ${TOLERANCE_PERCENT}% tolerance of $threshold)"
      failed=$((failed + 1))
    fi
  done

  # -------------------------------------------------------------------------
  # Phase 2: Spot-check validation (VAL-02) -- skip in --quick mode
  # -------------------------------------------------------------------------
  if [[ "$QUICK_MODE" == false ]]; then
    log_info "--------------------------------------------"
    log_info "Phase 2: Spot-check validation"
    log_info "--------------------------------------------"

    # --- Bounding boxes spot-check ---
    total_checks=$((total_checks + 1))
    log_info "Spot-check: bounding_boxes coordinates and booleans"
    if run_spot_check "bounding_boxes" \
      "NOT (x_min BETWEEN 0.0 AND 1.0 AND x_max BETWEEN 0.0 AND 1.0 AND y_min BETWEEN 0.0 AND 1.0 AND y_max BETWEEN 0.0 AND 1.0 AND is_occluded IS NOT NULL AND is_truncated IS NOT NULL AND is_group_of IS NOT NULL AND is_depiction IS NOT NULL AND is_inside IS NOT NULL)" \
      "bounding_boxes coordinates (0.0-1.0) and non-null booleans"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi

    # --- Labels spot-check ---
    total_checks=$((total_checks + 1))
    log_info "Spot-check: labels confidence and source"
    if run_spot_check "labels" \
      "NOT (confidence BETWEEN 0.0 AND 1.0 AND source IS NOT NULL AND source <> '')" \
      "labels confidence (0.0-1.0) and non-empty source"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi

    # --- Masks spot-check ---
    total_checks=$((total_checks + 1))
    log_info "Spot-check: masks predicted_iou and mask_path"
    if run_spot_check "masks" \
      "NOT (predicted_iou BETWEEN 0.0 AND 1.0 AND mask_path IS NOT NULL AND mask_path <> '')" \
      "masks predicted_iou (0.0-1.0) and non-empty mask_path"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  else
    log_info "Skipping spot-check validation (--quick mode)"
  fi

  # -------------------------------------------------------------------------
  # Summary
  # -------------------------------------------------------------------------
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "Data Validation Complete"
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
