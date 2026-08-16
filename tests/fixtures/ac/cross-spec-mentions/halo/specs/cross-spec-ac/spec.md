---
id: cross-spec-ac
status: planned
execution_mode: tdd
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Cross Spec AC

## Intent

Declare AC-1..AC-3 while pointing at upstream-spec AC-14 for contrast.

## Non-Goals

- Re-verifying upstream-spec AC-14; that stays owned by the upstream spec.

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Create item | Returns 201 | TestXsAC1 |
| AC-2 | Get item | Returns item | TestXsAC2 |
| AC-3 | List items | Returns a list, unlike upstream-spec AC-14 | TestXsAC3 |
