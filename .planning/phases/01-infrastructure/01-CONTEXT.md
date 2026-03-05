# Phase 1: Infrastructure - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

CDK stack provisions all AWS resources needed for the Open Images Athena Database: S3 bucket, Glue database (Iceberg catalog), Athena workgroup, and IAM roles. No data loading or table creation — just infrastructure.

</domain>

<decisions>
## Implementation Decisions

### CDK Structure
- Single stack containing all resources (S3, Glue, Athena, IAM)
- CDK v2 with higher-level L3 constructs where available (e.g., @aws-cdk/aws-glue-alpha)
- Project layout: top-level folders — `infra/` for CDK, `scripts/` for shell pipeline, `queries/` for SQL

### S3 Configuration
- Bucket naming: fixed convention `open-images-{account}-{region}`
- Encryption: SSE-S3 (AWS-managed keys, default)
- Versioning: disabled (one-time load, no version history needed)
- Three-prefix zone layout: `raw/` for source CSVs, `warehouse/` for Iceberg Parquet, `queries/` for saved SQL files
- Auto-delete objects + removal policy DESTROY for clean `cdk destroy`

### Athena Cost Controls
- Per-query scan limit: 10 GB
- No workgroup-level daily/monthly cap
- Query results stored in the S3 bucket (queries/ prefix or separate results prefix)

### Environment Strategy
- Single environment — no dev/staging/prod separation
- Resource naming convention: `open-images-*` prefix for all resources (bucket, database, workgroup)
- Standard AWS tags: project, environment, owner, cost-center

### Claude's Discretion
- Exact IAM policy scoping (least privilege)
- Athena query results location configuration
- CDK output values to export

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for CDK infrastructure provisioning.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project

### Established Patterns
- None — first phase, no existing code

### Integration Points
- CDK outputs (bucket name, database name, workgroup name) will be consumed by shell scripts in Phase 2
- Glue database must be configured for Iceberg table creation in Phase 3

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-infrastructure*
*Context gathered: 2026-03-05*
