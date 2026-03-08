#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# run-audit.sh -- Relationship & Hierarchy Audit Runner
#
# Executes SQL files from queries/audit/ against Athena. Each SQL file may
# contain multiple statements separated by semicolons; each statement is
# executed individually via start-query-execution.
#
# Substitutes __DATABASE__ placeholder before execution.
#
# Usage:
#   bash scripts/run-audit.sh [OPTIONS]
#
# Options:
#   --dry-run         Show SQL statements without executing
#   --help            Show this help message
#
# Requirements: AUDIT-01, AUDIT-02, AUDIT-03
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
# Process a single SQL file: split on semicolons, execute each statement
# Args: $1 = SQL file path
# Returns: 0 if all statements succeed, 1 if any fail
# -----------------------------------------------------------------------------

process_audit_file() {
  local sql_file="$1"
  local filename
  filename=$(basename "$sql_file" .sql)
  local file_errors=0
  local stmt_count=0

  log_info "--------------------------------------------"
  log_info "Processing: $filename"
  log_info "--------------------------------------------"

  # Read the file, substitute __DATABASE__ placeholder, strip comment-only lines
  local sql_content
  sql_content=$(sed -e "s|__DATABASE__|${ATHENA_DATABASE}|g" -e '/^[[:space:]]*--/d' "$sql_file")

  # Split on semicolons, skip chunks that have no actual SQL
  local IFS=";"
  local statements=()
  for stmt in $sql_content; do
    local stripped
    stripped=$(echo "$stmt" | grep -v '^[[:space:]]*--' | grep -v '^[[:space:]]*$' | tr -d '[:space:]')
    if [[ -n "$stripped" ]]; then
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
  log_info "Relationship & Hierarchy Audit"
  log_info "============================================"

  # Check prerequisites
  check_prerequisites

  # Find SQL files in queries/audit/
  local sql_dir="$SCRIPT_DIR/../queries/audit"
  if [[ ! -d "$sql_dir" ]]; then
    log_error "SQL directory not found: $sql_dir"
    log_error "Create queries/audit/ with SQL files first"
    exit 1
  fi

  local sql_files=()
  while IFS= read -r -d '' file; do
    sql_files+=("$file")
  done < <(find "$sql_dir" -name '*.sql' -type f -print0 | sort -z)

  if [[ ${#sql_files[@]} -eq 0 ]]; then
    log_warn "No SQL files found in $sql_dir"
    log_warn "Create SQL files (e.g., 01-relationship-types.sql) and re-run"
    exit 0
  fi

  log_info "============================================"
  log_info "Executing ${#sql_files[@]} audit SQL file(s)"
  log_info "============================================"

  local total_files=${#sql_files[@]}
  local failed_files=0
  local file_count=0

  for sql_file in "${sql_files[@]}"; do
    file_count=$((file_count + 1))
    log_info "File $file_count/$total_files: $(basename "$sql_file")"

    if ! process_audit_file "$sql_file"; then
      failed_files=$((failed_files + 1))
      # Continue processing remaining files (don't fail fast)
    fi
  done

  # Report summary
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "Audit Complete"
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
