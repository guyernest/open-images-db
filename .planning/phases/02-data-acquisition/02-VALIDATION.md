---
phase: 2
slug: data-acquisition
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell script self-validation (no external test framework) |
| **Config file** | none — validation is built into the download scripts |
| **Quick run command** | `bash scripts/download-all.sh --validate-only` |
| **Full suite command** | `bash scripts/download-all.sh` (includes post-download validation) |
| **Estimated runtime** | ~30 seconds (validate-only), ~10-30 minutes (full download) |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/download-all.sh --validate-only`
- **After every plan wave:** Run `bash scripts/download-all.sh` (full suite)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds (validate-only mode)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | DATA-01 | smoke | `aws s3 ls s3://$BUCKET/raw/annotations/ --profile ze-kasher-dev` | W0 | pending |
| 02-01-02 | 01 | 1 | DATA-02 | smoke | `aws s3 ls s3://$BUCKET/raw/metadata/ --profile ze-kasher-dev` | W0 | pending |
| 02-01-03 | 01 | 1 | DATA-03 | smoke | `aws s3 ls s3://$BUCKET/raw/masks/ --summarize --profile ze-kasher-dev` | W0 | pending |
| 02-01-04 | 01 | 1 | DATA-04 | integration | Run download-all.sh twice, verify no size changes | manual | pending |
| 02-01-05 | 01 | 1 | DATA-05 | smoke | Verified by successful download (public HTTPS, no auth needed) | N/A | pending |
| 02-01-06 | 01 | 1 | DATA-06 | manual-only | Review scripts/README.md exists and is complete | manual | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

- [ ] `scripts/` directory — does not exist yet
- [ ] `scripts/download-all.sh` — orchestrator script with --validate-only flag
- [ ] `scripts/lib/` — shared function library (common.sh)
- [ ] No external test framework needed — validation built into scripts

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Execution instructions complete | DATA-06 | Requires human review of documentation clarity | Read scripts/README.md, verify a user can follow steps from scratch |
| Idempotent re-run | DATA-04 | Requires running pipeline twice and comparing | Run download-all.sh, note file sizes, run again, verify no changes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
