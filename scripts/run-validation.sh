#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# run-validation.sh -- End-to-End Validation Runner
#
# Executes all example queries (01-08) against live Athena and performs
# validation checks across 4 categories plus round-trip traces. Produces
# a pass/fail summary table.
#
# Categories:
#   1. Non-empty results     -- each example query returns >= 1 row
#   2. Human-readable names  -- display_name columns contain names, not MIDs
#   3. Row count sanity      -- live counts within 10% of audit report values
#   4. Cross-view consistency -- hierarchy children match relationship entries
#
# Round-trip traces:
#   - Man on Horse (3-layer: raw -> view -> hierarchy view)
#   - Animal subtree (class_hierarchy root_path)
#   - Woman wears Hat (3-layer: raw -> view -> hierarchy view)
#
# Usage:
#   bash scripts/run-validation.sh [OPTIONS]
#
# Options:
#   --dry-run         Show checks without executing against Athena
#   --help            Show this help message
#
# Requirements: AUDIT-04
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared functions
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/athena.sh"

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
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
# Tracking arrays
# -----------------------------------------------------------------------------

declare -a CAT1_NAMES=() CAT1_RESULTS=()
declare -a CAT2_NAMES=() CAT2_RESULTS=()
declare -a CAT3_NAMES=() CAT3_RESULTS=()
declare -a CAT4_NAMES=() CAT4_RESULTS=()
declare -a CAT5_NAMES=() CAT5_RESULTS=()

# Helper: record a check result
# Args: $1 = category (1-5), $2 = check name, $3 = PASS or FAIL
record_check() {
  local cat="$1" name="$2" result="$3"
  eval "CAT${cat}_NAMES+=(\"$name\")"
  eval "CAT${cat}_RESULTS+=(\"$result\")"
  if [[ "$result" == "PASS" ]]; then
    log_info "  [PASS] $name"
  else
    log_error "  [FAIL] $name"
  fi
}

# Helper: get row count from last Athena query result
# Returns the number of data rows (excludes header)
get_result_row_count() {
  local result_json
  result_json=$(aws athena get-query-results \
    --query-execution-id "$ATHENA_LAST_QUERY_ID" \
    "${AWS_PROFILE_FLAG[@]}" \
    --output json) || { echo "0"; return 1; }
  # ResultSet.Rows includes header row at index 0
  local total_rows
  total_rows=$(echo "$result_json" | jq '.ResultSet.Rows | length')
  echo $((total_rows - 1))
}

# Helper: get scalar value from last Athena query result (first col, first data row)
get_result_scalar() {
  aws athena get-query-results \
    --query-execution-id "$ATHENA_LAST_QUERY_ID" \
    "${AWS_PROFILE_FLAG[@]}" \
    --output text \
    --query 'ResultSet.Rows[1].Data[0].VarCharValue' 2>/dev/null || echo ""
}

# Helper: get all values from first column (skipping header)
get_result_column() {
  aws athena get-query-results \
    --query-execution-id "$ATHENA_LAST_QUERY_ID" \
    "${AWS_PROFILE_FLAG[@]}" \
    --output json 2>/dev/null | jq -r '.ResultSet.Rows[1:][].Data[0].VarCharValue' || echo ""
}

# Helper: check if value is within tolerance of expected
# Args: $1 = actual, $2 = expected, $3 = tolerance (0.10 = 10%)
within_tolerance() {
  local actual="$1" expected="$2" tolerance="$3"
  local lower upper
  lower=$(echo "$expected * (1 - $tolerance)" | bc -l | cut -d. -f1)
  upper=$(echo "$expected * (1 + $tolerance)" | bc -l | cut -d. -f1)
  [[ "$actual" -ge "$lower" && "$actual" -le "$upper" ]]
}

# -----------------------------------------------------------------------------
# Category 1: Non-empty results (example queries 01-08)
# -----------------------------------------------------------------------------

run_category_1() {
  log_info "============================================"
  log_info "Category 1: Non-Empty Results"
  log_info "============================================"

  local sql_dir="$SCRIPT_DIR/../queries/examples"
  local sql_files=()

  while IFS= read -r -d '' file; do
    local basename
    basename=$(basename "$file")
    # Skip 00-mcp-reference.sql (documentation only)
    if [[ "$basename" == 00-* ]]; then
      continue
    fi
    sql_files+=("$file")
  done < <(find "$sql_dir" -name '*.sql' -type f -print0 | sort -z)

  for sql_file in "${sql_files[@]}"; do
    local name
    name=$(basename "$sql_file" .sql)

    if [[ "$DRY_RUN" == true ]]; then
      log_info "  [DRY RUN] Would execute: $name"
      record_check 1 "$name" "PASS"
      continue
    fi

    if process_sql_file "$sql_file"; then
      local row_count
      row_count=$(get_result_row_count)
      if [[ "$row_count" -ge 1 ]]; then
        record_check 1 "$name ($row_count rows)" "PASS"
      else
        record_check 1 "$name (0 rows)" "FAIL"
      fi
    else
      record_check 1 "$name (execution failed)" "FAIL"
    fi
  done
}

# -----------------------------------------------------------------------------
# Category 2: Human-readable names
# -----------------------------------------------------------------------------

run_category_2() {
  log_info "============================================"
  log_info "Category 2: Human-Readable Names"
  log_info "============================================"

  local checks=(
    "labeled_relationships.display_name_1|SELECT display_name_1 FROM ${ATHENA_DATABASE}.labeled_relationships LIMIT 1"
    "class_hierarchy.display_name|SELECT display_name FROM ${ATHENA_DATABASE}.class_hierarchy WHERE depth = 1 LIMIT 1"
    "hierarchy_relationships.ancestor_name_1|SELECT ancestor_name_1 FROM ${ATHENA_DATABASE}.hierarchy_relationships LIMIT 1"
  )

  for check_spec in "${checks[@]}"; do
    local check_name="${check_spec%%|*}"
    local sql="${check_spec#*|}"

    if [[ "$DRY_RUN" == true ]]; then
      log_info "  [DRY RUN] Would check: $check_name is not a raw MID"
      record_check 2 "$check_name" "PASS"
      continue
    fi

    if athena_execute_and_wait "$sql" "Check $check_name"; then
      local value
      value=$(get_result_scalar)
      if [[ -n "$value" && ! "$value" =~ ^/m/ ]]; then
        record_check 2 "$check_name = '$value'" "PASS"
      else
        record_check 2 "$check_name = '$value' (raw MID)" "FAIL"
      fi
    else
      record_check 2 "$check_name (query failed)" "FAIL"
    fi
  done
}

# -----------------------------------------------------------------------------
# Category 3: Row count sanity (within 10% of audit values)
# -----------------------------------------------------------------------------

run_category_3() {
  log_info "============================================"
  log_info "Category 3: Row Count Sanity"
  log_info "============================================"

  local checks=(
    "Distinct relationship types|SELECT COUNT(DISTINCT relationship_label) FROM ${ATHENA_DATABASE}.relationships|27"
    "Total relationship rows|SELECT COUNT(*) FROM ${ATHENA_DATABASE}.relationships|27243"
    "Hierarchy MIDs|SELECT COUNT(DISTINCT mid) FROM ${ATHENA_DATABASE}.class_hierarchy|602"
    "View relationship rows|SELECT COUNT(*) FROM ${ATHENA_DATABASE}.labeled_relationships|26357"
  )

  for check_spec in "${checks[@]}"; do
    local check_name="${check_spec%%|*}"
    local rest="${check_spec#*|}"
    local sql="${rest%%|*}"
    local expected="${rest##*|}"

    if [[ "$DRY_RUN" == true ]]; then
      log_info "  [DRY RUN] Would check: $check_name ~ $expected"
      record_check 3 "$check_name" "PASS"
      continue
    fi

    if athena_execute_and_wait "$sql" "Count $check_name"; then
      local actual
      actual=$(get_result_scalar)
      if within_tolerance "$actual" "$expected" "0.10"; then
        record_check 3 "$check_name: $actual (expected ~$expected)" "PASS"
      else
        record_check 3 "$check_name: $actual (expected ~$expected, outside 10%)" "FAIL"
      fi
    else
      record_check 3 "$check_name (query failed)" "FAIL"
    fi
  done
}

# -----------------------------------------------------------------------------
# Category 4: Cross-view consistency
# -----------------------------------------------------------------------------

run_category_4() {
  log_info "============================================"
  log_info "Category 4: Cross-View Consistency"
  log_info "============================================"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "  [DRY RUN] Would check: Person children from class_hierarchy"
    log_info "  [DRY RUN] Would check: hierarchy_relationships subset of Person descendants"
    record_check 4 "Person children in class_hierarchy" "PASS"
    record_check 4 "hierarchy_relationships subset" "PASS"
    return
  fi

  # Check 1: Person children from class_hierarchy
  local sql="SELECT display_name FROM ${ATHENA_DATABASE}.class_hierarchy WHERE parent_name = 'Person' AND depth = 2 ORDER BY display_name"
  if athena_execute_and_wait "$sql" "Person children from class_hierarchy"; then
    local children
    children=$(get_result_column)
    local has_man has_woman has_boy has_girl
    has_man=$(echo "$children" | grep -c "^Man$" || true)
    has_woman=$(echo "$children" | grep -c "^Woman$" || true)
    has_boy=$(echo "$children" | grep -c "^Boy$" || true)
    has_girl=$(echo "$children" | grep -c "^Girl$" || true)

    if [[ "$has_man" -ge 1 && "$has_woman" -ge 1 && "$has_boy" -ge 1 && "$has_girl" -ge 1 ]]; then
      record_check 4 "Person children: Man, Woman, Boy, Girl all found" "PASS"
    else
      record_check 4 "Person children: missing expected entries (Man=$has_man Woman=$has_woman Boy=$has_boy Girl=$has_girl)" "FAIL"
    fi
  else
    record_check 4 "Person children query failed" "FAIL"
  fi

  # Check 2: hierarchy_relationships for ancestor Person should include descendants
  local sql2="SELECT DISTINCT display_name_1 FROM ${ATHENA_DATABASE}.hierarchy_relationships WHERE ancestor_name_1 = 'Person' LIMIT 10"
  if athena_execute_and_wait "$sql2" "hierarchy_relationships Person ancestor check"; then
    local hr_names
    hr_names=$(get_result_column)
    local hr_has_man hr_has_woman
    hr_has_man=$(echo "$hr_names" | grep -c "^Man$" || true)
    hr_has_woman=$(echo "$hr_names" | grep -c "^Woman$" || true)

    if [[ "$hr_has_man" -ge 1 || "$hr_has_woman" -ge 1 ]]; then
      record_check 4 "hierarchy_relationships includes Person descendants" "PASS"
    else
      record_check 4 "hierarchy_relationships missing Person descendants" "FAIL"
    fi
  else
    record_check 4 "hierarchy_relationships subset query failed" "FAIL"
  fi
}

# -----------------------------------------------------------------------------
# Category 5: Round-trip traces
# -----------------------------------------------------------------------------

run_category_5() {
  log_info "============================================"
  log_info "Category 5: Round-Trip Traces"
  log_info "============================================"

  # --- Trace 1: Man on Horse ---
  log_info "  Trace 1: Man on Horse"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "  [DRY RUN] Would trace: Man on Horse across 3 layers"
    record_check 5 "Trace 1: Man on Horse" "PASS"
  else
    local t1_l1 t1_l2 t1_l3

    # Layer 1: Raw table (MID-based)
    local sql1="SELECT COUNT(*) FROM ${ATHENA_DATABASE}.relationships WHERE label_name_1 = '/m/04yx4' AND label_name_2 = '/m/03k3r' AND relationship_label = 'on'"
    if athena_execute_and_wait "$sql1" "Trace 1 Layer 1: raw relationships"; then
      t1_l1=$(get_result_scalar)
    else
      t1_l1="-1"
    fi

    # Layer 2: labeled_relationships (name-based)
    local sql2="SELECT COUNT(*) FROM ${ATHENA_DATABASE}.labeled_relationships WHERE display_name_1 = 'Man' AND display_name_2 = 'Horse' AND relationship_label = 'on'"
    if athena_execute_and_wait "$sql2" "Trace 1 Layer 2: labeled_relationships"; then
      t1_l2=$(get_result_scalar)
    else
      t1_l2="-1"
    fi

    # Layer 3: hierarchy_relationships (depth=0)
    local sql3="SELECT COUNT(*) FROM ${ATHENA_DATABASE}.hierarchy_relationships WHERE display_name_1 = 'Man' AND display_name_2 = 'Horse' AND relationship_label = 'on' AND depth_1 = 0 AND depth_2 = 0"
    if athena_execute_and_wait "$sql3" "Trace 1 Layer 3: hierarchy_relationships"; then
      t1_l3=$(get_result_scalar)
    else
      t1_l3="-1"
    fi

    log_info "  Trace 1 counts: L1=$t1_l1 L2=$t1_l2 L3=$t1_l3"
    if [[ "$t1_l1" == "$t1_l2" && "$t1_l2" == "$t1_l3" && "$t1_l1" != "-1" ]]; then
      record_check 5 "Trace 1: Man on Horse (L1=$t1_l1 L2=$t1_l2 L3=$t1_l3)" "PASS"
    else
      record_check 5 "Trace 1: Man on Horse counts differ (L1=$t1_l1 L2=$t1_l2 L3=$t1_l3)" "FAIL"
    fi
  fi

  # --- Trace 2: Animal subtree ---
  log_info "  Trace 2: Animal subtree"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "  [DRY RUN] Would trace: Animal subtree for Dog, Cat, Horse"
    record_check 5 "Trace 2: Animal subtree" "PASS"
  else
    local sql_animal="SELECT display_name FROM ${ATHENA_DATABASE}.class_hierarchy WHERE root_path LIKE 'Entity > Animal%' ORDER BY display_name"
    if athena_execute_and_wait "$sql_animal" "Trace 2: Animal subtree"; then
      local animal_names
      animal_names=$(get_result_column)
      local has_dog has_cat has_horse
      has_dog=$(echo "$animal_names" | grep -c "^Dog$" || true)
      has_cat=$(echo "$animal_names" | grep -c "^Cat$" || true)
      has_horse=$(echo "$animal_names" | grep -c "^Horse$" || true)

      if [[ "$has_dog" -ge 1 && "$has_cat" -ge 1 && "$has_horse" -ge 1 ]]; then
        record_check 5 "Trace 2: Animal subtree contains Dog, Cat, Horse" "PASS"
      else
        record_check 5 "Trace 2: Animal subtree missing entries (Dog=$has_dog Cat=$has_cat Horse=$has_horse)" "FAIL"
      fi
    else
      record_check 5 "Trace 2: Animal subtree query failed" "FAIL"
    fi
  fi

  # --- Trace 3: Woman wears Hat ---
  log_info "  Trace 3: Woman wears Hat"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "  [DRY RUN] Would trace: Woman wears Hat across 3 layers"
    record_check 5 "Trace 3: Woman wears Hat" "PASS"
  else
    local t3_l1 t3_l2 t3_l3

    # Layer 1: Raw table (MID-based)
    local sql1="SELECT COUNT(*) FROM ${ATHENA_DATABASE}.relationships WHERE label_name_1 = '/m/03bt1vf' AND label_name_2 = '/m/02dl1y' AND relationship_label = 'wears'"
    if athena_execute_and_wait "$sql1" "Trace 3 Layer 1: raw relationships"; then
      t3_l1=$(get_result_scalar)
    else
      t3_l1="-1"
    fi

    # Layer 2: labeled_relationships (name-based)
    local sql2="SELECT COUNT(*) FROM ${ATHENA_DATABASE}.labeled_relationships WHERE display_name_1 = 'Woman' AND display_name_2 = 'Hat' AND relationship_label = 'wears'"
    if athena_execute_and_wait "$sql2" "Trace 3 Layer 2: labeled_relationships"; then
      t3_l2=$(get_result_scalar)
    else
      t3_l2="-1"
    fi

    # Layer 3: hierarchy_relationships (depth=0)
    local sql3="SELECT COUNT(*) FROM ${ATHENA_DATABASE}.hierarchy_relationships WHERE display_name_1 = 'Woman' AND display_name_2 = 'Hat' AND relationship_label = 'wears' AND depth_1 = 0 AND depth_2 = 0"
    if athena_execute_and_wait "$sql3" "Trace 3 Layer 3: hierarchy_relationships"; then
      t3_l3=$(get_result_scalar)
    else
      t3_l3="-1"
    fi

    log_info "  Trace 3 counts: L1=$t3_l1 L2=$t3_l2 L3=$t3_l3"
    if [[ "$t3_l1" == "$t3_l2" && "$t3_l2" == "$t3_l3" && "$t3_l1" != "-1" ]]; then
      record_check 5 "Trace 3: Woman wears Hat (L1=$t3_l1 L2=$t3_l2 L3=$t3_l3)" "PASS"
    else
      record_check 5 "Trace 3: Woman wears Hat counts differ (L1=$t3_l1 L2=$t3_l2 L3=$t3_l3)" "FAIL"
    fi
  fi
}

# -----------------------------------------------------------------------------
# Summary table
# -----------------------------------------------------------------------------

print_summary() {
  local total_pass=0 total_fail=0

  for cat in 1 2 3 4 5; do
    local cat_pass=0 cat_fail=0
    local -n results_ref="CAT${cat}_RESULTS"
    for r in "${results_ref[@]}"; do
      if [[ "$r" == "PASS" ]]; then
        cat_pass=$((cat_pass + 1))
      else
        cat_fail=$((cat_fail + 1))
      fi
    done
    total_pass=$((total_pass + cat_pass))
    total_fail=$((total_fail + cat_fail))

    local cat_total=$((cat_pass + cat_fail))
    local cat_name
    case $cat in
      1) cat_name="Non-empty results    " ;;
      2) cat_name="Human-readable names " ;;
      3) cat_name="Row count sanity     " ;;
      4) cat_name="Cross-view consistency" ;;
      5) cat_name="Round-trip traces    " ;;
    esac

    printf "%-23s | %6d | %6d | %5d\n" "$cat_name" "$cat_pass" "$cat_fail" "$cat_total"
  done

  local grand_total=$((total_pass + total_fail))

  echo "--------------------------------------------"
  printf "%-23s | %6d | %6d | %5d\n" "TOTAL" "$total_pass" "$total_fail" "$grand_total"
  echo ""

  if [[ "$total_fail" -eq 0 ]]; then
    echo "OVERALL: PASS"
    return 0
  else
    echo "OVERALL: FAIL"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

main() {
  local start_time
  start_time=$(date +%s)

  log_info "============================================"
  log_info "End-to-End Validation"
  log_info "============================================"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "DRY RUN mode -- no Athena queries will be executed"
  else
    check_prerequisites
  fi

  run_category_1
  run_category_2
  run_category_3
  run_category_4
  run_category_5

  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  echo ""
  echo "============================================"
  echo "Validation Summary"
  echo "============================================"
  printf "%-23s | %6s | %6s | %5s\n" "Category" "Passed" "Failed" "Total"

  local overall_result
  if print_summary; then
    overall_result=0
  else
    overall_result=1
  fi

  echo ""
  log_info "Elapsed time: ${elapsed}s"

  exit "$overall_result"
}

main "$@"
