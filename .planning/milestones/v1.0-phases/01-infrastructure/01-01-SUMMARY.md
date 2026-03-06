---
phase: 01-infrastructure
plan: 01
subsystem: infra
tags: [cdk, s3, glue, athena, iam, cloudformation, typescript]

# Dependency graph
requires: []
provides:
  - S3 bucket for raw CSVs, Iceberg warehouse, and Athena results
  - Glue database 'open_images' as Iceberg catalog namespace
  - Athena workgroup 'open-images' with 10GB scan limit and engine v3
  - IAM managed policy with scoped S3, Glue, and Athena permissions
  - CfnOutputs for bucket name, bucket ARN, database name, workgroup name, policy ARN
affects: [02-data-acquisition, 03-iceberg-tables, 04-views-enrichment, 05-validation-queries]

# Tech tracking
tech-stack:
  added: [aws-cdk-lib, constructs, typescript, ts-node]
  patterns: [single-stack CDK, L1 CfnDatabase/CfnWorkGroup, L2 s3.Bucket, CDK assertion tests]

key-files:
  created:
    - infra/lib/open-images-stack.ts
    - infra/test/open-images-stack.test.ts
    - infra/bin/infra.ts
    - infra/cdk.json
    - infra/package.json
    - infra/tsconfig.json
  modified: []

key-decisions:
  - "Used L1 CfnDatabase and CfnWorkGroup instead of alpha packages -- simpler, no dependency churn"
  - "Created IAM ManagedPolicy (not role) so it can be attached to any user/role"
  - "Used athena-results/ prefix instead of queries/ to avoid mixing SQL files with query output"
  - "CDK assertion tests use Match.objectLike for Fn::Join token references"

patterns-established:
  - "Single CDK stack in infra/ directory with logical sections by AWS service"
  - "TDD with CDK assertions: RED (stub stack) then GREEN (implementation)"
  - "Resource naming: open-images-* prefix for all AWS resources"

requirements-completed: [INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05]

# Metrics
duration: 3min
completed: 2026-03-05
---

# Phase 1 Plan 1: CDK Infrastructure Stack Summary

**Single CDK stack provisioning S3 bucket, Glue database, Athena workgroup with 10GB scan limit, and scoped IAM policy -- verified by 12 CDK assertion tests**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-05T18:22:16Z
- **Completed:** 2026-03-05T18:25:31Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- CDK project initialized with TypeScript, jest, and full test scaffold
- 12 CDK assertion tests covering all 5 INFRA requirements (S3, Glue, Athena, IAM, Teardown, Tags)
- OpenImagesStack with S3 bucket (SSE-S3, auto-delete, DESTROY), Glue database (open_images, warehouse/ location), Athena workgroup (10GB limit, engine v3, enforced config), and IAM managed policy
- `cdk synth` produces valid CloudFormation template with all resource types

## Task Commits

Each task was committed atomically:

1. **Task 1: Initialize CDK project and write assertion tests** - `a2531ad` (test -- TDD RED phase)
2. **Task 2: Implement OpenImagesStack to pass all tests** - `4bd66ee` (feat -- TDD GREEN phase)

_TDD progression: RED (12 failing tests) -> GREEN (12 passing tests)_

## Files Created/Modified
- `infra/lib/open-images-stack.ts` - Single CDK stack with S3, Glue, Athena, IAM resources and outputs (142 lines)
- `infra/test/open-images-stack.test.ts` - CDK assertion tests for all 5 INFRA requirements (198 lines)
- `infra/bin/infra.ts` - CDK app entry point instantiating OpenImagesStack
- `infra/cdk.json` - CDK configuration
- `infra/package.json` - Project dependencies (aws-cdk-lib, constructs)
- `infra/tsconfig.json` - TypeScript configuration
- `infra/jest.config.js` - Jest test configuration

## Decisions Made
- Used L1 CfnDatabase and CfnWorkGroup instead of alpha packages -- simpler and avoids dependency churn for plain database/workgroup
- Created IAM ManagedPolicy (not role) so it can be attached to any caller identity
- Used `athena-results/` prefix for query output instead of `queries/` to avoid collision with SQL source files
- CDK assertion tests use `Match.objectLike` with `Fn::Join` patterns for token-based URIs (bucket name is a CDK token)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed CDK token assertions in tests**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** Three tests used `Match.stringLikeRegexp` for LocationUri and OutputLocation, but CDK synthesizes these as `Fn::Join` objects (not plain strings) because `bucket.bucketName` is a token
- **Fix:** Changed assertions to use `Match.objectLike` with `Fn::Join` array matching
- **Files modified:** infra/test/open-images-stack.test.ts
- **Verification:** All 12 tests pass
- **Committed in:** 4bd66ee (Task 2 commit)

**2. [Rule 1 - Bug] Fixed incorrect SSEAlgorithm in first S3 test**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** First S3 test asserted `aws:kms` instead of `AES256` for S3_MANAGED encryption
- **Fix:** Corrected to `AES256`
- **Files modified:** infra/test/open-images-stack.test.ts
- **Verification:** Test passes with correct SSE-S3 algorithm
- **Committed in:** 4bd66ee (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs in test assertions)
**Impact on plan:** Both fixes corrected test assertions to match CDK synthesis behavior. No scope creep.

## Issues Encountered
None -- plan executed smoothly after test assertion corrections.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All AWS infrastructure resources defined and tested
- CfnOutputs export bucket name, database name, workgroup name, and policy ARN for downstream phases
- Stack ready for `cdk deploy` when AWS credentials are configured
- Glue database namespace ready for Iceberg table creation in Phase 3

## Self-Check: PASSED

- All 7 key files found on disk
- Both task commits (a2531ad, 4bd66ee) verified in git log
- open-images-stack.ts: 142 lines (min: 80)
- open-images-stack.test.ts: 198 lines (min: 50)

---
*Phase: 01-infrastructure*
*Completed: 2026-03-05*
