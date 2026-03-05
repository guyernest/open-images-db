# Phase 2: Data Acquisition - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Shell scripts download all Open Images V7 validation set annotation data from GCS to S3 raw zone. Covers annotation CSVs, image metadata, and segmentation mask PNGs. No table creation or data transformation -- just raw data landing in S3.

</domain>

<decisions>
## Implementation Decisions

### Download strategy
- Two-hop transfer: gsutil from GCS, then aws s3 cp to S3
- Single orchestrator script (download-all.sh) that calls per-type functions
- Download to local temp directory first, verify, then upload to S3
- Auto-detect requester-pays: try without first, if 403 then prompt for GCS project ID
- Rust CLI fallback: if gsutil/aws CLI can't handle the 2.8M mask volume, escalate to a Rust-based download tool

### Mask PNG handling
- Download all masks in Phase 2 (don't defer)
- Store flat under raw/masks/ (no sharding)
- Resumable via skip-existing: check if mask already in S3 before downloading
- Parallel downloads using xargs -P or GNU parallel (16-32 threads)

### Script execution
- Primary target: EC2 instance (no timeout, high bandwidth)
- Scripts should also work on local machine with gsutil + aws CLI
- Progress summary output: per-type progress (e.g., "Downloading annotations... 5/8 files"), mask count/total
- Post-download validation: file count + size checks per data type
- Prerequisites check at start: verify gsutil, aws CLI, jq installed; fail with install instructions if missing (DATA-06)

### S3 raw zone layout
- Organized by data type: raw/annotations/, raw/metadata/, raw/masks/
- Preserve original GCS filenames for annotation CSVs (no renaming)
- JSON manifest (raw/manifest.json) listing all downloaded files with paths, sizes, timestamps, source URLs

### Claude's Discretion
- Exact gsutil flags and parallelism tuning
- Temp directory location and cleanup strategy
- Error retry logic and timeout values
- Whether to use gsutil -m (built-in parallelism) or external parallel tool

</decisions>

<specifics>
## Specific Ideas

- User prefers Rust code when possible -- if shell scripts + gsutil/aws CLI can't handle the mask download volume efficiently, build a Rust CLI tool instead
- Scripts must be idempotent (DATA-04) -- re-running should not corrupt or duplicate data

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- CDK stack outputs: bucket name (`open-images-{account}-{region}`), available via `aws cloudformation describe-stacks`
- AWS profile: `ze-kasher-dev` for all AWS CLI calls

### Established Patterns
- Project layout: `infra/` for CDK -- scripts should go in `scripts/` directory (decided in Phase 1 context)
- S3 bucket has raw/, warehouse/, athena-results/ prefix zones

### Integration Points
- Scripts write to `s3://open-images-{account}-{region}/raw/` (bucket from Phase 1)
- raw/manifest.json will be consumed by Phase 3 (Iceberg table creation) and Phase 5 (validation)
- Mask PNGs in raw/masks/ will be consumed by Phase 4 (mask enrichment)

</code_context>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 02-data-acquisition*
*Context gathered: 2026-03-05*
