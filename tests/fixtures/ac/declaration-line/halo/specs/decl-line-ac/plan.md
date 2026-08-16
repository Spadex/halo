# Plan: Declaration Line AC

## Source

- Spec: `halo/specs/decl-line-ac/spec.md`
- Execution mode: tdd

## Global Constraints

- Versions / dependencies: use existing Go module.
- Out-of-scope: export behavior.

## Tasks

- [ ] RED-1: Add failing tests for the create and get paths
  - 覆盖验收：AC-1, AC-2
  - 预期失败：处理器尚未实现创建与读取路径。注意：本任务不覆盖 AC-3，AC-3 由 RED-2 处理。
  - 测试文件：`internal/handler/item_test.go`
  - 验证方式：`go test ./internal/handler -run TestDeclAC`
  - 完成条件：
    - [ ] 预期失败已记录到对应任务证据。

- [ ] RED-2: Add failing test for the list path
  - Covers: AC-3, AC-14
  - 预期失败：处理器尚未实现列表路径，与 upstream-spec AC-14 的返回形状对照。
  - 测试文件：`internal/handler/item_list_test.go`
  - 验证方式：`go test ./internal/handler -run TestDeclList`
  - 完成条件：
    - [ ] 预期失败已记录到对应任务证据。

- [ ] T1: Implement the three handler paths
  - 覆盖验收：AC-1, AC-2, AC-3
  - 模式：tdd
  - 范围：实现满足 AC-1 至 AC-3 的最小路径。
  - 涉及文件：`internal/handler/item.go`
  - 验证方式：`go test ./internal/handler -run TestDecl`
  - 证据：
    - 任务简报：`.halo/sdd/decl-line-ac/T1/brief.md`
    - 评审包：`.halo/sdd/decl-line-ac/T1/review-package.md`
  - 完成条件：
    - [ ] AC-1 至 AC-3 通过聚焦验证且证据存在。
