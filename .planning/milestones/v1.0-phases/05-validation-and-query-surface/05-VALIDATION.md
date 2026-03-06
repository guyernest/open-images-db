---
phase: 5
slug: validation-and-query-surface
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash script with pass/fail assertions (no formal test framework) |
| **Config file** | N/A -- validation is the script itself |
| **Quick run command** | `bash scripts/validate-data.sh --quick` |
| **Full suite command** | `bash scripts/validate-data.sh` |
| **Estimated runtime** | ~60 seconds (Athena query latency) |

---

## Sampling Rate

- **After every task commit:** Verify file exists and has expected structure
- **After every plan wave:** Run `bash scripts/validate-data.sh` against live Athena
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | VAL-01 | integration (live Athena) | `bash scripts/validate-data.sh --quick` | No -- W0 | pending |
| 05-01-02 | 01 | 1 | VAL-02 | integration (live Athena) | `bash scripts/validate-data.sh` | No -- W0 | pending |
| 05-02-01 | 02 | 1 | QUERY-01, QUERY-02, QUERY-03 | manual review | `test -f docs/examples.md && grep -c '```sql' docs/examples.md` | No -- W0 | pending |
| 05-02-02 | 02 | 1 | QUERY-04 | manual review | `test -f docs/SCHEMA.md && wc -l docs/SCHEMA.md` | No -- W0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `scripts/validate-data.sh` -- stubs for VAL-01, VAL-02
- [ ] `docs/examples.md` -- stubs for QUERY-01, QUERY-02, QUERY-03
- [ ] `docs/SCHEMA.md` -- stubs for QUERY-04
- [ ] `docs/` directory creation -- first documentation artifacts outside .planning/

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Example queries are instructive and correct | QUERY-01, QUERY-02, QUERY-03 | Quality of documentation requires human review | Read docs/examples.md, verify each SQL block is syntactically correct and covers the intended pattern |
| Schema docs have semantic context | QUERY-04 | Semantic accuracy requires domain understanding | Read docs/SCHEMA.md, verify column descriptions match actual data semantics |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
