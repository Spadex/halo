#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-user-report.md
# Root cause class: A. 词法「提及≠声明」（第 4 次复发：#7 → #8 → #9 → 本次）
# Fixed by: 1f993a4
#
# 一份 spec 只声明 AC-1..AC-3，却在四个位置提到**上游 spec 的 AC-14**：
# 自己的 Non-Goals 散文、自己 AC-3 行的单元格内、plan 的 Out-of-scope、
# RED-1 任务体的 Discriminating power 行。
#
# 修复前，六处门禁各自 grep 全文抽 AC token，于是 AC-14 被当成本 spec 的 AC：
# task-next 的 ac_refs 里多出 AC-14、plan-lint 要求 plan 覆盖 AC-14、
# ac-coverage 把 AC 总数算成 4、task-complete 索要 AC-14 的红绿证据。
# 修复引入了 _lib.sh 的 spec_declared_acs + narrow_acs_to_declared 两个共享谓词。
#
# fixture 见 tests/fixtures/ac/cross-spec-mentions/。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_install_fixture ac/cross-spec-mentions
}

# RED-1 收口需要三条 AC 的红绿证据。一次调用写一份多 AC 的证据文件。
write_cycle_evidence() {
  bash halo/kernel/orchestrator/sdd/tdd-evidence.sh cross-spec-ac T1 \
    --ac=AC-1 \
    --ac=AC-2 \
    --ac=AC-3 \
    --test=TestXsAC \
    --test-file=internal/handler/item_test.go \
    --red-command="go test ./internal/handler -run TestXsAC" \
    --red-exit=1 \
    --red-summary="handler not implemented" \
    --green-command="go test ./internal/handler -run TestXsAC" \
    --green-exit=0 \
    --green-summary="focused AC tests pass" \
    --refactor=none > /dev/null 2>&1
}

@test "task-next ac_refs excludes an upstream spec's AC" {
  run bash halo/kernel/orchestrator/sdd/task-next.sh cross-spec-ac --json
  assert_success
  # 语义比较，不断言格式化后的字面量：旧断言写死了 '["AC-1", "AC-2", "AC-3"]'
  # 的空格排布，改一下 JSON 缩进就会假红。
  # join 一次覆盖内容、顺序与「有没有多出来的元素」三件事——AC-14 泄漏进来就是多一个元素。
  run yq -e '.task_id == "RED-1" and (.ac_refs | join(",")) == "AC-1,AC-2,AC-3"' <<< "$output"
  assert_success
}

@test "plan-lint does not demand another spec's AC in plan.md" {
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh cross-spec-ac
  assert_success
  refute_output --partial "AC-14"
}

@test "ac-coverage counts only declared ACs, not in-cell cross-references" {
  run bash halo/kernel/delivery/gates/ac-coverage.sh halo/specs/cross-spec-ac/spec.md .
  assert_output --partial "Spec AC count: 3"
}

@test "task-complete ignores a cross-spec AC in a red task body" {
  write_cycle_evidence
  run bash halo/kernel/orchestrator/sdd/task-complete.sh cross-spec-ac RED-1
  assert_success
  run grep -cE '^- \[x\] RED-1:' halo/specs/cross-spec-ac/plan.md
  assert_output "1"
}
