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
