# Open Images V7 Dataset Pipeline
# Usage: assume <profile> && just <recipe> [args]
#
# Requires: aws CLI (with credentials via assume/AWS_PROFILE/env), jq, just

set dotenv-load := false
set shell := ["bash", "-euo", "pipefail", "-c"]

scripts_dir := justfile_directory() / "scripts"
stack := "OpenImagesStack"

# ─── Discovery ────────────────────────────────────────────────────────────────

# Show available recipes
default:
    @just --list

# ─── Infrastructure ───────────────────────────────────────────────────────────

# Deploy CDK stack (includes open_images_full database + EC2 instance profile)
deploy:
    cd {{justfile_directory()}}/infra && npx cdk deploy

# ─── Existing pipeline (validation split only) ────────────────────────────────

# Download annotations and sync validation images (validation split only)
download-all:
    bash {{scripts_dir}}/download-all.sh

# Create Iceberg tables in open_images database (validation split)
create-tables *args="":
    bash {{scripts_dir}}/create-tables.sh {{args}}

# Create views in open_images database (validation split)
create-views *args="":
    bash {{scripts_dir}}/create-views.sh {{args}}

# Dry-run table creation for validation database (no Athena execution)
dry-run-tables:
    bash {{scripts_dir}}/create-tables.sh --dry-run

# ─── Full dataset pipeline (all 3 splits, 1.9M images) ─────────────────────────

# Launch EC2 to download annotation CSVs for all splits (~30 min, images served from CVDF)
launch-full-load:
    bash {{scripts_dir}}/launch-pipeline.sh \
      --userdata {{scripts_dir}}/ec2-userdata-full-load.sh \
      --instance-type t3.medium \
      --ebs-size 20 \
      --tag open-images-full-load

# Create Iceberg tables in open_images_full database (warehouse-full/ prefix)
create-tables-full *args="":
    bash {{scripts_dir}}/create-tables-full.sh {{args}}

# Create views in open_images_full database
create-views-full *args="":
    bash {{scripts_dir}}/create-views-full.sh {{args}}

# Dry-run table creation for full database (no Athena execution)
dry-run-tables-full:
    bash {{scripts_dir}}/create-tables-full.sh --dry-run

# ─── Validation ──────────────────────────────────────────────────────────────

# Verify full dataset table row counts
verify-tables-full:
    #!/usr/bin/env bash
    set -euo pipefail
    export ATHENA_DATABASE="open_images_full"
    source {{scripts_dir}}/lib/common.sh
    source {{scripts_dir}}/lib/athena.sh

    log_info "Verifying open_images_full table row counts..."

    images=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.images" "count images")
    class_desc=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.class_descriptions" "count class_descriptions")
    labels=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.labels" "count labels")
    labels_top5=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.labels_top5" "count labels_top5")
    boxes=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.bounding_boxes" "count bounding_boxes")
    masks=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.masks" "count masks")
    rels=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.relationships" "count relationships")
    hierarchy=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.label_hierarchy" "count label_hierarchy")

    echo ""
    echo "┌─────────────────────┬──────────────┬──────────────┐"
    echo "│ Table               │ Actual       │ Expected     │"
    echo "├─────────────────────┼──────────────┼──────────────┤"
    printf "│ images              │ %12s │     ~1910000 │\n" "$images"
    printf "│ class_descriptions  │ %12s │        ~600  │\n" "$class_desc"
    printf "│ labels              │ %12s │  ~229000000  │\n" "$labels"
    printf "│ labels_top5         │ %12s │   ~45000000  │\n" "$labels_top5"
    printf "│ bounding_boxes      │ %12s │   ~15000000  │\n" "$boxes"
    printf "│ masks               │ %12s │    ~2800000  │\n" "$masks"
    printf "│ relationships       │ %12s │     ~370000  │\n" "$rels"
    printf "│ label_hierarchy     │ %12s │        ~600  │\n" "$hierarchy"
    echo "└─────────────────────┴──────────────┴──────────────┘"

    errors=0
    [[ "$images" -ge 1000000 ]] || { echo "FAIL: images < 1M"; errors=$((errors+1)); }
    [[ "$class_desc" -ge 500 ]] || { echo "FAIL: class_descriptions < 500"; errors=$((errors+1)); }
    [[ "$labels" -ge 100000000 ]] || { echo "FAIL: labels < 100M"; errors=$((errors+1)); }
    [[ "$labels_top5" -ge 10000000 ]] || { echo "FAIL: labels_top5 < 10M"; errors=$((errors+1)); }
    [[ "$boxes" -ge 1000000 ]] || { echo "FAIL: bounding_boxes < 1M"; errors=$((errors+1)); }
    [[ "$hierarchy" -ge 100 ]] || { echo "FAIL: label_hierarchy < 100"; errors=$((errors+1)); }

    # Materialized aggregation tables (Tier 1)
    eic_mat=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.entity_image_counts_mat" "count entity_image_counts_mat" 2>/dev/null) || eic_mat="N/A"
    rs_mat=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.relationship_summary_mat" "count relationship_summary_mat" 2>/dev/null) || rs_mat="N/A"
    cooc=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.label_cooccurrence_top10" "count label_cooccurrence_top10" 2>/dev/null) || cooc="N/A"
    chr_mat=$(athena_query_scalar "SELECT COUNT(*) FROM ${ATHENA_DATABASE}.class_hierarchy_resolved_mat" "count class_hierarchy_resolved_mat" 2>/dev/null) || chr_mat="N/A"

    if [[ "$eic_mat" != "N/A" ]]; then
      echo ""
      echo "Materialized tables (Tier 1):"
      printf "  entity_image_counts_mat:       %s\n" "$eic_mat"
      printf "  relationship_summary_mat:      %s\n" "$rs_mat"
      printf "  label_cooccurrence_top10:      %s\n" "$cooc"
      printf "  class_hierarchy_resolved_mat:  %s\n" "$chr_mat"
    fi

    echo ""
    if [[ $errors -eq 0 ]]; then
      log_info "All table counts within expected range"
    else
      log_error "$errors table(s) have unexpected row counts"
      exit 1
    fi

# Verify a sample cvdf_url resolves (quick HTTP check)
verify-cvdf-url:
    #!/usr/bin/env bash
    set -euo pipefail
    export ATHENA_DATABASE="open_images_full"
    source {{scripts_dir}}/lib/common.sh
    source {{scripts_dir}}/lib/athena.sh

    log_info "Checking a sample cvdf_url..."
    url=$(athena_query_scalar \
      "SELECT cvdf_url FROM ${ATHENA_DATABASE}.images LIMIT 1" \
      "sample cvdf_url")
    echo "URL: $url"

    status=$(curl -sI "$url" | head -1)
    echo "HTTP: $status"

    if echo "$status" | grep -q "200"; then
      log_info "cvdf_url resolves correctly"
    else
      log_error "cvdf_url returned unexpected status"
      exit 1
    fi

# ─── EC2 Monitoring ───────────────────────────────────────────────────────────

# Check EC2 instance state
instance-status instance_id:
    @aws ec2 describe-instances \
      --instance-ids {{instance_id}} \
      --query 'Reservations[0].Instances[0].{State:State.Name,Launch:LaunchTime,Type:InstanceType}' \
      --output table

# View pipeline logs from EC2 console output (may take minutes after termination)
console-output instance_id:
    @aws ec2 get-console-output \
      --instance-id {{instance_id}} \
      --query 'Output' --output text 2>/dev/null \
      | tr '\r' '\n' | grep -E '\[(INFO|WARN|ERROR)\]' \
      || echo "(no script output yet — console may take a few minutes to populate)"

# View full raw EC2 console output
console-output-raw instance_id:
    @aws ec2 get-console-output \
      --instance-id {{instance_id}} \
      --query 'Output' --output text

# List open-images EC2 instances (running and recently terminated)
list-instances:
    @aws ec2 describe-instances \
      --filters "Name=tag:project,Values=open-images" \
      --query 'Reservations[*].Instances[*].{Id:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name,Launch:LaunchTime}' \
      --output table
