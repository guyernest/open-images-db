#!/usr/bin/env bash
# =============================================================================
# athena.sh -- Shared Athena configuration and query execution
# =============================================================================

# Source common.sh if not already loaded
if ! declare -f log_info >/dev/null 2>&1; then
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Athena configuration (single source of truth)
readonly ATHENA_WORKGROUP="open-images"
readonly ATHENA_DATABASE="open_images"
readonly ATHENA_CATALOG="AwsDataCatalog"

# -----------------------------------------------------------------------------
# Submit an Athena query and wait for completion
# Args: $1 = SQL statement, $2 = description
# Sets: ATHENA_LAST_QUERY_ID
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------

ATHENA_LAST_QUERY_ID=""

athena_execute_and_wait() {
  local sql="$1"
  local description="$2"

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

  ATHENA_LAST_QUERY_ID="$query_id"
  log_info "Started: $description (ID: $query_id)"

  # Poll until complete
  local status="RUNNING"
  local poll_json
  while [[ "$status" == "RUNNING" || "$status" == "QUEUED" ]]; do
    sleep 2
    poll_json=$(aws athena get-query-execution \
      --query-execution-id "$query_id" \
      --profile "$AWS_PROFILE" \
      --output json) || {
      log_error "Failed to check query status: $query_id"
      return 1
    }
    status=$(echo "$poll_json" | jq -r '.QueryExecution.Status.State')
  done

  if [[ "$status" == "SUCCEEDED" ]]; then
    log_info "Succeeded: $description"
    return 0
  else
    local reason
    reason=$(echo "$poll_json" | jq -r '.QueryExecution.Status.StateChangeReason // "Unknown reason"')
    log_error "Failed ($status): $description -- $reason"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Execute a single SQL statement with dry-run support
# Requires caller to set DRY_RUN=true/false before calling
# Args: $1 = SQL statement, $2 = description
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------

run_athena_query() {
  local sql="$1"
  local description="$2"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[DRY RUN] Would execute: $description"
    log_info "  SQL: ${sql:0:120}..."
    return 0
  fi

  athena_execute_and_wait "$sql" "$description"
}

# -----------------------------------------------------------------------------
# Execute an Athena query and return the first result value
# Args: $1 = SQL statement, $2 = description
# Prints: first column of first data row
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------

athena_query_scalar() {
  local sql="$1"
  local description="$2"

  athena_execute_and_wait "$sql" "$description" || return 1

  local result
  result=$(aws athena get-query-results \
    --query-execution-id "$ATHENA_LAST_QUERY_ID" \
    --profile "$AWS_PROFILE" \
    --output text \
    --query 'ResultSet.Rows[1].Data[0].VarCharValue') || {
    log_error "Failed to get query results: $description"
    return 1
  }

  echo "$result"
}

# -----------------------------------------------------------------------------
# Process a SQL file: substitute placeholders, split on semicolons, execute each
# LIMITATION: SQL statements must not contain semicolons in string literals or
# inline comments -- the naive semicolon splitter will break them.
# Args: $1 = SQL file path, $2 = bucket name (optional, empty string to skip)
# Returns: 0 if all statements succeed, 1 if any fail
# -----------------------------------------------------------------------------

process_sql_file() {
  local sql_file="$1"
  local bucket="${2:-}"
  local filename
  filename=$(basename "$sql_file" .sql)
  local file_errors=0
  local stmt_count=0

  log_info "--------------------------------------------"
  log_info "Processing: $filename"
  log_info "--------------------------------------------"

  # Read the file, substitute placeholders, strip comment-only lines
  local sed_args=(-e "s|__DATABASE__|${ATHENA_DATABASE}|g" -e '/^[[:space:]]*--/d')
  if [[ -n "$bucket" ]]; then
    sed_args+=(-e "s|__BUCKET__|${bucket}|g")
  fi
  local sql_content
  sql_content=$(sed "${sed_args[@]}" "$sql_file")

  # Split on semicolons, skip chunks that have no actual SQL
  local IFS=";"
  local statements=()
  for stmt in $sql_content; do
    local stripped
    stripped=$(echo "$stmt" | grep -v '^[[:space:]]*$' | tr -d '[:space:]')
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
