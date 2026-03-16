#!/bin/bash
set -euo pipefail

# =============================================================================
# ec2-userdata-full-load.sh -- EC2 bootstrap for Open Images full dataset load
#
# Runs as root on Amazon Linux 2023. Downloads pipeline scripts from S3,
# downloads all annotation CSVs for 3 splits (train/val/test), and syncs
# all 1.9M images (561 GB) from the public CVDF S3 bucket to our bucket
# via S3-to-S3 sync (no local disk required for image transfer).
# Self-terminates on exit (success or failure) via EXIT trap.
#
# Placeholder: BUCKET is injected by launch-pipeline.sh via sed substitution.
# Do not pass this script directly to EC2 — use launch-pipeline.sh.
# =============================================================================

# Cloud-init captures stdout/stderr to console output automatically.
# Also log to file for SSH debugging if instance is accessed directly.
LOG_FILE="/var/log/open-images-full-load.log"

# Self-terminate on EXIT regardless of success or failure
# Combined with --instance-initiated-shutdown-behavior terminate, this ensures
# the instance is terminated (not just stopped) so there is no lingering cost.
trap 'echo "[INFO]  $(date -u +%H:%M:%S) Pipeline exiting — initiating instance shutdown" | tee -a "$LOG_FILE"; shutdown -h now' EXIT

echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) Open Images full dataset load starting" | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"

# BUCKET is injected by launch-pipeline.sh via sed substitution before this
# script is passed as userdata. The placeholder below is replaced at launch time.
BUCKET="__BUCKET__"

if [[ "$BUCKET" == __*__ ]]; then
  echo "[ERROR] $(date -u +%H:%M:%S) BUCKET placeholder was not replaced by launch-pipeline.sh" | tee -a "$LOG_FILE"
  echo "[ERROR] $(date -u +%H:%M:%S) Run launch-pipeline.sh to launch the instance (do not pass this script directly)" | tee -a "$LOG_FILE"
  exit 1
fi

# Use instance role credentials (no named AWS profile on EC2)
# OPEN_IMAGES_NO_PROFILE=1 tells common.sh to use an empty AWS_PROFILE_FLAG array.
# AWS_PROFILE must be unset (not empty) — AWS CLI treats "" as a named profile lookup.
unset AWS_PROFILE
export OPEN_IMAGES_NO_PROFILE=1

echo "[INFO]  $(date -u +%H:%M:%S) Bucket: $BUCKET" | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) Mode: EC2 instance role (OPEN_IMAGES_NO_PROFILE=1)" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# Step 1: Install dependencies and expand root partition
# Amazon Linux 2023 uses dnf (not yum). curl is pre-installed.
# Growpart + xfs_growfs expand EBS to full volume size (AMI default is 8 GiB).
# -----------------------------------------------------------------------------

echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) Step 1: Installing dependencies..." | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"

dnf install -y jq curl wget 2>&1 | tee -a "$LOG_FILE"

# Expand root partition to use full EBS volume
growpart /dev/xvda 1 2>/dev/null || true
xfs_growfs / 2>/dev/null || true

echo "[INFO]  $(date -u +%H:%M:%S) Disk: $(df -h / | awk 'NR==2{print $2, "total,", $4, "available"}')" | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) Dependencies installed" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# Step 2: Download pipeline scripts from S3
# launch-pipeline.sh uploads scripts to s3://{BUCKET}/pipeline-scripts/
# before launching this instance.
# -----------------------------------------------------------------------------

echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) Step 2: Downloading pipeline scripts from S3..." | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"

mkdir -p /opt/open-images/scripts/lib

aws s3 sync "s3://$BUCKET/pipeline-scripts/" /opt/open-images/scripts/ 2>&1 | tee -a "$LOG_FILE"

chmod +x /opt/open-images/scripts/*.sh 2>/dev/null || true
chmod +x /opt/open-images/scripts/lib/*.sh 2>/dev/null || true

echo "[INFO]  $(date -u +%H:%M:%S) Scripts downloaded to /opt/open-images/scripts/" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# Step 3: Source common.sh and download-annotations-full.sh
# common.sh must be sourced with OPEN_IMAGES_NO_PROFILE=1 already exported.
# The library provides log_info, download_url_set, download_annotations_full.
# -----------------------------------------------------------------------------

echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) Step 3: Loading pipeline libraries..." | tee -a "$LOG_FILE"
echo "[INFO]  $(date -u +%H:%M:%S) ============================================" | tee -a "$LOG_FILE"

source /opt/open-images/scripts/lib/common.sh
source /opt/open-images/scripts/lib/download-annotations-full.sh

log_info "Libraries loaded: common.sh, download-annotations-full.sh"

# -----------------------------------------------------------------------------
# Step 4: Download annotation CSVs for all three splits
# Files are downloaded to local disk then uploaded to S3.
# Annotation CSVs are ~5-10 GB total — 20 GB EBS is sufficient.
# -----------------------------------------------------------------------------

log_info "============================================"
log_info "Step 4: Downloading annotation CSVs (all splits)..."
log_info "============================================"

export OPEN_IMAGES_TEMP="/opt/open-images/tmp"
mkdir -p "$OPEN_IMAGES_TEMP"

download_annotations_full "$OPEN_IMAGES_TEMP" "$BUCKET"

log_info "Annotation download complete"

# NOTE: Image sync SKIPPED — images are served directly from the CVDF public
# bucket (https://open-images-dataset.s3.amazonaws.com/{split}/{id}.jpg).
# The images table generates cvdf_url as a derived column, eliminating the
# need to copy 561 GB / 1.9M files to our S3. Saves ~$10 one-time + $13/month.

# -----------------------------------------------------------------------------
# Step 5: Log completion
# EXIT trap fires after this, calling shutdown -h now
# -----------------------------------------------------------------------------

log_info "============================================"
log_info "Full dataset load pipeline complete"
log_info "Annotations uploaded to s3://$BUCKET/raw/"
log_info "Images served from CVDF public bucket (no copy needed)"
log_info "Next steps (run locally):"
log_info "  just create-tables-full"
log_info "  just create-views-full"
log_info "============================================"
log_info "Instance will self-terminate now"

# EXIT trap fires here, calling: shutdown -h now
