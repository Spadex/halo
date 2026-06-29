---
id: {spec-id}
title: {title}
status: drafted
template: tdd
execution_mode: tdd
mode_source: model-selected | project-default | user-override
approval: explicit | inferred | skipped-with-reason
owner: {owner}
created_at: {timestamp}
updated_at: {timestamp}
---

# TDD Spec: {Title}

## 1. Problem

{描述 bug、核心链路风险、历史回归点或必须被测试钉住的行为。}

## 2. Context Basis

> 只记录会影响红灯测试、回归边界、不变量、兼容性或验证策略的已采用事实。没有外部依据时写 N/A。

| Source | Constraint / Fact | Impact On Test |
|--------|-------------------|----------------|
| user request / bug report | | |
| code / tests | | |
| docs / incidents / knowledge | | |
| open questions / conflicts | | |

## 3. Regression Boundary

| Existing Behavior | Must Preserve? | Evidence |
|-------------------|----------------|----------|
| | yes / no | |

## 4. Invariants

| Invariant | Why It Must Hold | Verification |
|-----------|------------------|--------------|
| | | |

## 5. Acceptance Criteria

| # | Given | When | Then | Red Test |
|---|-------|------|------|----------|
| AC-1 | | | | `test('AC-1 ...')` |

## 6. Red Test Plan

| Test | Expected Initial Failure | Makes Green When |
|------|--------------------------|------------------|
| AC-1 | | |

## 7. Implementation Constraints

- {必须保持的接口、兼容性、性能、权限、数据一致性约束}

## 8. Risk Notes

| Risk | Mitigation | Verification |
|------|------------|--------------|
| regression | red/green evidence | |
| concurrency / idempotency / state | | |

## 9. Execution Policy

- Mode: `tdd`
- Reason: {为什么需要 red-first}
- Source: model-selected | project-default | user-override
- Rule: no red test, no implementation.

## 10. Verification Plan

| Gate / Test | Required? | Evidence |
|-------------|-----------|----------|
| focused red test | yes | |
| focused green test | yes | |
| full relevant unit suite | yes | |
| build / type-check | yes | |
| integration / smoke | conditional | |

## 11. Approval

- Status: explicit / inferred / skipped-with-reason
- Source: user message / project default / reason
- Notes: {审批、推断或跳过原因；没有则写 N/A}
