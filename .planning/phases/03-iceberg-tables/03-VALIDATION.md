---
phase: 3
slug: iceberg-tables
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell script + Athena SQL queries |
| **Config file** | None — Wave 0 creates verify script |
| **Quick run command** | `scripts/verify-tables.sh --quick` |
| **Full suite command** | `scripts/verify-tables.sh` |
| **Estimated runtime** | ~30 seconds (7 Athena queries) |

---

## Sampling Rate

- **After every task commit:** Run `scripts/verify-tables.sh --quick` (SELECT LIMIT 1 against newly created table)
- **After every plan wave:** Run `scripts/verify-tables.sh` (all 7 tables, row counts, type checks)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | TBL-01 | smoke | `SELECT * FROM open_images.images LIMIT 1` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | TBL-02 | smoke | `SELECT * FROM open_images.class_descriptions LIMIT 1` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | TBL-03 | smoke | `SELECT * FROM open_images.labels LIMIT 1` | ❌ W0 | ⬜ pending |
| 03-01-04 | 01 | 1 | TBL-04 | smoke | `SELECT typeof(x_min), typeof(is_occluded) FROM open_images.bounding_boxes LIMIT 1` | ❌ W0 | ⬜ pending |
| 03-01-05 | 01 | 1 | TBL-05 | smoke | `SELECT * FROM open_images.masks LIMIT 1` | ❌ W0 | ⬜ pending |
| 03-01-06 | 01 | 1 | TBL-06 | smoke | `SELECT * FROM open_images.relationships LIMIT 1` | ❌ W0 | ⬜ pending |
| 03-01-07 | 01 | 1 | TBL-07 | smoke | `SELECT * FROM open_images.label_hierarchy LIMIT 1` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 2 | TBL-08 | manual | Verify table_type=ICEBERG in Glue catalog | N/A | ⬜ pending |
| 03-02-02 | 02 | 2 | TBL-09 | smoke | `SELECT typeof(confidence) FROM open_images.labels LIMIT 1` → 'double' | ❌ W0 | ⬜ pending |
| 03-02-03 | 02 | 2 | TBL-10 | smoke | `SELECT typeof(mask_path) FROM open_images.masks LIMIT 1` → 'varchar' | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/verify-tables.sh` — smoke test script that runs SELECT against all 7 tables, checks row counts > 0, verifies column types via typeof()
- [ ] `queries/tables/` directory — create directory structure for SQL files

*Wave 0 creates the verification infrastructure before any tables are built.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tables created via Athena DDL (not CDK) | TBL-08 | Requires checking Glue catalog metadata | Run `aws glue get-table --database open_images --name images` and verify `TableType` and `Parameters.table_type=ICEBERG` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
