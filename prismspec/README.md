# PrismSpec

PrismSpec 是一套可独立使用的渐进式 Spec-Driven Development skills，用于 AI Coding。

它只保留一条克制的主流程：

```text
brainstorm -> plan -> implement(plan|tdd) -> verify -> finish
```

## 定位

PrismSpec 可以独立使用，也可以被 Lattice 增强。

| 使用方式 | 你会得到什么 | 是否依赖 Lattice |
|----------|--------------|------------------|
| 独立模式 | 持久化 spec、plan、verify、summary，以及 plan/tdd 两种执行纪律 | 否 |
| Lattice-hosted | PrismSpec + manifest、知识库、交付 gate、AC coverage、drift check、compliance audit | 是 |

PrismSpec 不依赖 Lattice。Lattice 内置 PrismSpec，并把它作为默认的 spec-coding workflow。

## 产物结构

独立模式默认使用：

```text
prismspec/
├── skills/
├── templates/
└── specs/
    └── {spec-id}/
        ├── spec.md
        ├── plan.md
        ├── verify.md
        └── summary.md

.prismspec/
└── runs/
    └── {spec-id}/
        └── {task-id}/
            ├── brief.md
            └── review-package.md
```

如果项目存在 `lattice/manifest.yaml`，PrismSpec 会进入 Lattice-hosted 模式，并使用 Lattice 的宿主路径：

```text
lattice/specs/{spec-id}/{spec.md,plan.md,summary.md}
.lattice/sdd/{spec-id}/{task-id}/
```

## 执行模式

PrismSpec 只支持两种实现策略：

| 模式 | 适用场景 | 规则 |
|------|----------|------|
| `plan` | 低风险功能、文档、脚手架、直接重构 | 从已审查的 plan 执行；行为变化需要补测试 |
| `tdd` | bug fix、核心链路、安全/权限/资金逻辑、状态机、迁移、并发、幂等、历史回归点 | 先写红灯测试，再实现绿灯，最后重构 |

`auto` 表示由模型按风险选择 `plan` 或 `tdd`。当后续发现风险高于预期时，允许从 `plan -> tdd` 升级；不允许静默从 `tdd -> plan` 降级，除非用户显式覆盖。

## Skills

| Skill | 作用 |
|-------|------|
| `sdd.md` | 引导式 controller，解析当前阶段并从产物恢复 |
| `brainstorm.md` | 澄清需求并生成 `spec.md` |
| `plan.md` | 把 `spec.md` 拆成可执行、可审查、可追踪 AC 的 `plan.md` |
| `implement.md` | 按 plan 或 TDD 策略执行 |
| `verify.md` | 运行本地验证并记录证据 |
| `finish.md` | 生成 summary，沉淀后续工作和可复用经验 |
| `learn.md` | 捕获可复用知识 |

## 设计原则

PrismSpec 只有在一个流程节点能产生持久产物，或能避免真实工程风险时，才引入这个节点。

多一个流程，就多一层人工损耗。因此默认 workflow 保持克制：不是把 AI Coding 变成审批流，而是让需求、计划、实现和验证之间有可追踪的证据链。

---

## English Summary

PrismSpec is a standalone, progressive Spec-Driven Development skill module for AI coding.

It keeps the workflow intentionally small:

```text
brainstorm -> plan -> implement(plan|tdd) -> verify -> finish
```

PrismSpec can run standalone, or in Lattice-hosted mode. Standalone mode provides persistent specs, plans, verification notes, summaries, and plan/tdd execution discipline. Lattice-hosted mode adds manifest routing, knowledge loading, delivery gates, AC coverage, drift checks, and compliance audit.

PrismSpec does not depend on Lattice. Lattice embeds PrismSpec as its default spec-coding workflow.

Modes:

| Mode | Use When | Rule |
|------|----------|------|
| `plan` | Low-risk features, docs, scaffolding, straightforward refactors | Implement from a reviewed plan and add tests when behavior changes |
| `tdd` | Bug fixes, core flows, security/permission/money logic, state machines, migrations, concurrency, idempotency, regressions | Write red tests first, make them green, then refactor |

`auto` means the model chooses `plan` or `tdd` based on risk. `plan -> tdd` escalation is allowed when risk is discovered. `tdd -> plan` downgrade requires an explicit user override.
