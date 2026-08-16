---
id: decl-warn-ac
status: planned
execution_mode: plan
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Declaration Warn AC

## Intent

A declaration line without AC ids must warn and fall back to the whole-body scan.

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Create item | Returns 201 | TestWarnAC1 |
