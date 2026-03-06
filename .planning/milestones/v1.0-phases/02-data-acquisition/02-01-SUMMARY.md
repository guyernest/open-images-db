---
phase: 02-data-acquisition
plan: 01
subsystem: data-pipeline
tags: [bash, shell, curl, aws-s3, open-images, download, idempotent]

# Dependency graph
requires:
  - phase: 01-infrastructure
    provides: S3 bucket and CloudFormation stack outputs for bucket discovery
provides:
  - Shell scripts to download Open Images V7 validation annotations, metadata, and mask PNGs
  - Idempotent data acquisition pipeline (curl -z + aws s3 sync)
  - S3 raw zone population (raw/annotations/, raw/metadata/, raw/masks/, raw/manifest.json)
  - Shared script library with logging, prerequisites check, bucket discovery, download and upload helpers
affects: [03-iceberg-tables, 04-views-enrichment, 05-validation-queries]

# Tech tracking
tech-stack:
  added: [curl, aws-s3-sync, jq, unzip]
  patterns: [two-hop transfer (HTTPS to local to S3), modular shell library with source, idempotent downloads via curl -z, idempotent uploads via aws s3 sync]

key-files:
  created:
    - scripts/lib/common.sh
    - scripts/lib/download-annotations.sh
    - scripts/lib/download-metadata.sh
    - scripts/lib/download-masks.sh
    - scripts/download-all.sh
    - scripts/README.md
  modified: []

key-decisions:
  - "Used curl for all downloads instead of gsutil -- public HTTPS URLs need no GCS auth"
  - "Mask archives downloaded and extracted sequentially with zip cleanup after each to minimize disk usage"
  - "AWS profile stored in common.sh as configurable readonly variable for single-point-of-change"

patterns-established:
  - "Shell library pattern: scripts/lib/*.sh sourced by orchestrator, each exporting one main function"
  - "Idempotent download: curl -z for conditional download, aws s3 sync for deduped upload"
  - "Bucket discovery: CloudFormation describe-stacks with --bucket override escape hatch"

requirements-completed: [DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06]

# Metrics
duration: 3min
completed: 2026-03-05
---

# Phase 2 Plan 1: Data Acquisition Pipeline Summary

**Shell scripts downloading Open Images V7 validation annotations (5 CSVs), metadata (3 CSVs), and segmentation masks (16 zip archives, ~24,730 PNGs) via curl to S3 raw zone with idempotent re-run support**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-05T20:15:33Z
- **Completed:** 2026-03-05T20:18:09Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Four modular shell library files (common, annotations, metadata, masks) with clean function boundaries
- Orchestrator script with --bucket, --validate-only, --skip-masks flags for flexible execution
- Post-download S3 validation checking file counts (5 annotations, 3 metadata, ~24,730 masks)
- Manifest generation via aws s3api list-objects-v2 piped through jq
- Comprehensive README with prerequisites, quick start, EC2/local instructions, and troubleshooting

## Task Commits

Each task was committed atomically:

1. **Task 1: Create shared library and download functions** - `4aefb34` (feat)
2. **Task 2: Create orchestrator script, validation, manifest, and README** - `70a246d` (feat)

## Files Created/Modified
- `scripts/lib/common.sh` - Shared functions: logging, prerequisites, bucket discovery, download_file, upload_to_s3 (123 lines)
- `scripts/lib/download-annotations.sh` - Downloads 5 annotation CSVs from public HTTPS URLs (50 lines)
- `scripts/lib/download-metadata.sh` - Downloads 3 metadata/class-description files (48 lines)
- `scripts/lib/download-masks.sh` - Downloads 16 mask zip archives, extracts flat PNGs, cleans up zips (80 lines)
- `scripts/download-all.sh` - Orchestrator with validation, manifest generation, argument parsing (248 lines)
- `scripts/README.md` - Execution instructions with prerequisites, options, troubleshooting (173 lines)

## Decisions Made
- Used curl for all downloads instead of gsutil -- research confirmed all Open Images annotation/mask URLs are publicly accessible via HTTPS, no GCS authentication needed
- Mask archives downloaded and extracted one at a time with immediate zip cleanup to minimize disk usage on constrained EC2 instances
- AWS profile stored as configurable readonly variable in common.sh rather than hardcoded in each function

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None -- all scripts passed bash -n syntax validation on first attempt.

## User Setup Required
None - no external service configuration required. AWS profile `ze-kasher-dev` and CDK stack must already be configured from Phase 1.

## Next Phase Readiness
- All raw data acquisition scripts ready for execution
- S3 raw zone layout (annotations/, metadata/, masks/, manifest.json) established for Phase 3 Iceberg table creation
- Manifest generation provides file inventory for Phase 5 validation queries

## Self-Check: PASSED

- All 6 key files found on disk
- Both task commits (4aefb34, 70a246d) verified in git log
- download-all.sh: 248 lines (min: 80)
- README.md: 173 lines (min: 40)

---
*Phase: 02-data-acquisition*
*Completed: 2026-03-05*
