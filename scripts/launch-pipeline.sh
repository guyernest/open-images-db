#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# launch-pipeline.sh -- Launch Open Images EC2 pipeline instance
#
# Generic launcher: uploads scripts to S3, injects BUCKET into a userdata
# template, and launches a self-terminating EC2 instance with the
# open-images-ec2-profile instance profile.
#
# Usage:
#   bash scripts/launch-pipeline.sh [OPTIONS]
#
# Options:
#   --userdata FILE        Userdata template (required)
#   --instance-type TYPE   EC2 instance type (default: t3.medium)
#   --ebs-size GB          Root EBS volume size in GiB (default: 20)
#   --tag NAME             Instance Name tag (default: open-images-pipeline)
#   --help                 Show this help message
#
# Prerequisites:
#   - OpenImagesStack deployed (cd infra && npx cdk deploy)
#   - aws CLI configured (via assume <profile>, AWS_PROFILE, or instance role)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common.sh for logging and bucket discovery
source "$SCRIPT_DIR/lib/common.sh"

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

USERDATA_TEMPLATE=""
INSTANCE_TYPE="t3.medium"
EBS_SIZE="20"
INSTANCE_TAG="open-images-pipeline"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --userdata)
      USERDATA_TEMPLATE="${2:-}"
      if [[ -z "$USERDATA_TEMPLATE" ]]; then
        log_error "--userdata requires a file path"
        exit 1
      fi
      shift 2
      ;;
    --instance-type)
      INSTANCE_TYPE="${2:-}"
      if [[ -z "$INSTANCE_TYPE" ]]; then
        log_error "--instance-type requires a value"
        exit 1
      fi
      shift 2
      ;;
    --ebs-size)
      EBS_SIZE="${2:-}"
      if [[ -z "$EBS_SIZE" ]]; then
        log_error "--ebs-size requires a value"
        exit 1
      fi
      shift 2
      ;;
    --tag)
      INSTANCE_TAG="${2:-}"
      if [[ -z "$INSTANCE_TAG" ]]; then
        log_error "--tag requires a value"
        exit 1
      fi
      shift 2
      ;;
    --help)
      awk '/^# ={10}/{if(found)exit; found=1; next} found && /^#/{sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1 (use --help for usage)"
      exit 1
      ;;
  esac
done

if [[ -z "$USERDATA_TEMPLATE" ]]; then
  log_error "--userdata is required"
  exit 1
fi

if [[ ! -f "$USERDATA_TEMPLATE" ]]; then
  log_error "Userdata template not found: $USERDATA_TEMPLATE"
  exit 1
fi

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

main() {
  log_info "============================================"
  log_info "Open Images EC2 Pipeline Launcher"
  log_info "============================================"

  # Step 1: Check prerequisites
  log_info "Checking local prerequisites..."
  check_prerequisites

  # Step 2: Discover bucket from CloudFormation (sets BUCKET global)
  local bucket
  bucket=$(discover_bucket)

  # Step 3: Upload scripts to S3 so EC2 can download them
  log_info "============================================"
  log_info "Uploading pipeline scripts to S3..."
  log_info "============================================"

  aws s3 sync "$SCRIPT_DIR/" "s3://$bucket/pipeline-scripts/" \
    --exclude "*" \
    --include "*.sh" \
    --include "lib/*.sh" \
    --exclude "ec2-userdata*.sh" \
    --exclude "launch-pipeline.sh" \
    --exclude ".venv/*"

  log_info "Scripts uploaded to s3://$bucket/pipeline-scripts/"

  # Step 4: Generate userdata by injecting BUCKET into the template
  local temp_userdata
  temp_userdata=$(mktemp /tmp/open-images-userdata-XXXXXX)
  trap 'rm -f "${temp_userdata:-}"' EXIT

  sed "s|__BUCKET__|$bucket|g" \
    "$USERDATA_TEMPLATE" > "$temp_userdata"

  log_info "Userdata: $(basename "$USERDATA_TEMPLATE") (BUCKET=$bucket)"

  # Step 5: Launch EC2 instance
  log_info "============================================"
  log_info "Launching EC2 instance..."
  log_info "  Instance type: $INSTANCE_TYPE"
  log_info "  EBS volume:    ${EBS_SIZE} GiB"
  log_info "  Userdata:      $(basename "$USERDATA_TEMPLATE")"
  log_info "============================================"

  local instance_id
  instance_id=$(aws ec2 run-instances \
    --image-id "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
    --instance-type "$INSTANCE_TYPE" \
    --iam-instance-profile "Name=open-images-ec2-profile" \
    --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=${EBS_SIZE},VolumeType=gp3,DeleteOnTermination=true}" \
    --user-data "fileb://$temp_userdata" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_TAG}},{Key=project,Value=open-images}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

  log_info "============================================"
  log_info "Pipeline launched successfully!"
  log_info "Instance ID: $instance_id"
  log_info "============================================"
  log_info ""
  log_info "The instance will self-terminate on completion (success or failure)."
  log_info ""
  log_info "Monitor:  just instance-status $instance_id"
  log_info "Logs:     just console-output $instance_id"
}

main "$@"
