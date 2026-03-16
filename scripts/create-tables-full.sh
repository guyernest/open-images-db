#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# create-tables-full.sh -- Iceberg Table Creation for open_images_full database
#
# Thin wrapper around create-tables.sh that:
#   1. Sets ATHENA_DATABASE=open_images_full
#   2. Patches SQL warehouse/ -> warehouse-full/ in a temp directory
#   3. Delegates all execution to create-tables.sh's main logic
#
# Usage:
#   bash scripts/create-tables-full.sh [OPTIONS]
#
# Options: same as create-tables.sh (--bucket, --skip-reorg, --skip-hierarchy, --dry-run, --help)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Override database and reorganization script before delegation
export ATHENA_DATABASE="open_images_full"
export REORG_SCRIPT="$SCRIPT_DIR/lib/reorganize-raw-full.sh"

# Patch SQL files: copy to temp dir with warehouse/ -> warehouse-full/ substitution
# Uses LOCATION-anchored sed to avoid false positives in comments
original_sql_dir="$SCRIPT_DIR/../queries/tables"
temp_sql_dir=$(mktemp -d /tmp/open-images-tables-full-XXXXXX)
trap 'rm -rf "${temp_sql_dir:-}"' EXIT

for sql_file in "$original_sql_dir"/*.sql; do
  [[ -f "$sql_file" ]] || continue
  sed "s|/warehouse/|/warehouse-full/|g" "$sql_file" > "$temp_sql_dir/$(basename "$sql_file")"
done

# Override the SQL directory for create-tables.sh by symlinking queries/tables -> temp dir
# We accomplish this by setting SQL_DIR_OVERRIDE (checked by create-tables.sh)
export SQL_DIR_OVERRIDE="$temp_sql_dir"

# Delegate to create-tables.sh with all arguments passed through
exec bash "$SCRIPT_DIR/create-tables.sh" "$@"
