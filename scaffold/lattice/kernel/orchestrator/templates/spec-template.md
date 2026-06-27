---
id: {spec-id}
status: drafted
execution_mode: {plan|tdd}
owner: {owner}
created_at: {timestamp}
updated_at: {timestamp}
---

# Spec: {Title}

> Default Lattice template. Projects may override `specs.template` in
> `lattice/manifest.yaml` with a team/domain-specific template.

## Intent

{One sentence: what problem this change solves and why it matters.}

## Scope

### In

- {In-scope behavior / module / user impact}

### Out

- {Explicitly excluded behavior / module / follow-up}

## Context

> Include only the few constraints needed for this task. Do not paste the entire knowledge base.

| Source | Constraint | Why it matters |
|--------|------------|----------------|
| manifest / code / knowledge | | |

## Acceptance Criteria

> AC numbers are stable and trace through spec -> plan -> tests -> verification.

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | | | |

## Design Decisions

> Record only one-way decisions that need human review. Do not lock low-level implementation details the model can infer safely from code.

| # | Decision | Rationale | Reversible? |
|---|----------|-----------|-------------|
| D-1 | | | yes / no |

## Risk Notes

> Required for money, security, permissions, state machines, data consistency, concurrency, idempotency, or regression-prone behavior.

| Risk | Mitigation | Verification |
|------|------------|--------------|
| | | |

## Execution Policy

- Mode: `{plan|tdd}`
- Reason: {why this mode was selected}
- Source: model-selected | project-default | user-override

Use `plan` for low-risk, routine changes where a reviewed plan plus normal tests is enough. Use `tdd` when behavior must be pinned by red tests first: bug fixes, core flows, money/security/permission/state-machine logic, concurrency, idempotency, or historical regression points.

## Verification Plan

| Gate / Test | Required? | Notes |
|-------------|-----------|-------|
| spec-lint | yes | |
| build | yes | |
| lint | yes | |
| unit-test | yes | |
| ac-coverage | plan: conditional / tdd: yes | |
| drift-check | conditional | Required for API/schema/error-code changes |
| smoke / integration | conditional | |
