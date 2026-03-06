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

# Raw table counterparts (labels is special: sum of two raw tables)
readonly RAW_TABLES=(
  raw_images
  raw_class_descriptions
  __labels_special__
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
    if [[ "$raw" == "__labels_special__" ]]; then
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

    local bbox_result
    bbox_result=$(athena_query_scalar \
      "SELECT CASE
        WHEN x_min BETWEEN 0.0 AND 1.0
         AND x_max BETWEEN 0.0 AND 1.0
         AND y_min BETWEEN 0.0 AND 1.0
         AND y_max BETWEEN 0.0 AND 1.0
         AND is_occluded IS NOT NULL
         AND is_truncated IS NOT NULL
         AND is_group_of IS NOT NULL
         AND is_depiction IS NOT NULL
         AND is_inside IS NOT NULL
        THEN 'VALID'
        ELSE 'INVALID'
       END
       FROM ${ATHENA_DATABASE}.bounding_boxes LIMIT 1" \
      "spotcheck(bounding_boxes)") || bbox_result="ERROR"

    if [[ "$bbox_result" == "VALID" ]]; then
      log_info "PASS: bounding_boxes sample row has valid coordinates (0.0-1.0) and non-null booleans"
      passed=$((passed + 1))
    else
      log_error "FAIL: bounding_boxes sample row has invalid coordinates or null booleans (result: $bbox_result)"
      failed=$((failed + 1))
    fi

    # --- Labels spot-check ---
    total_checks=$((total_checks + 1))
    log_info "Spot-check: labels confidence and source"

    local labels_result
    labels_result=$(athena_query_scalar \
      "SELECT CASE
        WHEN confidence BETWEEN 0.0 AND 1.0
         AND source IS NOT NULL
         AND source <> ''
        THEN 'VALID'
        ELSE 'INVALID'
       END
       FROM ${ATHENA_DATABASE}.labels LIMIT 1" \
      "spotcheck(labels)") || labels_result="ERROR"

    if [[ "$labels_result" == "VALID" ]]; then
      log_info "PASS: labels sample row has valid confidence (0.0-1.0) and non-empty source"
      passed=$((passed + 1))
    else
      log_error "FAIL: labels sample row has invalid confidence or empty source (result: $labels_result)"
      failed=$((failed + 1))
    fi

    # --- Masks spot-check ---
    total_checks=$((total_checks + 1))
    log_info "Spot-check: masks predicted_iou and mask_path"

    local masks_result
    masks_result=$(athena_query_scalar \
      "SELECT CASE
        WHEN predicted_iou BETWEEN 0.0 AND 1.0
         AND mask_path IS NOT NULL
         AND mask_path <> ''
        THEN 'VALID'
        ELSE 'INVALID'
       END
       FROM ${ATHENA_DATABASE}.masks LIMIT 1" \
      "spotcheck(masks)") || masks_result="ERROR"

    if [[ "$masks_result" == "VALID" ]]; then
      log_info "PASS: masks sample row has valid predicted_iou (0.0-1.0) and non-empty mask_path"
      passed=$((passed + 1))
    else
      log_error "FAIL: masks sample row has invalid predicted_iou or empty mask_path (result: $masks_result)"
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
