# Phase 1: Infrastructure - Research

**Researched:** 2026-03-05
**Domain:** AWS CDK v2 -- S3, Glue, Athena, IAM
**Confidence:** HIGH

## Summary

Phase 1 provisions all AWS resources via a single CDK v2 stack: an S3 bucket with prefix-based zones, a Glue database (namespace for Iceberg tables created later via Athena DDL), an Athena workgroup with per-query scan limits, and IAM roles granting Athena access to S3 and Glue. This is a straightforward infrastructure-as-code task using well-documented L1/L2 CDK constructs.

The Glue database itself does not require Iceberg-specific configuration at the CDK level. Iceberg is configured at table creation time (Phase 3) via Athena's `TBLPROPERTIES ('table_type' = 'ICEBERG')`. The CDK stack just creates the empty database namespace, the S3 location, and the Athena workgroup.

**Primary recommendation:** Use `aws-cdk-lib` L1 constructs (`CfnDatabase`, `CfnWorkGroup`) for Glue and Athena, and the L2 `s3.Bucket` construct for S3. No alpha packages needed -- the L2 Glue `Database` construct adds no value for a simple database, and there is no L2 Athena workgroup construct.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Single stack containing all resources (S3, Glue, Athena, IAM)
- CDK v2 with higher-level L3 constructs where available (e.g., @aws-cdk/aws-glue-alpha)
- Project layout: top-level folders -- `infra/` for CDK, `scripts/` for shell pipeline, `queries/` for SQL
- Bucket naming: fixed convention `open-images-{account}-{region}`
- Encryption: SSE-S3 (AWS-managed keys, default)
- Versioning: disabled
- Three-prefix zone layout: `raw/` for source CSVs, `warehouse/` for Iceberg Parquet, `queries/` for saved SQL files
- Auto-delete objects + removal policy DESTROY for clean `cdk destroy`
- Per-query scan limit: 10 GB
- No workgroup-level daily/monthly cap
- Query results stored in the S3 bucket (queries/ prefix or separate results prefix)
- Single environment -- no dev/staging/prod separation
- Resource naming convention: `open-images-*` prefix for all resources
- Standard AWS tags: project, environment, owner, cost-center

### Claude's Discretion
- Exact IAM policy scoping (least privilege)
- Athena query results location configuration
- CDK output values to export

### Deferred Ideas (OUT OF SCOPE)
None
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFRA-01 | CDK stack provisions S3 bucket with two-zone layout (raw/ and warehouse/) | S3 `Bucket` L2 construct with prefix conventions; no CDK prefix resources needed -- prefixes created implicitly by data operations |
| INFRA-02 | CDK stack provisions Glue database configured as Iceberg catalog | `CfnDatabase` L1 construct creates the namespace; Iceberg configuration happens at table creation (Phase 3) via Athena DDL |
| INFRA-03 | CDK stack provisions Athena workgroup with per-query scan cost limits | `CfnWorkGroup` with `bytesScannedCutoffPerQuery: 10737418240` (10 GB) and `enforceWorkGroupConfiguration: true` |
| INFRA-04 | CDK stack supports clean teardown via `cdk destroy` | `removalPolicy: DESTROY` + `autoDeleteObjects: true` on S3 bucket |
| INFRA-05 | CDK stack provisions necessary IAM roles for Athena-to-S3 and Glue access | IAM policy with scoped S3 and Glue permissions (see IAM section below) |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| aws-cdk-lib | ^2.241.0 | CDK v2 core library | All CDK v2 constructs in one package |
| constructs | ^10.0.0 | CDK construct base | Required peer dependency for CDK v2 |
| typescript | ^5.5.0 | Language | CDK TypeScript is the primary supported language |
| ts-node | ^10.9.0 | Execute TS without compile step | Standard for CDK apps |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @aws-cdk/aws-glue-alpha | ^2.238.0-alpha.0 | L2 Glue constructs | Only if the user wants it per CONTEXT.md; for a bare database, CfnDatabase is simpler |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CfnDatabase (L1) | @aws-cdk/aws-glue-alpha Database (L2) | L2 adds `databaseArn` convenience but alpha package adds dependency churn; either works for a plain database |
| CfnWorkGroup (L1) | No L2 exists | CfnWorkGroup is the only option for Athena workgroups in CDK |

**Installation:**
```bash
mkdir infra && cd infra
npx cdk init app --language typescript
# aws-cdk-lib and constructs are installed by cdk init
```

## Architecture Patterns

### Recommended Project Structure
```
infra/
  bin/
    infra.ts              # CDK app entry point
  lib/
    open-images-stack.ts  # Single stack with all resources
  cdk.json
  tsconfig.json
  package.json
scripts/                  # Shell pipeline (Phase 2)
queries/                  # SQL files (Phase 5)
```

### Pattern 1: Single Stack, Logical Sections
**What:** Group all resources in one stack file, organized by service (S3, Glue, Athena, IAM) with comment separators.
**When to use:** Small infrastructure with < 20 resources, single environment.
**Example:**
```typescript
// Source: AWS CDK best practices
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export class OpenImagesStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const tags = {
      project: 'open-images',
      environment: 'production',
      owner: 'data-team',
      'cost-center': 'analytics',
    };
    Object.entries(tags).forEach(([k, v]) => cdk.Tags.of(this).add(k, v));

    // ---- S3 ----
    const bucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `open-images-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
    });

    // ---- Glue ----
    const database = new glue.CfnDatabase(this, 'Database', {
      catalogId: this.account,
      databaseInput: {
        name: 'open_images',
        description: 'Open Images V7 Iceberg tables',
        locationUri: `s3://${bucket.bucketName}/warehouse/`,
      },
    });

    // ---- Athena ----
    const workgroup = new athena.CfnWorkGroup(this, 'Workgroup', {
      name: 'open-images',
      description: 'Open Images query workgroup',
      state: 'ENABLED',
      workGroupConfiguration: {
        bytesScannedCutoffPerQuery: 10 * 1024 * 1024 * 1024, // 10 GB
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetricsEnabled: true,
        resultConfiguration: {
          outputLocation: `s3://${bucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        engineVersion: {
          selectedEngineVersion: 'Athena engine version 3',
        },
      },
      recursiveDeleteOption: true,
    });

    // ---- IAM ----
    // (see IAM section below)

    // ---- Outputs ----
    new cdk.CfnOutput(this, 'BucketName', { value: bucket.bucketName });
    new cdk.CfnOutput(this, 'DatabaseName', { value: 'open_images' });
    new cdk.CfnOutput(this, 'WorkgroupName', { value: workgroup.name });
    new cdk.CfnOutput(this, 'BucketArn', { value: bucket.bucketArn });
  }
}
```

### Pattern 2: IAM Least Privilege for Athena+Glue+S3
**What:** Scoped IAM policy allowing Athena to read/write the specific S3 bucket and access the specific Glue database.
**When to use:** Always -- principle of least privilege.
**Example:**
```typescript
// Source: AWS Athena documentation on IAM permissions
const athenaRole = new iam.Role(this, 'AthenaRole', {
  roleName: 'open-images-athena-role',
  assumedBy: new iam.ServicePrincipal('athena.amazonaws.com'),
});

// S3 permissions: read/write data and query results
bucket.grantReadWrite(athenaRole);

// Glue catalog permissions
athenaRole.addToPolicy(new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: [
    'glue:GetDatabase',
    'glue:GetDatabases',
    'glue:GetTable',
    'glue:GetTables',
    'glue:GetPartition',
    'glue:GetPartitions',
    'glue:CreateTable',
    'glue:UpdateTable',
    'glue:DeleteTable',
    'glue:BatchGetPartition',
  ],
  resources: [
    `arn:aws:glue:${this.region}:${this.account}:catalog`,
    `arn:aws:glue:${this.region}:${this.account}:database/open_images`,
    `arn:aws:glue:${this.region}:${this.account}:table/open_images/*`,
  ],
}));
```

**Note on IAM for Athena:** In practice, Athena queries run under the *caller's* IAM identity (the user or role that calls `StartQueryExecution`), not a separate Athena service role. A dedicated "Athena role" is not strictly necessary unless you want to use it for cross-service access. For this project, the simpler approach is to ensure the deploying user/role has the required Glue and S3 permissions. However, creating a dedicated role and outputting its ARN is useful for documentation and for scripts in Phase 2 that call Athena.

### Anti-Patterns to Avoid
- **Creating S3 prefixes as CDK resources:** S3 prefixes are virtual -- they are created implicitly when objects are uploaded. Do not try to create `raw/`, `warehouse/`, or `queries/` as resources.
- **Using `CREATE EXTERNAL TABLE` for Iceberg:** Athena Iceberg tables must use `CREATE TABLE`, not `CREATE EXTERNAL TABLE`. Using `EXTERNAL` causes error: "External keyword not supported for table type ICEBERG."
- **Hardcoding account/region in bucket name:** Use `this.account` and `this.region` CDK tokens so the stack is portable.
- **Forgetting `enforceWorkGroupConfiguration: true`:** Without enforcement, individual queries can override the workgroup's scan limit and results location.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| S3 bucket cleanup on destroy | Custom Lambda to empty bucket | `autoDeleteObjects: true` on `s3.Bucket` | CDK creates the cleanup Lambda automatically; custom ones break on edge cases |
| Athena workgroup | Raw CloudFormation YAML | `CfnWorkGroup` construct | Type-safe properties, handles dependencies |
| Unique bucket naming | Random suffix generation | `open-images-${this.account}-${this.region}` pattern | Account+region is globally unique by definition |

## Common Pitfalls

### Pitfall 1: autoDeleteObjects requires removalPolicy DESTROY
**What goes wrong:** Setting `autoDeleteObjects: true` without `removalPolicy: cdk.RemovalPolicy.DESTROY` causes a CDK synth error.
**Why it happens:** CDK validates that auto-delete only makes sense with DESTROY policy.
**How to avoid:** Always set both together.
**Warning signs:** CDK synth fails with validation error.

### Pitfall 2: CfnDatabase name must be lowercase
**What goes wrong:** Glue database names with uppercase characters cause deployment failures.
**Why it happens:** AWS Glue requires database names to be lowercase, following Hive metastore conventions.
**How to avoid:** Use `open_images` (lowercase with underscores), not `OpenImages` or `open-images` (hyphens not allowed either).
**Warning signs:** CloudFormation deployment fails with "InvalidInputException".

### Pitfall 3: bytesScannedCutoffPerQuery minimum value
**What goes wrong:** Setting the scan limit too low causes all queries to fail.
**Why it happens:** Minimum value is 10,000,000 bytes (10 MB). Values below this are rejected.
**How to avoid:** 10 GB (10,737,418,240 bytes) is a reasonable limit for this dataset size.
**Warning signs:** CloudFormation deployment error on workgroup creation.

### Pitfall 4: Athena query results location must end with /
**What goes wrong:** Query results scattered or inaccessible.
**Why it happens:** Athena appends query IDs to the output path; without trailing slash the path is malformed.
**How to avoid:** Use `s3://bucket/athena-results/` (trailing slash).
**Warning signs:** Queries succeed but results are hard to find.

### Pitfall 5: Glue database locationUri for Iceberg
**What goes wrong:** Setting `locationUri` to the wrong path causes Iceberg tables to write data outside the intended zone.
**Why it happens:** The database `locationUri` becomes the default location for tables in that database.
**How to avoid:** Point `locationUri` to `s3://bucket/warehouse/` so Iceberg tables default to the warehouse zone.
**Warning signs:** Data appears in unexpected S3 paths.

### Pitfall 6: Athena engine version for Iceberg support
**What goes wrong:** Iceberg operations fail or are limited.
**Why it happens:** Iceberg support requires Athena engine version 3.
**How to avoid:** Explicitly set `engineVersion.selectedEngineVersion: 'Athena engine version 3'`.
**Warning signs:** DDL errors when creating Iceberg tables in Phase 3.

## Code Examples

### Athena Workgroup with Cost Controls
```typescript
// Source: https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_athena.CfnWorkGroup.html
const workgroup = new athena.CfnWorkGroup(this, 'Workgroup', {
  name: 'open-images',
  state: 'ENABLED',
  recursiveDeleteOption: true, // allows cdk destroy to remove workgroup with saved queries
  workGroupConfiguration: {
    bytesScannedCutoffPerQuery: 10 * 1024 * 1024 * 1024, // 10 GB
    enforceWorkGroupConfiguration: true,
    publishCloudWatchMetricsEnabled: true,
    engineVersion: {
      selectedEngineVersion: 'Athena engine version 3',
    },
    resultConfiguration: {
      outputLocation: `s3://${bucket.bucketName}/athena-results/`,
      encryptionConfiguration: {
        encryptionOption: 'SSE_S3',
      },
    },
  },
});
```

### Glue Database for Iceberg Tables
```typescript
// Source: https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_glue.CfnDatabase.html
const database = new glue.CfnDatabase(this, 'Database', {
  catalogId: this.account,
  databaseInput: {
    name: 'open_images',
    description: 'Open Images V7 annotation data in Iceberg format',
    locationUri: `s3://${bucket.bucketName}/warehouse/`,
  },
});
```

### S3 Bucket with Auto-Delete
```typescript
// Source: https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_s3.Bucket.html
const bucket = new s3.Bucket(this, 'DataBucket', {
  bucketName: `open-images-${this.account}-${this.region}`,
  encryption: s3.BucketEncryption.S3_MANAGED,
  versioned: false,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  removalPolicy: cdk.RemovalPolicy.DESTROY,
  autoDeleteObjects: true,
});
```

### CDK Outputs for Downstream Phases
```typescript
// Outputs consumed by shell scripts in Phase 2
new cdk.CfnOutput(this, 'BucketName', {
  value: bucket.bucketName,
  exportName: 'open-images-bucket-name',
});
new cdk.CfnOutput(this, 'DatabaseName', {
  value: 'open_images',
  exportName: 'open-images-database-name',
});
new cdk.CfnOutput(this, 'WorkgroupName', {
  value: 'open-images',
  exportName: 'open-images-workgroup-name',
});
new cdk.CfnOutput(this, 'BucketArn', {
  value: bucket.bucketArn,
  exportName: 'open-images-bucket-arn',
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CDK v1 (separate packages per service) | CDK v2 (single `aws-cdk-lib`) | 2022 | Use `aws-cdk-lib` only |
| Athena engine v2 | Athena engine v3 | 2023 | Required for full Iceberg support |
| Glue tables for Iceberg via CDK | Athena DDL for Iceberg tables | Current best practice | CDK creates database; Athena SQL creates tables |
| Custom S3 cleanup Lambda | `autoDeleteObjects: true` | CDK v2 | Built-in, no custom code needed |

**Deprecated/outdated:**
- CDK v1 packages (`@aws-cdk/aws-s3`, etc.) -- use `aws-cdk-lib` submodules
- Athena engine version 2 -- version 3 is current and required for Iceberg

## Open Questions

1. **Athena query results: `queries/` prefix vs `athena-results/` prefix**
   - What we know: CONTEXT.md says "queries/ prefix or separate results prefix" for query results
   - What's unclear: Whether to reuse `queries/` (which is also for saved SQL files) or create a separate `athena-results/` prefix
   - Recommendation: Use `athena-results/` prefix to avoid mixing SQL files with query output. The `queries/` folder in the project root is for SQL source files, not Athena output.

2. **IAM: Dedicated role vs caller identity**
   - What we know: Athena queries run under the caller's identity, not a service role
   - What's unclear: Whether to create a dedicated IAM role or rely on the deploying user's permissions
   - Recommendation: Create a dedicated IAM policy (not role) that can be attached to users/roles. Output the policy ARN. This documents the minimum permissions without assuming execution context.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | CDK assertions (built into aws-cdk-lib/assertions) |
| Config file | infra/jest.config.js (created by `cdk init`) |
| Quick run command | `cd infra && npx jest --passWithNoTests` |
| Full suite command | `cd infra && npx jest` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | S3 bucket created with correct name and config | unit (CDK assertion) | `cd infra && npx jest --testPathPattern=stack.test -t "S3"` | No -- Wave 0 |
| INFRA-02 | Glue database exists with correct name and locationUri | unit (CDK assertion) | `cd infra && npx jest --testPathPattern=stack.test -t "Glue"` | No -- Wave 0 |
| INFRA-03 | Athena workgroup with 10GB scan limit and enforce=true | unit (CDK assertion) | `cd infra && npx jest --testPathPattern=stack.test -t "Athena"` | No -- Wave 0 |
| INFRA-04 | S3 bucket has DESTROY policy and auto-delete | unit (CDK assertion) | `cd infra && npx jest --testPathPattern=stack.test -t "destroy"` | No -- Wave 0 |
| INFRA-05 | IAM policy with required Glue and S3 actions | unit (CDK assertion) | `cd infra && npx jest --testPathPattern=stack.test -t "IAM"` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `cd infra && npx jest --passWithNoTests`
- **Per wave merge:** `cd infra && npx jest`
- **Phase gate:** Full suite green + successful `cdk synth`

### Wave 0 Gaps
- [ ] `infra/test/open-images-stack.test.ts` -- CDK assertion tests for all 5 requirements
- [ ] CDK project initialization (`cdk init` creates jest config and test scaffold)

## Sources

### Primary (HIGH confidence)
- [CfnWorkGroup API](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_athena.CfnWorkGroup.html) - workgroup config, bytesScannedCutoffPerQuery, resultConfiguration
- [CfnDatabase API](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_glue.CfnDatabase.html) - database creation with databaseInput
- [S3 Bucket API](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_s3.Bucket.html) - autoDeleteObjects, removalPolicy
- [Athena Iceberg table creation](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-creating-tables.html) - TBLPROPERTIES, CREATE TABLE (not EXTERNAL)

### Secondary (MEDIUM confidence)
- [Athena IAM permissions](https://docs.aws.amazon.com/athena/latest/ug/managed-policies.html) - required Glue and S3 actions
- [aws-cdk-lib npm](https://www.npmjs.com/package/aws-cdk-lib) - current version 2.241.0
- [@aws-cdk/aws-glue-alpha npm](https://www.npmjs.com/package/@aws-cdk/aws-glue-alpha) - current version 2.238.0-alpha.0

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - CDK v2 is mature, constructs well-documented
- Architecture: HIGH - single-stack CDK is a standard pattern, all constructs are L1/L2
- Pitfalls: HIGH - documented in CDK issues and AWS docs (autoDeleteObjects, Glue naming, Iceberg engine version)

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (CDK constructs are stable; L1 constructs track CloudFormation which changes slowly)
