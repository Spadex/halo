#!/usr/bin/env bash
# tests/helpers/fixtures.bash — 参数化 spec/plan 构造函数。
# 蓝本：smoke-test.sh 的 modern-feature fixture（已被 spec-lint、
# prismspec lint、plan-lint、task-next 全链路接受的最小形态）。
#
# 语法变体（交叉引用、断号、列序等）不进构造函数：
# 用例拿产物做 sed 改写，保持构造函数只有一种"黄金形态"。

# make_spec <specs_root> <id> [ac_count=2] [ac_start=1] [mode=tdd]
make_spec() {
  local root="$1" id="$2" ac_count="${3:-2}" ac_start="${4:-1}" mode="${5:-tdd}"
  local dir="$root/$id"
  mkdir -p "$dir"

  local ac_rows="" i ac
  for ((i = 0; i < ac_count; i++)); do
    ac=$((ac_start + i))
    ac_rows+="| AC-${ac} | Step ${ac} | Result ${ac} | TestAC${ac} |"$'\n'
  done

  cat > "$dir/spec.md" << EOF
---
id: ${id}
status: drafted
execution_mode: ${mode}
mode_source: model-selected
approval: inferred
owner: bats
created_at: 2026-01-01T00:00:00Z
updated_at: 2026-01-01T00:00:00Z
---

# Spec: ${id}

## Intent

Add a small behavior with AC tracing.

## Scope

### In

- Create behavior.

### Out

- Export behavior.

## Context Basis

| Source | Constraint | Why it matters |
|--------|------------|----------------|
| user | Bats fixture for gate contracts. | Use a minimal fixture. |
| code / tests | No production code is required for this fixture. | Keep scope small and AC ids stable. |
| open questions / conflicts | None. | No blocking decision required. |

## Architecture

Use the existing handler boundary. No new subsystem is required for this fixture.

## Interface

| Interface | Contract |
|-----------|----------|
| Handler | Behaviors must be observable through AC-named tests. |

## Invariants

| Invariant | Verification |
|-----------|--------------|
| AC ids remain stable and traceable. | spec-lint and ac-coverage fixtures |

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
${ac_rows}
## Design Decisions

| # | Decision | Rationale | Reversible? |
|---|----------|-----------|-------------|
| D-1 | Use existing handler | Minimal change | yes |

## Risk Notes

| Risk | Mitigation | Verification |
|------|------------|--------------|
| None | N/A | Tests |

## Execution Policy

- Mode: \`${mode}\`
- Reason: bats fixture validates the modern template.

## Verification Plan

| Gate / Test | Required? | Notes |
|-------------|-----------|-------|
| spec-lint | yes | |
| unit-test | yes | |
EOF
}

# make_plan <specs_root> <id> [ac_count=2] [ac_start=1] [style=ref]
# 每个 AC 生成一组 RED-n（红测试任务）+ T-n（实现任务），n 从 1 计数。
#
# style 决定任务体里那一行 AC 引用的写法，三者都是被 plan-lint 接受的黄金形态：
#   ref      `- Ref: AC-N`        存量形态：无覆盖声明行，门禁回退到任务全文扫描，
#                                 plan-lint 出 fallback warning 但不 fail。
#   decl-cn  `- 覆盖验收：AC-N`   现行形态（中文标签），门禁只读声明行。
#   decl-en  `- Covers: AC-N`     现行形态（英文标签），同上。
# 标签口径见 harness-template/halo/kernel/_lib.sh 的 ac_declaration_lines()。
#
# 「一个任务声明多条 AC / 声明外部 spec 的 AC / 声明行不含 AC token」等变体不进本函数，
# 走 tests/fixtures/ 静态文件——那些形态的价值在于可被逐字审阅。
make_plan() {
  local root="$1" id="$2" ac_count="${3:-2}" ac_start="${4:-1}" style="${5:-ref}"
  local dir="$root/$id"

  # 未知 style 必须报错退出，不得静默回落到默认形态：静默回落会让用例
  # 以为自己在测声明行，实际测的是 ref 形态，断言照样通过（假绿）。
  # 标签含分隔符与其后的间距，中文冒号后不留空格（与仓内既有 plan 写法一致）。
  local ac_label
  case "$style" in
    ref) ac_label="Ref: " ;;
    decl-cn) ac_label="覆盖验收：" ;;
    decl-en) ac_label="Covers: " ;;
    *)
      echo "make_plan: unknown style '${style}' (expected ref|decl-cn|decl-en)" >&2
      return 1
      ;;
  esac

  mkdir -p "$dir"

  local red_tasks="" impl_tasks="" i ac n
  for ((i = 0; i < ac_count; i++)); do
    ac=$((ac_start + i))
    n=$((i + 1))
    red_tasks+="- [ ] RED-${n}: Add failing test for AC-${ac}
  - ${ac_label}AC-${ac}
  - Expected failure: handler does not implement AC-${ac} yet
  - Test file: \`internal/handler/item_test.go\`
  - Verification: \`go test ./internal/handler -run TestAC${ac}\`
  - Done when:
    - [ ] Expected failure is captured in \`.halo/sdd/${id}/T${n}/tdd-evidence.json\`

"
    impl_tasks+="- [ ] T${n}: Implement behavior for AC-${ac}
  - ${ac_label}AC-${ac}
  - Mode: tdd
  - Scope: Implement the smallest path needed for AC-${ac}.
  - Interfaces:
    - Inputs: request
    - Outputs: response
    - Touched files/contracts: handler
  - Files: \`internal/handler/item.go\`
  - Verification: \`TestAC${ac}\`
  - Evidence:
    - Brief: \`.halo/sdd/${id}/T${n}/brief.md\`
    - Review package: \`.halo/sdd/${id}/T${n}/review-package.md\`
  - Done when:
    - [ ] AC-${ac} passes focused verification and evidence exists.

"
  done

  cat > "$dir/plan.md" << EOF
# Plan: ${id}

## Source

- Spec: \`halo/specs/${id}/spec.md\`
- Execution mode: tdd

## Implementation Notes

## Global Constraints

- Versions / dependencies: use existing Go module.
- Naming / style: keep AC test names.
- Security / permissions: no permission change.
- Data / migration: no migration.
- Compatibility: no API break.
- Out-of-scope: export behavior.

## Tasks

${red_tasks}${impl_tasks}
EOF
}
