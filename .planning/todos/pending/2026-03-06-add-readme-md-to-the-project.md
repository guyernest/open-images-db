---
created: 2026-03-06T02:00:09.798Z
title: Add README.md to the project
area: docs
files:
  - README.md
---

## Problem

The project has no README.md. A top-level README is needed to explain what the project does (Open Images V7 validation set loaded into Athena Iceberg tables), how to set it up (prerequisites, AWS configuration, CloudFormation stack), and how to use it (running scripts, querying via Athena). The docs/ directory has schema and example queries but there's no entry point for new users.

## Solution

Create a README.md covering:
- Project overview (Open Images V7 -> Athena Iceberg tables)
- Prerequisites (AWS CLI, jq, AWS account with Athena)
- Setup instructions (CloudFormation stack, script execution order)
- Usage (example queries, link to docs/examples.md and docs/SCHEMA.md)
- Project structure overview
