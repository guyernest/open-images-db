#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# common.sh -- Shared functions for Open Images data acquisition pipeline
# =============================================================================

# AWS profile used for all AWS CLI calls
readonly AWS_PROFILE="${AWS_PROFILE:-ze-kasher-dev}"

# Default temp directory (configurable via environment variable)
TEMP_DIR="${OPEN_IMAGES_TEMP:-$HOME/open-images-tmp}"

# CloudFormation stack name for bucket discovery
readonly CF_STACK_NAME="OpenImagesStack"

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

log_info() {
  echo "[INFO]  $(date -u +%H:%M:%S) $*" >&2
}

log_warn() {
  echo "[WARN]  $(date -u +%H:%M:%S) $*" >&2
}

log_error() {
  echo "[ERROR] $(date -u +%H:%M:%S) $*" >&2
}

# -----------------------------------------------------------------------------
# Prerequisites check (DATA-06)
# -----------------------------------------------------------------------------

check_prerequisites() {
  local missing=()

  command -v curl  >/dev/null 2>&1 || missing+=("curl")
  command -v aws   >/dev/null 2>&1 || missing+=("aws (AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)")
  command -v jq    >/dev/null 2>&1 || missing+=("jq (https://jqlang.github.io/jq/download/)")
  command -v unzip >/dev/null 2>&1 || missing+=("unzip")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools:"
    printf '  - %s\n' "${missing[@]}" >&2
    return 1
  fi

  # Verify AWS credentials work with the expected profile
  if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    log_error "AWS credentials not configured for profile '$AWS_PROFILE'"
    log_error "Run: aws configure --profile $AWS_PROFILE"
    return 1
  fi

  log_info "All prerequisites satisfied (curl, aws, jq, unzip, AWS profile '$AWS_PROFILE')"
}

# -----------------------------------------------------------------------------
# Bucket discovery from CloudFormation stack outputs
# -----------------------------------------------------------------------------

discover_bucket() {
  local bucket_override="${1:-}"

  # Allow --bucket override for flexibility
  if [[ -n "$bucket_override" ]]; then
    log_info "Using provided bucket: $bucket_override"
    echo "$bucket_override"
    return 0
  fi

  log_info "Discovering bucket from CloudFormation stack '$CF_STACK_NAME'..."

  local bucket
  bucket=$(aws cloudformation describe-stacks \
    --stack-name "$CF_STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text \
    --profile "$AWS_PROFILE" 2>/dev/null) || true

  if [[ -z "$bucket" || "$bucket" == "None" ]]; then
    log_error "Could not discover bucket from stack '$CF_STACK_NAME'"
    log_error "Either deploy the CDK stack first (cd infra && npx cdk deploy)"
    log_error "or pass --bucket BUCKET_NAME to override"
    return 1
  fi

  log_info "Discovered bucket: $bucket"
  echo "$bucket"
}

# -----------------------------------------------------------------------------
# Download a single file from URL to local path (idempotent via curl -z)
# -----------------------------------------------------------------------------

download_file() {
  local url="$1"
  local dest="$2"
  local filename
  filename=$(basename "$url")

  # Create destination directory if needed
  mkdir -p "$(dirname "$dest")"

  # curl -z provides conditional download (only if remote is newer)
  # curl -f fails silently on HTTP errors, -S shows error, -L follows redirects
  # --retry 3 with --retry-delay 5 for transient failures
  curl -fSL --retry 3 --retry-delay 5 \
    -z "$dest" \
    -o "$dest" \
    "$url" 2>&1 || {
    local exit_code=$?
    if [[ $exit_code -eq 22 ]]; then
      log_error "HTTP error downloading $filename (possibly 403/404)"
      log_error "If this is a GCS file, the bucket may have become requester-pays."
      log_error "Consider installing gsutil and using: gsutil -u YOUR_PROJECT cp gs://... $dest"
    else
      log_error "Failed to download $filename (curl exit code: $exit_code)"
    fi
    return 1
  }

  # Verify file is non-empty after download
  if [[ ! -s "$dest" ]]; then
    log_error "Downloaded file is empty: $dest"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Upload a local directory to an S3 prefix (idempotent via aws s3 sync)
# -----------------------------------------------------------------------------

upload_to_s3() {
  local local_dir="$1"
  local s3_prefix="$2"

  log_info "Uploading $local_dir -> $s3_prefix"
  aws s3 sync "$local_dir" "$s3_prefix" \
    --profile "$AWS_PROFILE" \
    --no-progress
  log_info "Upload complete: $s3_prefix"
}
