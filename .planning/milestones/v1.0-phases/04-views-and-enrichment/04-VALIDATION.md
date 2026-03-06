---
phase: 04
slug: views-and-enrichment
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash scripts + Athena SQL queries |
| **Config file** | scripts/lib/athena.sh |
| **Quick run command** | `bash scripts/verify-views.sh --quick` |
| **Full suite command** | `bash scripts/verify-views.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/verify-views.sh --quick`
- **After every plan wave:** Run `bash scripts/verify-views.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | VIEW-01 | smoke | `bash scripts/verify-views.sh` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | VIEW-02 | smoke | `bash scripts/verify-views.sh` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | VIEW-03, MASK-01 | smoke | `bash scripts/verify-views.sh` | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 1 | VIEW-04 | smoke | `bash scripts/verify-views.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `queries/views/` — directory for view SQL files
- [ ] `scripts/create-views.sh` — runner script for view creation
- [ ] `scripts/verify-views.sh` — verification script for view checks
- [ ] All 4 SQL view files (01-labeled-images.sql through 04-labeled-relationships.sql)

*Wave 0 creates all files during plan execution.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Views queryable in Athena console | VIEW-01..04 | Requires AWS credentials | Run `SELECT * FROM open_images.labeled_images LIMIT 5` in Athena console |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
