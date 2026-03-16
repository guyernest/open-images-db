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
      --instance-type c5n.large \
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
