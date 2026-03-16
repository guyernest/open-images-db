#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# create-views-full.sh -- Athena View Creation for open_images_full database
#
# Wrapper around create-views.sh that sets ATHENA_DATABASE=open_images_full.
# Views use __DATABASE__ placeholder substitution (no LOCATION clauses),
# so no warehouse prefix substitution is needed — only the database override.
#
# Usage:
#   bash scripts/create-views-full.sh [OPTIONS]
#
# Options:
#   --dry-run         Show SQL statements without executing
#   --help            Show this help message
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Override ATHENA_DATABASE before sourcing athena.sh
# athena.sh uses: readonly ATHENA_DATABASE="${ATHENA_DATABASE:-open_images}"
export ATHENA_DATABASE="open_images_full"

# Source shared libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/athena.sh"

# -----------------------------------------------------------------------------
# Argument parsing (mirrors create-views.sh)
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
# Main execution
# -----------------------------------------------------------------------------

main() {
  local start_time
  start_time=$(date +%s)

  log_info "============================================"
  log_info "Athena View Creation (Full Dataset)"
  log_info "Using database: $ATHENA_DATABASE"
  log_info "============================================"

  # Check prerequisites
  check_prerequisites

  # Find SQL files in queries/views/
  local sql_dir="$SCRIPT_DIR/../queries/views"
  if [[ ! -d "$sql_dir" ]]; then
    log_error "SQL directory not found: $sql_dir"
    log_error "Create queries/views/ with SQL files first"
    exit 1
  fi

  local sql_files=()
  while IFS= read -r -d '' file; do
    sql_files+=("$file")
  done < <(find "$sql_dir" -name '*.sql' -type f -print0 | sort -z)

  if [[ ${#sql_files[@]} -eq 0 ]]; then
    log_warn "No SQL files found in $sql_dir"
    log_warn "Create SQL files (e.g., 01-labeled-images.sql) and re-run"
    exit 0
  fi

  log_info "============================================"
  log_info "Executing ${#sql_files[@]} view SQL file(s)"
  log_info "============================================"

  local total_files=${#sql_files[@]}
  local failed_files=0
  local file_count=0

  for sql_file in "${sql_files[@]}"; do
    file_count=$((file_count + 1))
    local filename
    filename=$(basename "$sql_file" .sql)

    log_info "--------------------------------------------"
    log_info "File $file_count/$total_files: $filename"
    log_info "--------------------------------------------"

    # Read the file and substitute __DATABASE__ placeholder
    local sql_content
    sql_content=$(sed "s|__DATABASE__|${ATHENA_DATABASE}|g" "$sql_file")

    # Build description from filename
    local description="Create view: $filename"

    if ! run_athena_query "$sql_content" "$description"; then
      failed_files=$((failed_files + 1))
      log_error "$filename: FAILED"
      # Continue processing remaining files (don't fail fast)
    else
      log_info "$filename: succeeded"
    fi
  done

  # Report summary
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  log_info "============================================"
  log_info "View Creation Complete"
  log_info "============================================"
  log_info "Database:            $ATHENA_DATABASE"
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
