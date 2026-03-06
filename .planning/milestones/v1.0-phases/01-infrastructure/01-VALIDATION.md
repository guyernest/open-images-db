---
phase: 1
slug: infrastructure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | jest (CDK assertions via aws-cdk-lib/assertions) |
| **Config file** | infra/jest.config.js (created by `cdk init`) |
| **Quick run command** | `cd infra && npx jest --passWithNoTests` |
| **Full suite command** | `cd infra && npx jest` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd infra && npx jest --passWithNoTests`
- **After every plan wave:** Run `cd infra && npx jest`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | INFRA-01 | unit (CDK assertion) | `cd infra && npx jest -t "S3"` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | INFRA-02 | unit (CDK assertion) | `cd infra && npx jest -t "Glue"` | ❌ W0 | ⬜ pending |
| 01-01-03 | 01 | 1 | INFRA-03 | unit (CDK assertion) | `cd infra && npx jest -t "Athena"` | ❌ W0 | ⬜ pending |
| 01-01-04 | 01 | 1 | INFRA-04 | unit (CDK assertion) | `cd infra && npx jest -t "destroy"` | ❌ W0 | ⬜ pending |
| 01-01-05 | 01 | 1 | INFRA-05 | unit (CDK assertion) | `cd infra && npx jest -t "IAM"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `infra/test/open-images-stack.test.ts` — CDK assertion tests for all 5 requirements
- [ ] CDK project initialization (`cdk init` creates jest config and test scaffold)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `cdk deploy` creates actual resources | INFRA-01–05 | Requires AWS account | Run `cdk deploy` and verify resources in console |
| `cdk destroy` removes everything | INFRA-04 | Destructive operation, needs live test | Run `cdk destroy` and verify no resources remain |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
