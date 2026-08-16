# Plan: Declaration Warn AC

## Source

- Spec: `halo/specs/decl-warn-ac/spec.md`
- Execution mode: plan

## Global Constraints

- Versions / dependencies: use existing Go module.

## Tasks

- [ ] T1: Add create behavior
  - 覆盖验收：以下条目补充说明
  - 模式：plan
  - 范围：实现满足 AC-1 的最小创建路径。
  - 涉及文件：`internal/handler/item.go`
  - 验证方式：`go test ./internal/handler -run TestWarnAC1`
  - 证据：
    - 任务简报：`.halo/sdd/decl-warn-ac/T1/brief.md`
    - 评审包：`.halo/sdd/decl-warn-ac/T1/review-package.md`
  - 完成条件：
    - [ ] AC-1 通过聚焦验证且证据存在。
